import Foundation
import os
import UserNotifications

// The end of the rest, notified at its absolute time even with the iPhone locked or in another app: moved when the
// rest is shortened or lengthened, removed when it is skipped or the session ends. Only when notifications are
// allowed; in the app, the session shows the end itself.
enum RestAlert {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")
    private static let identifier = "rest-end"

    static func schedule(at end: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        guard let end, end > .now, await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest over")
        content.body = String(localized: "Time for the next set.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        } catch {
            logger.error("Cannot notify the end of the rest: \(String(describing: error))")
        }
    }
}
