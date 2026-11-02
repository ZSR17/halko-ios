import HalkoCore
import HealthKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct HalkoApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    private let container: ModelContainer
    @State private var liveSession: LiveSessionStore
    @State private var permissions: Permissions
    @State private var recorder: WorkoutRecorder

    init() {
        do {
            #if DEBUG
            if DemoData.isRequested {
                container = try DemoData.container()
                // The device's own session in progress, its Health and its settings are never touched either.
                _liveSession = State(initialValue: LiveSessionStore(fileURL: nil))
                _permissions = State(initialValue: Permissions(health: nil, defaults: nil))
                _recorder = State(initialValue: WorkoutRecorder(health: nil))
                return
            }
            #endif
            container = try HalkoStore.container()
            _liveSession = State(initialValue: LiveSessionStore(fileURL: LiveSessionStore.defaultFileURL))
            let health = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
            _permissions = State(initialValue: Permissions(health: health, defaults: .standard))
            _recorder = State(initialValue: WorkoutRecorder(health: health))
        } catch {
            fatalError("Cannot open the local database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(liveSession)
                .environment(permissions)
                .environment(recorder)
                .task {
                    recorder.recover(sessionID: liveSession.state?.sessionID)
                    await ExerciseLibrary.install(in: container)
                }
                .task(id: liveSession.state?.restEndsAt) {
                    await RestAlert.schedule(at: liveSession.state?.restEndsAt)
                }
        }
        .modelContainer(container)
    }
}

// In the app, the end of the rest only rings: the session shows it already.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.sound]
    }
}
