import HalkoCore
import HealthKit
import SwiftData
import SwiftUI
import WatchKit

@main
struct HalkoWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var thumbnails: Thumbnails
    @State private var liveSession: LiveSessionStore
    @State private var permissions: Permissions
    @State private var recorder: WorkoutRecorder
    // Keeps what the iPhone sends and hands it the sessions done, for as long as the app runs.
    private let phone: PhoneLink?
    // The session in progress shared with the iPhone.
    private let live: LiveLink?

    init() {
        let thumbnails = Thumbnails()
        _thumbnails = State(initialValue: thumbnails)
        do {
            #if DEBUG
            if DemoData.isRequested {
                // Nothing from the iPhone either, nor anything of the watch's own session, Health or settings.
                container = try DemoData.container()
                _liveSession = State(initialValue: LiveSessionStore(fileURL: nil))
                _permissions = State(initialValue: Permissions(health: nil, defaults: nil))
                _recorder = State(initialValue: WorkoutRecorder.demo())
                phone = nil
                live = nil
                return
            }
            #endif
            container = try HalkoStore.container()
        } catch {
            fatalError("Cannot open the local database: \(error)")
        }
        let health = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
        let store = LiveSessionStore(fileURL: LiveSessionStore.defaultFileURL)
        let recorder = WorkoutRecorder(health: health)
        let live = LiveLink(container: container, store: store, recorder: recorder)
        WatchAppDelegate.workoutAsked = {
            live.startWorkout()
        }
        _liveSession = State(initialValue: store)
        _permissions = State(initialValue: Permissions(health: health, defaults: .standard))
        _recorder = State(initialValue: recorder)
        self.live = live
        phone = PhoneLink(container: container, thumbnails: thumbnails, live: live)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(thumbnails)
                .environment(liveSession)
                .environment(permissions)
                .environment(recorder)
                .task {
                    recorder.recover(sessionID: liveSession.state?.sessionID)
                    await ExerciseLibrary.install(in: container)
                }
                // A session of the iPhone found with the watch asleep: its workout could not start then.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        live?.startWorkout()
                    }
                }
        }
        .modelContainer(container)
    }
}

// The iPhone asks the watch to start the workout of the session it has just started.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    static var workoutAsked: (() -> Void)?

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Self.workoutAsked?()
    }
}

// The workouts; the session in progress instead, without the rest of the app, then its summary once saved.
private struct RootView: View {
    @Environment(LiveSessionStore.self) private var store
    @State private var finished: Session?

    var body: some View {
        if let finished = finished ?? store.finishedElsewhere {
            SessionSummaryView(session: finished) {
                self.finished = nil
                store.finishedElsewhere = nil
            }
        } else if let state = store.state {
            LiveSessionView(state: state) { session in
                finished = session
            }
        } else {
            NavigationStack {
                WorkoutsView()
            }
        }
    }
}
