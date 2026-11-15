import HalkoCore
import os
import SwiftData
import SwiftUI

// Starts a session of a workout, or brings back the one in progress (one at a time, on any device); « Before your
// first workout » first, the first time. On the workout's page and on its card.
struct StartWorkoutButton<Label: View>: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

    let workout: Workout
    let label: Label
    @Query(filter: #Predicate<Session> { !$0.removed && $0.endedAt == nil }, sort: \Session.startedAt, order: .reverse)
    private var sessionsInProgress: [Session]
    @Environment(\.modelContext) private var context
    @Environment(LiveSessionStore.self) private var liveSession
    @Environment(Permissions.self) private var permissions
    @Environment(WorkoutRecorder.self) private var recorder
    // Another workout's session is in progress: one at a time.
    @State private var otherSession: Session?
    // « Before your first workout », then the session once it is closed.
    @State private var preparing = false
    @State private var prepared = false

    init(workout: Workout, @ViewBuilder label: () -> Label) {
        self.workout = workout
        self.label = label()
    }

    var body: some View {
        Button(action: start) {
            label
        }
        .sheet(isPresented: $preparing, onDismiss: startPrepared) {
            FirstWorkoutView {
                await permissions.request()
                prepared = true
                preparing = false
            }
        }
        .alert(
            "A session is already in progress",
            isPresented: Binding { otherSession != nil } set: { if !$0 { otherSession = nil } },
            presenting: otherSession
        ) { session in
            Button("Resume it") {
                change { try liveSession.open(session, in: context) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("Finish “\(session.name)” before starting another one.")
        }
    }

    private func start() {
        if let session = sessionsInProgress.first {
            if session.workoutID == workout.id {
                change { try liveSession.open(session, in: context) }
            } else {
                otherSession = session
            }
            return
        }
        if permissions.asked {
            begin()
            return
        }
        Task {
            await permissions.checkAnswered()
            if !permissions.asked {
                preparing = true
            } else if liveSession.state == nil {
                begin()
            }
        }
    }

    private func startPrepared() {
        guard prepared else { return }
        prepared = false
        begin()
    }

    private func begin() {
        let now = Date.now
        change {
            let state = try context.startSession(of: workout, now: now)
            liveSession.set(state)
            liveSession.isPresented = true
            recorder.startWithWatch(sessionID: state.sessionID, at: now)
        }
    }

    private func change(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            Self.logger.error("Cannot start the workout: \(String(describing: error))")
        }
    }
}
