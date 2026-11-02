import HealthKit
import Observation
import os
import UserNotifications

// The access to Health and to notifications, asked together once, by « Before your first workout ». Whatever the
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
