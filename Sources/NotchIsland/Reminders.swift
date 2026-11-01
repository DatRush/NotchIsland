import Foundation
import Combine

struct SavedReminder: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let due: Date
    var scheduled: Bool
    var completedAt: Date? = nil
    var notificationID: String { Self.prefix + id.uuidString }
    static let prefix = "notchisland.reminder."
    var link: URL? {
        guard let parts = URLComponents(string: text),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              !text.contains(where: { $0.isWhitespace }),
              parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
}

protocol ReminderPersistence {
    func load() throws -> [SavedReminder]
    func save(_ reminders: [SavedReminder]) throws
}

struct ReminderFile: ReminderPersistence {
    struct Document: Codable { let version: Int; let reminders: [SavedReminder] }
    let url: URL
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchIsland/reminders.json")) { self.url = url }
    func load() throws -> [SavedReminder] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let doc = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard doc.version == 1, doc.reminders.filter({ $0.completedAt == nil }).count <= 32,
              Set(doc.reminders.map(\.id)).count == doc.reminders.count,
              doc.reminders.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 4000 && $0.due.timeIntervalSince1970.isFinite }) else {
            throw NSError(domain: "ReminderFile", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Некорректный файл напоминаний", "Invalid reminders file")])
        }
        return doc.reminders
    }
    func save(_ reminders: [SavedReminder]) throws {
        let data = try JSONEncoder().encode(Document(version: 1, reminders: reminders))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

// Implementations deliver callbacks on the main queue. Tests use a deterministic fake.
protocol ReminderNotifications {
    func authorize(requestPermission: Bool, completion: @escaping (Result<Bool, Error>) -> Void)
    func schedule(_ reminder: SavedReminder, completion: @escaping (Error?) -> Void)
    func cancel(_ identifiers: [String])
    func pending(completion: @escaping (Set<String>) -> Void)
}

final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [SavedReminder] = []
    @Published private(set) var busy = false
    @Published private(set) var storageUnavailable = false
    @Published var draft = ""
    @Published var due: Date
    @Published var composing = false
    @Published var selectedID: UUID?
    @Published var message = ""
    private let persistence: ReminderPersistence
    private let notifications: ReminderNotifications
    private var cleanup: AnyCancellable?
    private let now: () -> Date
    var selected: SavedReminder? { reminders.first { $0.id == selectedID } }
    var ordered: [SavedReminder] { reminders.filter { $0.completedAt == nil }.sorted { $0.due < $1.due } }
    var completed: [SavedReminder] { reminders.filter { $0.completedAt != nil }.sorted { $0.completedAt! > $1.completedAt! } }
    var canCreate: Bool {
        !busy && !storageUnavailable && ordered.count < 32 && validText(draft) && due > now()
    }
    init(persistence: ReminderPersistence = ReminderFile(), notifications: ReminderNotifications, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.notifications = notifications
        self.now = now
        cleanup = nil
        due = now().addingTimeInterval(3600)
        do { reminders = try persistence.load() }
        catch {
            storageUnavailable = true
            message = L("Не удалось прочитать напоминания. Файл сохранён без изменений: ", "Could not read reminders. The file was preserved unchanged: ") + error.localizedDescription
        }
        cleanup = Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.purgeCompleted() }
    }
    func complete(_ id: UUID) {
        guard !busy, !storageUnavailable,
              let index = reminders.firstIndex(where: { $0.id == id && $0.completedAt == nil }) else { return }
        var updated = reminders
        updated[index].completedAt = now()
        updated[index].scheduled = false
        guard commit(updated) else { return }
        notifications.cancel([updated[index].notificationID])
        selectedID = nil
        message = ""
    }
    func reopen(_ id: UUID) {
        guard !busy, !storageUnavailable, ordered.count < 32,
              let index = reminders.firstIndex(where: { $0.id == id && $0.completedAt != nil }) else { return }
        var updated = reminders
        updated[index].completedAt = nil
        updated[index].scheduled = false
        guard commit(updated) else { return }
        message = ""
        if updated[index].due > now() { retry(id) }
    }
    func purgeCompleted() {
        guard !busy, !storageUnavailable else { return }
        let expired = reminders.filter { $0.completedAt.map { now().timeIntervalSince($0) >= 6 * 3600 } ?? false }
        guard !expired.isEmpty else { return }
        let ids = Set(expired.map(\.id))
        guard commit(reminders.filter { !ids.contains($0.id) }) else { return }
        notifications.cancel(expired.map(\.notificationID))
        if let selectedID, ids.contains(selectedID) { self.selectedID = nil }
    }
    private func validText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 4000
    }
    private func commit(_ updated: [SavedReminder]) -> Bool {
        do { try persistence.save(updated); reminders = updated; return true }
        catch { message = L("Не удалось сохранить напоминания: ", "Could not save reminders: ") + error.localizedDescription; return false }
    }
    func newReminder() {
        guard !busy else { return }
        selectedID = nil
        composing = true
        message = ""
        if due <= now() { due = now().addingTimeInterval(3600) }
    }
    func show(_ id: UUID) {
        guard reminders.contains(where: { $0.id == id }) else {
            selectedID = nil
            composing = false
            message = L("Это напоминание уже удалено.", "This reminder was already deleted."); return
        }
        selectedID = id
        composing = false
        message = ""
    }
    func create() {
        guard canCreate else { message = L("Нужны текст до 4000 символов, будущее время и менее 32 напоминаний.", "Enter up to 4,000 characters, choose a future time and keep fewer than 32 reminders."); return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = due
        busy = true
        message = ""
        notifications.authorize(requestPermission: true) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): self.message = L("Не удалось запросить уведомления: ", "Could not request notifications: ") + error.localizedDescription; self.busy = false
            case .success(false): self.message = L("Разрешите уведомления NotchIsland в Системных настройках → Уведомления. Черновик сохранён.", "Allow NotchIsland notifications in System Settings → Notifications. Your draft was saved."); self.busy = false
            case .success(true):
                guard date > self.now() else { self.message = L("Выбранное время уже прошло. Укажите новое.", "The selected time has passed. Choose a new time."); self.busy = false; return }
                let reminder = SavedReminder(id: UUID(), text: text, due: date, scheduled: false)
                guard self.commit(self.reminders + [reminder]) else { self.busy = false; return }
                self.draft = ""
                self.composing = false
                self.selectedID = reminder.id
                self.schedule(reminder) { self.busy = false }
            }
        }
    }
    private func schedule(_ reminder: SavedReminder, completion: @escaping () -> Void) {
        notifications.schedule(reminder) { [weak self] error in
            guard let self else { completion(); return }
            guard let index = self.reminders.firstIndex(where: { $0.id == reminder.id }) else {
                self.notifications.cancel([reminder.notificationID]); completion(); return
            }
            if let error {
                self.message = L("Напоминание сохранено, но уведомление не поставлено: ", "Reminder saved, but no notification scheduled: ") + error.localizedDescription
            } else {
                var updated = self.reminders
                updated[index].scheduled = true
                if !self.commit(updated) { self.notifications.cancel([reminder.notificationID]) }
            }
            completion()
        }
    }
    func retry(_ id: UUID) {
        guard !busy, !storageUnavailable, let reminder = reminders.first(where: { $0.id == id }), reminder.completedAt == nil, reminder.due > now() else { return }
        busy = true
        message = ""
        notifications.authorize(requestPermission: true) { [weak self] result in
            guard let self else { return }
            if case .success(true) = result {
                self.schedule(reminder) { self.busy = false }
            } else {
                self.message = L("Уведомления недоступны. Разрешите их в Системных настройках → Уведомления.", "Notifications unavailable. Allow them in System Settings → Notifications.")
                self.busy = false
            }
        }
    }
    func remove(_ id: UUID) {
        guard !busy, !storageUnavailable, let reminder = reminders.first(where: { $0.id == id }) else { return }
        guard commit(reminders.filter { $0.id != id }) else { return }
        notifications.cancel([reminder.notificationID])
        if selectedID == id { selectedID = nil }
        message = ""
    }
    // Reconcile accepted future requests after a restart, without prompting or re-alerting overdue items.
    func restoreNotifications() {
        guard !busy, !storageUnavailable else { return }
        purgeCompleted()
        busy = true
        notifications.pending { [weak self] pending in
            guard let self else { return }
            let owned = Set(self.ordered.map(\.notificationID))
            self.notifications.cancel(Array(pending.filter { $0.hasPrefix(SavedReminder.prefix) && !owned.contains($0) }))
            // Reflect the actual system queue even when permission was revoked or the
            // app stopped between adding a request and persisting its accepted state.
            let reconciled = self.reminders.map { reminder -> SavedReminder in
                var updated = reminder
                if reminder.completedAt != nil { updated.scheduled = false }
                else if reminder.due > self.now() { updated.scheduled = pending.contains(reminder.notificationID) }
                return updated
            }
            if reconciled != self.reminders && !self.commit(reconciled) { self.busy = false; return }
            let missing = self.reminders.filter { $0.completedAt == nil && $0.due > self.now() && !pending.contains($0.notificationID) }
            guard !missing.isEmpty else { self.busy = false; return }
            self.notifications.authorize(requestPermission: false) { [weak self] result in
                guard let self else { return }
                guard case .success(true) = result else {
                    self.message = L("Есть напоминания без уведомлений. Проверьте разрешение в Системных настройках → Уведомления.", "Some reminders have no notifications. Check permission in System Settings → Notifications.")
                    self.busy = false
                    return
                }
                self.restore(missing, index: 0)
            }
        }
    }
    private func restore(_ items: [SavedReminder], index: Int) {
        guard index < items.count else { busy = false; return }
        let reminder = items[index]
        if reminder.due <= now() { restore(items, index: index + 1); return }
        schedule(reminder) { [weak self] in self?.restore(items, index: index + 1) }
    }
}

// Main-queue one-shot completion: a late authorization answer must not save a
// reminder after the UI has timed out and returned control to its user.
final class ReminderReply<Value> {
    private var completion: ((Value) -> Void)?
    init(_ completion: @escaping (Value) -> Void) { self.completion = completion }
    func resolve(_ value: Value) {
        let callback = completion
        completion = nil
        callback?(value)
    }
}
