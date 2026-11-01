import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) { guard value() else { fatalError(label) }; checks += 1 }
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let file = ReminderFile(url: root.appendingPathComponent("reminders.json"))
let first = SavedReminder(id: UUID(), text: "Keep me", due: Date().addingTimeInterval(600), scheduled: true)
let second = SavedReminder(id: UUID(), text: "Done", due: Date(), scheduled: false, completedAt: Date())
try file.save([first, second])
let migration = AppleReminderMigration(file: file)
var saved: [SavedReminder] = [], cancelled: [String] = []
try migration.run(existing: [], save: { saved.append($0) }, cancel: { cancelled += $0 })
check(saved == [first, second], "Both active and completed records migrate")
check(cancelled.count == 2, "Legacy requests cancelled after migration")
check(FileManager.default.fileExists(atPath: root.appendingPathComponent("reminders-before-apple.json").path), "Backup created")
check(try! file.load() == [first, second], "Original source unchanged")
try migration.run(existing: [], save: { saved.append($0) }, cancel: { cancelled += $0 })
check(saved.count == 2, "Ledger prevents reimport even after Apple deletion")
try FileManager.default.removeItem(at: root.appendingPathComponent("apple-reminders-imported.json"))
let apple = AppleReminder(id: "apple-1", text: first.text, notes: AppleReminderMigration.marker(first.id), due: first.due, hasTime: true, isCompleted: false, completedAt: nil, url: nil)
saved = []
try migration.run(existing: [apple], save: { saved.append($0) }, cancel: { _ in })
check(saved == [second], "Marker recovers crash before journal save")
try FileManager.default.removeItem(at: root.appendingPathComponent("apple-reminders-imported.json"))
cancelled = []
do { try migration.run(existing: [], save: { _ in throw reminderError("Failed") }, cancel: { cancelled += $0 }); fatalError("Expected failure") } catch {}
check(cancelled.isEmpty, "Save failure keeps legacy notifications")
let completed = AppleReminder(id: "done", text: "Done", notes: "", due: nil, hasTime: false, isCompleted: true, completedAt: Date(timeIntervalSince1970: 100), url: nil)
check(AppleReminderStore.visibleCompleted([completed], now: Date(timeIntervalSince1970: 21699)).count == 1, "Visible before six hours")
check(AppleReminderStore.visibleCompleted([completed], now: Date(timeIntervalSince1970: 21700)).isEmpty, "Hidden at six hours without deleting")

final class Fake: AppleReminderRepository {
    var authorized = true
    var items: [AppleReminder] = []
    var saves = 0
    var lastDate: Date?
    var changedDate = false
    var failSave = false
    var completion: Bool?
    var removed: String?
    func authorize(_ completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(authorized)) }
    func lists() -> [AppleReminderList] { [AppleReminderList(id: "list", title: "NotchIsland", account: "iCloud")] }
    func createIslandList() throws -> String { "list" }
    func fetch(list: String?, completion: @escaping (Result<[AppleReminder], Error>) -> Void) { completion(.success(items)) }
    func save(id: String?, list: String, text: String, due: Date?, changeDate: Bool, migration: SavedReminder?) throws {
        if failSave { throw reminderError("Failed") }; saves += 1; lastDate = due; changedDate = changeDate
    }
    func finishImport(_ id: UUID) throws {}
    func complete(id: String, value: Bool) throws { completion = value }
    func remove(id: String) throws { removed = id }
}
let suite = "NotchIslandChecks." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let fake = Fake()
let store = AppleReminderStore(repository: fake, migration: migration, defaults: defaults, cancelLegacy: { _ in })
store.refresh()
check(store.authorized && store.listID == "list", "Finds dedicated list")
store.newReminder(); store.draft = "No date"; store.create()
check(fake.saves == 1 && fake.lastDate == nil && !store.composing, "Saves task without date")
store.newReminder(); store.draft = "Keep draft"; fake.failSave = true; store.create()
check(store.composing && store.draft == "Keep draft", "Save failure preserves draft")
fake.failSave = false; fake.items = [apple]; store.refresh(); store.edit(apple); store.draft = "Renamed"; store.create()
check(!fake.changedDate, "Title edit preserves existing alarms and all-day semantics")
store.edit(apple); store.usesDate = false; store.create()
check(fake.changedDate && fake.lastDate == nil, "Removing date changes alarm configuration")
store.complete(apple.id); check(fake.completion == true, "Completion written to Apple")
store.reopen(apple.id); check(fake.completion == false, "Reopen written to Apple")
store.remove(apple.id); check(fake.removed == apple.id, "Explicit deletion written to Apple")
fake.authorized = false; store.refresh()
check(!store.authorized && store.reminders.isEmpty, "Revocation clears displayed Apple data")
print("AppleReminders: \(checks) checks passed")
try? FileManager.default.removeItem(at: root.appendingPathComponent("apple-reminders-imported.json"))
saved = []
do {
    try migration.run(existing: [], save: { saved.append($0) }, cancel: { _ in }, finish: { _ in throw reminderError("Cleanup interrupted") })
} catch {}
check(saved.count == 1, "Interrupted marker cleanup occurs after first record saved")
try migration.run(existing: [], save: { saved.append($0) }, cancel: { _ in })
check(saved.count == 2, "Journal prevents duplicate after marker cleanup failure")
print("AppleReminders final: \(checks) checks passed")

// Recreating SwiftUI views must not recreate draft date state.
fake.authorized = true; store.refresh(); store.edit(apple)
var editor: RemindersView? = RemindersView(store: store)
editor = nil // island closes / another tab replaces its content
store.refresh()
editor = RemindersView(store: store)
check(store.interval == 0 && store.due == apple.due, "Dated edit survives view recreation and refresh")
store.create()
check(fake.lastDate == apple.due && !fake.changedDate, "Reopened editor preserves date and alarms")
store.newReminder(); store.draft = "Relative"; store.interval = 600
editor = nil; editor = RemindersView(store: store)
let saveTime = Date(timeIntervalSince1970: 2000000)
check(store.interval == 600 && store.composing, "Relative mode survives tab/island recreation")
store.create(now: saveTime)
check(fake.lastDate == saveTime.addingTimeInterval(600), "Interval starts at save, not first opening")
store.newReminder(); store.draft = "Absolute"; store.interval = 0; store.due = saveTime
editor = nil; editor = RemindersView(store: store); store.create()
check(fake.lastDate == saveTime, "New absolute draft retains selected date")
store.newReminder(); store.draft = "Undated"
editor = nil; editor = RemindersView(store: store); store.create()
check(fake.lastDate == nil && store.interval == -1, "New draft resets old mode and stays undated")
print("AppleReminders regression total: \(checks) checks passed")
