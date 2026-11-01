import Foundation
import UserNotifications

var count = 0
func check(_ condition: @autoclosure () throws -> Bool, _ label: String) {
    guard try! condition() else { fatalError(label) }
    count += 1
}
let failure = NSError(domain: "Tests", code: 1)
final class Memory: ReminderPersistence {
    var entries: [SavedReminder] = []
    var fails = false
    var loadFails = false
    func load() throws -> [SavedReminder] { if loadFails { throw failure }; return entries }
    func save(_ reminders: [SavedReminder]) throws { if fails { throw failure }; entries = reminders }
}
final class Notifications: ReminderNotifications {
    var allowed = true
    var fails = false
    var pendingIDs = Set<String>()
    var requests: [SavedReminder] = []
    var cancellations: [String] = []
    var permissions: [Bool] = []
    var holdAuthorization = false
    var held: ((Result<Bool, Error>) -> Void)?
    func authorize(requestPermission: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        permissions.append(requestPermission)
        if holdAuthorization { held = completion } else { completion(.success(allowed)) }
    }
    func schedule(_ reminder: SavedReminder, completion: @escaping (Error?) -> Void) {
        requests.append(reminder)
        if fails { completion(failure) } else { pendingIDs.insert(reminder.notificationID); completion(nil) }
    }
    func cancel(_ identifiers: [String]) { cancellations += identifiers; identifiers.forEach { pendingIDs.remove($0) } }
    func pending(completion: @escaping (Set<String>) -> Void) { completion(pendingIDs) }
}
var now = Date(timeIntervalSince1970: 2_000_000_000)
let memory = Memory(), notifications = Notifications()
let store = ReminderStore(persistence: memory, notifications: notifications, now: { now })
check(store.reminders.isEmpty && !store.storageUnavailable, "Fresh storage")
store.newReminder(); store.draft = "  \n "
check(!store.canCreate, "Empty text rejected")
store.draft = String(repeating: "a", count: 4001)
check(!store.canCreate, "Overlong text rejected")
store.draft = "Remember this"; store.due = now
check(!store.canCreate, "Past date rejected")
store.due = now.addingTimeInterval(60); notifications.allowed = false; store.create()
check(store.reminders.isEmpty && store.draft == "Remember this" && !store.busy, "Denied permission preserves draft")
check(notifications.requests.isEmpty, "No scheduling on denial")
notifications.allowed = true; memory.fails = true; store.create()
check(store.reminders.isEmpty && notifications.requests.isEmpty, "No notification without successful storage")
memory.fails = false; store.create()
check(store.reminders.count == 1 && store.reminders[0].scheduled && !store.busy, "Created and scheduled")
check(store.draft.isEmpty && store.selected != nil && !store.composing, "Creation opens saved detail")
check(memory.entries == store.reminders, "State matches persisted records")
let first = store.reminders[0]
check(first.text == "Remember this" && first.link == nil, "Text context preserved")
let request = SystemReminderNotifications.request(for: first)
check(request.identifier == first.notificationID && request.content.userInfo["reminderID"] as? String == first.id.uuidString, "Notification routes by ID")
check(!request.content.body.contains(first.text), "Notification does not expose saved text")
check(request.content.sound == nil, "No unsolicited sound")
let trigger = request.trigger as! UNCalendarNotificationTrigger
check(!trigger.repeats && trigger.dateComponents.timeZone?.secondsFromGMT() == 0, "One-time trigger fixed to absolute date")
check(abs(trigger.nextTriggerDate()!.timeIntervalSince(first.due)) < 1, "Trigger date matches selected instant")
let restored = ReminderStore(persistence: memory, notifications: notifications, now: { now })
restored.restoreNotifications()
check(notifications.requests.count == 1, "Restore does not duplicate pending request")
notifications.pendingIDs.removeAll(); restored.restoreNotifications()
check(notifications.requests.count == 2 && notifications.permissions.last == false, "Missing future request restored without prompt")
now += 120; notifications.pendingIDs.removeAll(); restored.restoreNotifications()
check(notifications.requests.count == 2, "Overdue reminder is not re-alerted")
restored.show(first.id)
check(restored.selected?.text == first.text, "Notification ID restores exact context")
memory.fails = true; restored.remove(first.id)
check(restored.reminders.count == 1 && !notifications.cancellations.contains(first.notificationID), "Failed deletion preserves scheduled reminder")
memory.fails = false; restored.remove(first.id)
check(restored.reminders.isEmpty && notifications.cancellations.contains(first.notificationID), "Completion deletes storage and cancels notification")
restored.show(first.id)
check(restored.selected == nil && !restored.message.isEmpty, "Deleted notification handled safely")

store.newReminder(); store.draft = "https://example.com/path?q=test"; store.due = now.addingTimeInterval(60)
notifications.fails = true; store.create()
let unscheduled = store.reminders.last!
check(!unscheduled.scheduled && unscheduled.link?.host == "example.com", "Failure retains unscheduled link")
check(!store.message.isEmpty && !store.busy, "Scheduling error is visible")
notifications.fails = false; store.retry(unscheduled.id)
check(store.reminders.last!.scheduled && notifications.pendingIDs.contains(unscheduled.notificationID), "Retry schedules saved item")
for value in ["javascript:alert(1)", "file:///tmp/item", "https://user:password@example.com", "some text https://example.com", "https://"] {
    check(SavedReminder(id: UUID(), text: value, due: now, scheduled: false).link == nil, "Unsafe or mixed URL remains text")
}
check(SavedReminder(id: UUID(), text: "HTTP://example.com", due: now, scheduled: false).link != nil, "Case-insensitive web scheme")

let heldMemory = Memory(), heldNotifications = Notifications()
let heldStore = ReminderStore(persistence: heldMemory, notifications: heldNotifications, now: { now })
heldStore.draft = "Delayed permission"; heldStore.due = now.addingTimeInterval(2)
heldNotifications.holdAuthorization = true; heldStore.create()
check(heldStore.busy && !heldStore.canCreate, "Pending authorization blocks duplicate creation")
now += 3; heldNotifications.held?(.success(true))
check(heldStore.reminders.isEmpty && !heldStore.busy && !heldStore.draft.isEmpty, "Expired date during authorization preserves draft")
let broken = Memory(); broken.loadFails = true
let brokenStore = ReminderStore(persistence: broken, notifications: notifications, now: { now })
check(brokenStore.storageUnavailable && !brokenStore.canCreate, "Unreadable storage is not overwritten")
let before = notifications.requests.count; brokenStore.restoreNotifications()
check(notifications.requests.count == before, "No reconciliation on unreadable storage")

let orphanNotifications = Notifications()
let orphanID = SavedReminder.prefix + UUID().uuidString
orphanNotifications.pendingIDs = [orphanID, "unrelated.notification"]
let empty = ReminderStore(persistence: Memory(), notifications: orphanNotifications, now: { now })
empty.restoreNotifications()
check(orphanNotifications.cancellations == [orphanID] && orphanNotifications.pendingIDs.contains("unrelated.notification"), "Only owned orphan requests cancelled")
let fullMemory = Memory()
fullMemory.entries = (0..<32).map { SavedReminder(id: UUID(), text: "Item \($0)", due: now.addingTimeInterval(60), scheduled: false) }
let full = ReminderStore(persistence: fullMemory, notifications: Notifications(), now: { now })
full.draft = "Extra"
check(!full.canCreate, "Bounded active reminder count")

let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReminderChecks-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let file = ReminderFile(url: root.appendingPathComponent("reminders.json"))
check(try file.load().isEmpty, "Missing file is empty")
try file.save([first]); check(try file.load() == [first], "Atomic file roundtrip")
try Data("invalid json".utf8).write(to: file.url)
do { _ = try file.load(); fatalError("Corruption accepted") } catch { check(true, "Corruption detected") }
check(try String(contentsOf: file.url) == "invalid json", "Corruption left intact")
let duplicates = ReminderFile.Document(version: 1, reminders: [first, first])
try JSONEncoder().encode(duplicates).write(to: file.url)
do { _ = try file.load(); fatalError("Duplicate IDs accepted") } catch { check(true, "Duplicate IDs rejected") }
let repairMemory = Memory(), repairNotifications = Notifications()
let future = SavedReminder(id: UUID(), text: "Recover", due: now.addingTimeInterval(100), scheduled: false)
repairMemory.entries = [future]; repairNotifications.pendingIDs = [future.notificationID]
let repair = ReminderStore(persistence: repairMemory, notifications: repairNotifications, now: { now })
repair.restoreNotifications()
check(repair.reminders[0].scheduled && repairNotifications.requests.isEmpty, "Queue repairs accepted state without duplicate")
repairNotifications.allowed = false; repairNotifications.pendingIDs.removeAll(); repair.restoreNotifications()
check(!repair.reminders[0].scheduled && !repair.message.isEmpty && !repair.busy, "Revoked permission clears stale scheduled flag")
repairMemory.fails = true; repairNotifications.pendingIDs = [future.notificationID]; repair.restoreNotifications()
check(!repair.reminders[0].scheduled && !repair.busy, "Reconciliation save failure preserves state")
let fractional = SavedReminder(id: UUID(), text: "Fraction", due: Date(timeIntervalSince1970: 2_000_000_000.8), scheduled: false)
let fractionalTrigger = SystemReminderNotifications.request(for: fractional).trigger as! UNCalendarNotificationTrigger
check(fractionalTrigger.nextTriggerDate()! >= fractional.due && fractionalTrigger.nextTriggerDate()!.timeIntervalSince(fractional.due) < 1, "Calendar trigger never rounds earlier")
var replies: [String] = []
let reply = ReminderReply<String> { replies.append($0) }
reply.resolve("timeout"); reply.resolve("late approval")
check(replies == ["timeout"], "Late authorization cannot save after timeout")
let approvedReply = ReminderReply<String> { replies.append($0) }
approvedReply.resolve("approved"); approvedReply.resolve("timeout")
check(replies == ["timeout", "approved"], "Completed request ignores timeout")
store.show(unscheduled.id); store.show(UUID())
check(store.selected == nil && !store.composing, "Missing notification never reveals another selected context")
print("Reminders: \(count) checks passed")

let historyMemory = Memory(), historyNotifications = Notifications()
let history = ReminderStore(persistence: historyMemory, notifications: historyNotifications, now: { now })
history.draft = "History"; history.due = now.addingTimeInterval(3600); history.create()
let historyID = history.reminders[0].id
historyMemory.fails = true; history.complete(historyID)
check(history.completed.isEmpty && !historyNotifications.pendingIDs.isEmpty, "Failed completion preserves active notification")
historyMemory.fails = false; history.complete(historyID)
check(history.ordered.isEmpty && history.completed.count == 1, "Completion moves record into history")
check(historyNotifications.pendingIDs.isEmpty && history.selectedID == nil, "Completion cancels notification and returns to list")
let historyReload = ReminderStore(persistence: historyMemory, notifications: historyNotifications, now: { now })
historyReload.restoreNotifications()
check(historyReload.completed.count == 1 && historyNotifications.requests.count == 1, "Completed future reminder survives reload without rescheduling")
now = now.addingTimeInterval(6 * 3600 - 1); historyReload.purgeCompleted()
check(historyReload.completed.count == 1, "History retained before six hours")
now = now.addingTimeInterval(1); historyMemory.fails = true; historyReload.purgeCompleted()
check(historyReload.completed.count == 1, "Failed cleanup preserves history")
historyMemory.fails = false; historyReload.purgeCompleted()
check(historyReload.reminders.isEmpty && historyMemory.entries.isEmpty, "History expires at six hours and persists cleanup")
historyMemory.entries = [SavedReminder(id: UUID(), text: "Completed", due: now, scheduled: false, completedAt: now)]
let manualHistory = ReminderStore(persistence: historyMemory, notifications: historyNotifications, now: { now })
manualHistory.remove(manualHistory.completed[0].id)
check(manualHistory.reminders.isEmpty, "Completed reminder can be deleted immediately")
print("All \(count) reminder checks passed")
let undoMemory = Memory(), undoNotifications = Notifications()
let undoStore = ReminderStore(persistence: undoMemory, notifications: undoNotifications, now: { now })
undoStore.draft = "Undo"; undoStore.due = now.addingTimeInterval(600); undoStore.create()
let undoID = undoStore.reminders[0].id
undoStore.complete(undoID); undoMemory.fails = true; undoStore.reopen(undoID)
check(undoStore.completed.count == 1, "Failed reopen keeps completed record")
undoMemory.fails = false; undoStore.reopen(undoID)
check(undoStore.completed.isEmpty && undoStore.ordered.count == 1 && undoStore.ordered[0].scheduled, "Reopening future reminder restores notification")
undoStore.complete(undoID); now = now.addingTimeInterval(601)
let requestCount = undoNotifications.requests.count
undoStore.reopen(undoID)
check(undoStore.ordered.count == 1 && !undoStore.ordered[0].scheduled && undoNotifications.requests.count == requestCount, "Reopening overdue reminder does not replay notification")
print("All \(count) reminder checks passed")
