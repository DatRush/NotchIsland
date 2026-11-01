import AppKit
import UserNotifications

final class SystemReminderNotifications: NSObject, ReminderNotifications, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var openReminder: ((UUID) -> Void)?
    func attach() { center.delegate = self }
    func authorize(requestPermission: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        let reply = ReminderReply(completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            reply.resolve(.failure(NSError(domain: "Reminders", code: 2, userInfo: [NSLocalizedDescriptionKey:
                L("macOS не ответила на запрос разрешения. Проверьте системный диалог и повторите попытку.", "macOS did not respond to the permission request. Check the system dialog and try again.")])))
        }
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined && requestPermission {
                self.center.requestAuthorization(options: [.alert]) { allowed, error in
                    DispatchQueue.main.async { reply.resolve(error.map { .failure($0) } ?? .success(allowed)) }
                }
            } else {
                let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                DispatchQueue.main.async { reply.resolve(.success(allowed)) }
            }
        }
    }
    static func request(for reminder: SavedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = L("Напоминание · NotchIsland", "Reminder · NotchIsland")
        content.body = L("Пора вернуться к сохранённому тексту или ссылке.", "Time to return to your saved text or link.")
        content.userInfo = ["reminderID": reminder.id.uuidString]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: ceil(reminder.due.timeIntervalSince1970)))
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: reminder.notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
    func schedule(_ reminder: SavedReminder, completion: @escaping (Error?) -> Void) {
        guard reminder.due > Date() else {
            completion(NSError(domain: "Reminders", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Время уже прошло", "The time has already passed")]))
            return
        }
        center.add(Self.request(for: reminder)) { error in DispatchQueue.main.async { completion(error) } }
    }
    func cancel(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    func pending(completion: @escaping (Set<String>) -> Void) {
        center.getPendingNotificationRequests { requests in
            DispatchQueue.main.async { completion(Set(requests.map(\.identifier))) }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let raw = response.notification.request.content.userInfo["reminderID"] as? String,
              let id = UUID(uuidString: raw) else { completionHandler(); return }
        DispatchQueue.main.async { [weak self] in self?.openReminder?(id); completionHandler() }
    }
}
