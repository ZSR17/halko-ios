import HealthKit
import Observation
import os
import UserNotifications

// The access to Health and to notifications, asked together once, by « Before your first workout », and only if the
// system still has something to ask on this device: an answer, yes or no, is never asked for again. Whatever the
// answers, the app works the same; refused, Health shows nothing and no notification comes.
@MainActor
@Observable
final class Permissions {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "health")
    private static let askedKey = "permissionsAsked"

    private(set) var asked: Bool
    // Without them (the interface tests' sample data), nothing is asked of the system nor kept.
    private let health: HKHealthStore?
    private let defaults: UserDefaults?

    init(health: HKHealthStore?, defaults: UserDefaults?) {
        self.health = health
        self.defaults = defaults
        asked = defaults?.bool(forKey: Self.askedKey) ?? false
    }

    // Everything may have been answered already, from the other device if the system shares the answers.
    func checkAnswered() async {
        guard !asked, let defaults else { return }
        if let health {
            let status = await withCheckedContinuation { continuation in
                health.getRequestStatusForAuthorization(toShare: HealthTypes.share, read: HealthTypes.read) { @Sendable status, _ in
                    continuation.resume(returning: status)
                }
            }
            guard status == .unnecessary else { return }
        }
        let notifications = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        guard notifications != .notDetermined else { return }
        asked = true
        defaults.set(true, forKey: Self.askedKey)
    }

    // Health first, then notifications.
    func request() async {
        if let health {
            do {
                try await health.requestAuthorization(toShare: HealthTypes.share, read: HealthTypes.read)
            } catch {
                Self.logger.error("Cannot ask for Health: \(String(describing: error))")
            }
        }
        if defaults != nil {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                Self.logger.error("Cannot ask for notifications: \(String(describing: error))")
            }
        }
        asked = true
        defaults?.set(true, forKey: Self.askedKey)
    }
}
