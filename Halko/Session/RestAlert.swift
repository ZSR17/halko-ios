import Foundation
import os
import UserNotifications

// The end of the rest, notified at its absolute time even with the device locked or in another app, with the set that
// follows: moved when the rest is shortened or lengthened, removed when it is skipped or the session ends. Only when
// notifications are allowed; in the app, the session shows the end itself.
enum RestAlert {
    struct Request: Equatable {
        let end: Date
        // The set that follows.
        let body: String
        var title = String(localized: "Rest over")
    }

    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")
    private static let identifier = "rest-end"

    // Nil: no rest, nothing to notify.
    static func schedule(_ request: Request?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        guard let request, request.end > .now, await center.notificationSettings().authorizationStatus == .authorized else { return }
        let end = request.end
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
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
