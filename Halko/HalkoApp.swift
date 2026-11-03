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
    private let activities: SessionActivities

    init() {
        do {
            #if DEBUG
            if DemoData.isRequested {
                // The device's own session in progress, its Health, its settings and its lock screen are never
                // touched either.
                self.init(
                    container: try DemoData.container(),
                    liveSession: LiveSessionStore(fileURL: nil),
                    permissions: Permissions(health: nil, defaults: nil),
                    recorder: WorkoutRecorder(health: nil),
                    showsActivity: false
                )
                return
            }
            #endif
            let health = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
            self.init(
                container: try HalkoStore.container(),
                liveSession: LiveSessionStore(fileURL: LiveSessionStore.defaultFileURL),
                permissions: Permissions(health: health, defaults: .standard),
                recorder: WorkoutRecorder(health: health),
                showsActivity: true
            )
        } catch {
            fatalError("Cannot open the local database: \(error)")
        }
    }

    private init(container: ModelContainer, liveSession: LiveSessionStore, permissions: Permissions, recorder: WorkoutRecorder, showsActivity: Bool) {
        let activities = SessionActivities(container: container, store: liveSession, recorder: recorder, showsActivity: showsActivity)
        // The buttons of the session outside the app run here, even with the app in the background.
        SessionControl.handler = { action in
            await activities.apply(action)
        }
        self.container = container
        self.activities = activities
        _liveSession = State(initialValue: liveSession)
        _permissions = State(initialValue: permissions)
        _recorder = State(initialValue: recorder)
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
                // Outside the app: the Live Activity and the end of the rest.
                .task(id: OutsideKey(state: liveSession.state, heartRate: recorder.heartRate.map { Int($0.rounded()) })) {
                    await activities.refresh()
                }
        }
        .modelContainer(container)
    }
}

// What the session shows outside the app depends on.
private struct OutsideKey: Equatable {
    let state: LiveState?
    let heartRate: Int?
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
