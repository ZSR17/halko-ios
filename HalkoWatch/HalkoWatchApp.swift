import HalkoCore
import HealthKit
import SwiftData
import SwiftUI

@main
struct HalkoWatchApp: App {
    private let container: ModelContainer
    @State private var thumbnails: Thumbnails
    @State private var liveSession: LiveSessionStore
    @State private var permissions: Permissions
    @State private var recorder: WorkoutRecorder
    // Keeps what the iPhone sends and hands it the sessions done, for as long as the app runs.
    private let phone: PhoneLink?

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
                _recorder = State(initialValue: WorkoutRecorder(health: nil))
                phone = nil
                return
            }
            #endif
            container = try HalkoStore.container()
        } catch {
            fatalError("Cannot open the local database: \(error)")
        }
        let health = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
        _liveSession = State(initialValue: LiveSessionStore(fileURL: LiveSessionStore.defaultFileURL))
        _permissions = State(initialValue: Permissions(health: health, defaults: .standard))
        _recorder = State(initialValue: WorkoutRecorder(health: health))
        phone = PhoneLink(container: container, thumbnails: thumbnails)
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
        }
        .modelContainer(container)
    }
}

// The workouts; the session in progress instead, without the rest of the app, then its summary once saved.
private struct RootView: View {
    @Environment(LiveSessionStore.self) private var store
    @State private var finished: Session?

    var body: some View {
        if let finished {
            SessionSummaryView(session: finished) {
                self.finished = nil
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
