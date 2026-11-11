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
    // What the system says of one access, written in full in the settings.
    enum Access {
        case allowed, refused, notAsked
    }

    private static let logger = Logger(subsystem: "com.zsr.halko", category: "health")
    private static let askedKey = "permissionsAsked"

    private(set) var asked: Bool
    // Of saving the workouts; Health never tells whether reading was allowed.
    private(set) var healthAccess = Access.notAsked
    private(set) var notificationAccess = Access.notAsked
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
        await requestHealth()
        await requestNotifications()
        asked = true
        defaults?.set(true, forKey: Self.askedKey)
    }

    // One of them, from the settings, before any workout.
    func requestHealth() async {
        if let health {
            do {
                try await health.requestAuthorization(toShare: HealthTypes.share, read: HealthTypes.read)
            } catch {
                Self.logger.error("Cannot ask for Health: \(String(describing: error))")
            }
        }
        await refresh()
    }

    func requestNotifications() async {
        if defaults != nil {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                Self.logger.error("Cannot ask for notifications: \(String(describing: error))")
            }
        }
        await refresh()
    }

    // Read again from the system, where they can change at any time.
    func refresh() async {
        if let health {
            healthAccess = switch health.authorizationStatus(for: HKObjectType.workoutType()) {
            case .sharingAuthorized: .allowed
            case .sharingDenied: .refused
            default: .notAsked
            }
        }
        guard defaults != nil else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAccess = switch settings.authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .refused
        // Authorized, quietly or for a while.
        default: .allowed
        }
    }
}
