import Foundation
import Combine
import EventKit
import AppKit

struct AppleReminderList: Identifiable, Equatable {
    let id: String
    let title: String
    let account: String
}
struct AppleReminder: Identifiable, Equatable {
    let id: String
    let text: String
    let notes: String
    let due: Date?
    let hasTime: Bool
    let isCompleted: Bool
    let completedAt: Date?
    let url: URL?
    var link: URL? {
        if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url }
        return SavedReminder(id: UUID(), text: text, due: .distantFuture, scheduled: false).link
    }
}
protocol AppleReminderRepository {
    var authorized: Bool { get }
    func authorize(_ completion: @escaping (Result<Bool, Error>) -> Void)
    func lists() -> [AppleReminderList]
    func createIslandList() throws -> String
    func fetch(list: String?, completion: @escaping (Result<[AppleReminder], Error>) -> Void)
    func save(id: String?, list: String, text: String, due: Date?, changeDate: Bool, migration: SavedReminder?) throws
    func finishImport(_ id: UUID) throws
    func complete(id: String, value: Bool) throws
    func remove(id: String) throws
}
func reminderError(_ message: String) -> Error {
    NSError(domain: "AppleReminders", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
final class EventKitReminders: AppleReminderRepository {
    private let events = EKEventStore()
    private var importIDs: [UUID: String] = [:]
    var authorized: Bool {
        if #available(macOS 14, *) { return EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
        return EKEventStore.authorizationStatus(for: .reminder) == .authorized
    }
    func authorize(_ completion: @escaping (Result<Bool, Error>) -> Void) {
        let reply = ReminderReply(completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            reply.resolve(.failure(reminderError(L("macOS не ответила на запрос. Проверьте разрешение и повторите подключение.", "macOS did not respond. Check permissions and try connecting again."))))
        }
        let callback: EKEventStoreRequestAccessCompletionHandler = { allowed, error in
            DispatchQueue.main.async { reply.resolve(error.map { .failure($0) } ?? .success(allowed)) }
        }
        if #available(macOS 14, *) { events.requestFullAccessToReminders(completion: callback) }
        else { events.requestAccess(to: .reminder, completion: callback) }
    }
    func lists() -> [AppleReminderList] {
        events.calendars(for: .reminder).filter(\.allowsContentModifications).map {
            AppleReminderList(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title)
        }.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }
    func createIslandList() throws -> String {
        guard let source = events.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased() == "icloud" }) else {
            throw reminderError(L("Включите «Напоминания» в iCloud или выберите существующий список ниже.", "Enable Reminders in iCloud or choose an existing list below."))
        }
        let list = EKCalendar(for: .reminder, eventStore: events)
        list.title = "NotchIsland"; list.source = source
        try events.saveCalendar(list, commit: true)
        return list.calendarIdentifier
    }
    func fetch(list: String?, completion: @escaping (Result<[AppleReminder], Error>) -> Void) {
        var calendars: [EKCalendar]?
        if let list {
            guard let calendar = events.calendar(withIdentifier: list) else { completion(.failure(reminderError(L("Список удалён. Выберите другой.", "This list was deleted. Choose another.")))); return }
            calendars = [calendar]
        }
        let predicate = events.predicateForReminders(in: calendars)
        events.fetchReminders(matching: predicate) { reminders in
            DispatchQueue.main.async {
                guard let reminders else { completion(.failure(reminderError(L("Не удалось прочитать напоминания Apple.", "Could not read Apple Reminders.")))); return }
                for item in reminders {
                    for line in (item.notes ?? "").components(separatedBy: "\n") where line.hasPrefix("NotchIsland import: ") {
                        if let id = UUID(uuidString: String(line.dropFirst("NotchIsland import: ".count))) { self.importIDs[id] = item.calendarItemIdentifier }
                    }
                }
                completion(.success(reminders.map { item in
                    var due: Date?
                    if let components = item.dueDateComponents {
                        due = (components.calendar ?? Calendar.current).date(from: components)
                    }
                    return AppleReminder(id: item.calendarItemIdentifier, text: item.title ?? "", notes: item.notes ?? "", due: due,
                                         hasTime: item.dueDateComponents?.hour != nil, isCompleted: item.isCompleted,
                                         completedAt: item.completionDate, url: item.url)
                }))
            }
        }
    }
    func save(id: String?, list: String, text: String, due: Date?, changeDate: Bool, migration: SavedReminder?) throws {
        let item: EKReminder
        if let id { item = try existing(id) }
        else {
            guard let calendar = events.calendar(withIdentifier: list), calendar.allowsContentModifications else { throw reminderError(L("Список недоступен для записи.", "This list is not writable.")) }
            item = EKReminder(eventStore: events); item.calendar = calendar
        }
        item.title = text
        if id == nil || changeDate {
            item.dueDateComponents = due.map { Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: $0) }
            item.alarms = due.flatMap { $0 > Date() ? [EKAlarm(absoluteDate: $0)] : nil }
        }
        if let migration {
            item.notes = AppleReminderMigration.marker(migration.id)
            item.url = migration.link
            if let completed = migration.completedAt { item.completionDate = completed; item.alarms = nil }
        }
        try events.save(item, commit: true)
        if let migration { importIDs[migration.id] = item.calendarItemIdentifier }
    }
    func finishImport(_ id: UUID) throws {
        guard let appleID = importIDs[id] else { return }
        let item = try existing(appleID)
        let notes = (item.notes ?? "").components(separatedBy: "\n").filter { $0 != AppleReminderMigration.marker(id) }.joined(separator: "\n")
        item.notes = notes.isEmpty ? nil : notes
        try events.save(item, commit: true)
        importIDs.removeValue(forKey: id)
    }
    private func existing(_ id: String) throws -> EKReminder {
        guard let item = events.calendarItem(withIdentifier: id) as? EKReminder,
              item.calendar.allowsContentModifications else { throw reminderError(L("Напоминание удалено или недоступно для изменения. Обновите список.", "This reminder was deleted or cannot be edited. Refresh the list.")) }
        return item
    }
    func complete(id: String, value: Bool) throws {
        let item = try existing(id); item.isCompleted = value
        try events.save(item, commit: true)
    }
    func remove(id: String) throws { try events.remove(existing(id), commit: true) }
}

// Source data remains intact. The ledger prevents reimport even if a migrated
// reminder is subsequently deleted. The marker recovers a crash before ledger write.
struct AppleReminderMigration {
    let file: ReminderFile
    let directory: URL
    init(file: ReminderFile = ReminderFile(), directory: URL? = nil) {
        self.file = file; self.directory = directory ?? file.url.deletingLastPathComponent()
    }
    static func marker(_ id: UUID) -> String { "NotchIsland import: " + id.uuidString }
    func run(existing: [AppleReminder], save: (SavedReminder) throws -> Void, cancel: ([String]) -> Void, finish: (UUID) throws -> Void = { _ in }) throws {
        let old = try file.load()
        guard !old.isEmpty else { return }
        let backup = directory.appendingPathComponent("reminders-before-apple.json")
        if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: file.url, to: backup) }
        let ledger = directory.appendingPathComponent("apple-reminders-imported.json")
        var imported = Set<UUID>()
        if FileManager.default.fileExists(atPath: ledger.path) { imported = try JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: ledger)) }
        for item in old {
            if !imported.contains(item.id) {
                if !existing.contains(where: { $0.notes.components(separatedBy: "\n").contains(Self.marker(item.id)) }) { try save(item) }
                imported.insert(item.id)
                try JSONEncoder().encode(imported).write(to: ledger, options: .atomic)
            }
            cancel([item.notificationID])
            try finish(item.id)
        }
    }
}

final class AppleReminderStore: ObservableObject {
    @Published private(set) var reminders: [AppleReminder] = []
    @Published private(set) var lists: [AppleReminderList] = []
    @Published private(set) var authorized = false
    @Published private(set) var busy = false
    @Published var listID = ""
    @Published var choosingList = false
    @Published var draft = ""
    @Published var due = Date().addingTimeInterval(3600)
    // Draft mode belongs to the store, just like text and due date. Views are transient.
    @Published var interval = -1
    var usesDate: Bool {
        get { interval != -1 }
        set { interval = newValue ? 0 : -1 }
    }
    @Published var composing = false
    @Published var selectedID: String?
    @Published var message = ""
    private var editingID: String?
    private var originalDate: Date?
    private let repository: AppleReminderRepository
    private let migration: AppleReminderMigration
    private let cancelLegacy: ([String]) -> Void
    private let defaults: UserDefaults
    private var subscriptions = Set<AnyCancellable>()
    private var generation = 0
    private var refreshPending = false
    var storageUnavailable: Bool { !authorized || listID.isEmpty }
    var selected: AppleReminder? { reminders.first { $0.id == selectedID } }
    var ordered: [AppleReminder] { reminders.filter { !$0.isCompleted }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) } }
    var completed: [AppleReminder] { Self.visibleCompleted(reminders, now: Date()) }
    static func visibleCompleted(_ items: [AppleReminder], now: Date) -> [AppleReminder] {
        items.filter { $0.isCompleted && $0.completedAt.map { now.timeIntervalSince($0) < 21600 } == true }
            .sorted { $0.completedAt! > $1.completedAt! }
    }
    var listTitle: String { lists.first { $0.id == listID }.map { $0.title + " · " + $0.account } ?? L("Выбрать список", "Choose list") }
    init(repository: AppleReminderRepository = EventKitReminders(), migration: AppleReminderMigration = AppleReminderMigration(),
         defaults: UserDefaults = .standard, cancelLegacy: @escaping ([String]) -> Void) {
        self.repository = repository; self.migration = migration; self.defaults = defaults; self.cancelLegacy = cancelLegacy
        NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
    }
    func connect() {
        guard !busy else { return }; busy = true; message = ""
        repository.authorize { [weak self] result in
            guard let self else { return }; self.busy = false
            switch result {
            case .success(true): self.refresh()
            case .success(false): self.message = L("Разрешите доступ в настройках macOS → Конфиденциальность и безопасность → Напоминания.", "Allow access in macOS Settings → Privacy & Security → Reminders.")
            case .failure(let error): self.message = error.localizedDescription
            }
        }
    }
    func refresh() {
        guard !busy else { refreshPending = true; return }
        authorized = repository.authorized
        guard authorized else { reminders = []; lists = []; return }
        lists = repository.lists()
        if !lists.contains(where: { $0.id == listID }) {
            listID = lists.first { $0.id == defaults.string(forKey: "appleReminderList") }?.id ?? lists.first { $0.title == "NotchIsland" }?.id ?? ""
        }
        guard !listID.isEmpty else { choosingList = true; return }
        busy = true; generation += 1
        let request = generation
        repository.fetch(list: listID) { [weak self] result in
            guard let self, request == self.generation else { return }
            if case .success(let items) = result { self.reminders = items }
            if case .failure(let error) = result { self.message = error.localizedDescription }
            self.finish()
        }
    }
    private func finish() {
        busy = false
        if refreshPending { refreshPending = false; refresh() }
    }
    func selectList(_ id: String) {
        guard !busy else { return }
        listID = id; defaults.set(id, forKey: "appleReminderList"); selectedID = nil; choosingList = false
        reminders = []; message = ""; refresh()
    }
    func createList() {
        guard !busy else { return }
        do { let id = try repository.createIslandList(); lists = repository.lists(); selectList(id) }
        catch { message = error.localizedDescription }
    }
    func importLegacy() {
        guard !busy, !storageUnavailable else { return }; busy = true; message = ""
        let target = listID
        repository.fetch(list: nil) { [weak self] result in
            guard let self else { return }
            do {
                let existing = try result.get()
                try self.migration.run(existing: existing, save: {
                    try self.repository.save(id: nil, list: target, text: $0.text, due: $0.due, changeDate: true, migration: $0)
                }, cancel: self.cancelLegacy, finish: self.repository.finishImport)
                self.message = L("Перенос завершён. Исходный файл сохранён.", "Import complete. The original file was preserved.")
            } catch { self.message = L("Перенос не завершён: ", "Import incomplete: ") + error.localizedDescription }
            self.finish(); self.refresh()
        }
    }
    func newReminder() {
        editingID = nil; selectedID = nil; draft = ""; usesDate = false
        due = Date().addingTimeInterval(3600); composing = true; message = ""
    }
    func edit(_ item: AppleReminder) {
        editingID = item.id; originalDate = item.due; draft = item.text
        usesDate = item.due != nil; due = item.due ?? Date().addingTimeInterval(3600); composing = true
    }
    func show(_ id: String) { selectedID = id; composing = false; message = "" }
    func create(now: Date = Date()) {
        guard !busy, !storageUnavailable else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { message = L("Введите текст напоминания.", "Enter reminder text."); return }
        let date = interval > 0 ? now.addingTimeInterval(Double(interval)) : (usesDate ? due : nil)
        do {
            try repository.save(id: editingID, list: listID, text: text, due: date, changeDate: editingID == nil || originalDate != date, migration: nil)
            composing = false; draft = ""; message = ""; refresh()
        } catch { message = error.localizedDescription }
    }
    func complete(_ id: String) { setCompleted(id, value: true) }
    func reopen(_ id: String) { setCompleted(id, value: false) }
    private func setCompleted(_ id: String, value: Bool) {
        guard !busy else { return }
        do { try repository.complete(id: id, value: value); message = ""; selectedID = nil; refresh() }
        catch { message = error.localizedDescription }
    }
    func remove(_ id: String) {
        guard !busy else { return }
        do { try repository.remove(id: id); selectedID = nil; message = ""; refresh() }
        catch { message = error.localizedDescription }
    }
}
