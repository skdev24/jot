import Foundation
import UserNotifications

/// Turns dated to-dos into macOS notifications. Everything pending is
/// rebuilt from the notes on each change, so the files stay the only truth:
/// tick a to-do (in Jot or anywhere else) and its reminder disappears.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Clicking a notification: open this note at this text.
    var onOpen: (UUID, String) -> Void = { _, _ in }

    private let center = UNUserNotificationCenter.current()
    private var asked = false
    private static let limit = 60 // macOS keeps at most 64 pending per app.

    override init() {
        super.init()
        center.delegate = self
    }

    func sync(_ reminders: [Reminder]) {
        guard Prefs.defaults.bool(forKey: Prefs.reminders) else {
            center.removeAllPendingNotificationRequests()
            return
        }
        let now = Date()
        let hour = Prefs.defaults.integer(forKey: Prefs.reminderHour)
        let upcoming = reminders.compactMap { reminder -> (Reminder, Date)? in
            let fire = reminder.hasTime ? reminder.date : Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: reminder.date)
            guard let fire, fire > now else { return nil }
            return (reminder, fire)
        }
        .prefix(Self.limit)

        center.removeAllPendingNotificationRequests()
        guard upcoming.isEmpty == false else { return }
        authorize { [weak self] granted in
            guard granted, let self else { return }
            for (reminder, fire) in upcoming {
                let content = UNMutableNotificationContent()
                content.title = reminder.text.isEmpty ? "Reminder" : reminder.text
                content.subtitle = reminder.noteTitle
                content.sound = .default
                content.threadIdentifier = reminder.noteID.uuidString
                content.userInfo = ["note": reminder.noteID.uuidString, "text": reminder.text]
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                self.center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
            }
        }
    }

    /// Asks once, the first time a dated to-do exists — not at launch.
    private func authorize(_ done: @escaping @MainActor (Bool) -> Void) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                if status == .authorized || status == .provisional { return done(true) }
                guard status == .notDetermined, self.asked == false else { return done(false) }
                self.asked = true
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    Task { @MainActor in done(granted) }
                }
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["note"] as? String, let id = UUID(uuidString: raw) else { return }
        let text = info["text"] as? String ?? ""
        await MainActor.run { self.onOpen(id, text) }
    }
}
