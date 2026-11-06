import HalkoCore
import os
import SwiftData
import SwiftUI

// The page of a workout: how much it holds, Start, which goes through « Before your first workout » the first time, then
// its exercises with their picture and the sets planned.
struct WorkoutView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")

    let workout: Workout
    @Query private var items: [WorkoutItem]
    @Environment(LiveSessionStore.self) private var store
    @Environment(Permissions.self) private var permissions
    @Environment(WorkoutRecorder.self) private var recorder
    @Environment(\.modelContext) private var context
    @State private var isPreparing = false

    init(workout: Workout) {
        self.workout = workout
        let id = workout.id
        _items = Query(filter: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id }, sort: \WorkoutItem.position)
    }

    var body: some View {
        if isPreparing {
            FirstWorkoutView {
                await permissions.request()
                start()
            }
        } else {
            WorkoutContent(items: items) {
                if permissions.asked {
                    start()
                    return
                }
                Task {
                    await permissions.checkAnswered()
                    if !permissions.asked {
                        isPreparing = true
                    } else if store.state == nil {
                        start()
                    }
                }
            }
            .navigationTitle(workout.name)
        }
    }

    private func start() {
        let now = Date.now
        do {
            let state = try context.startSession(of: workout, now: now)
            recorder.start(sessionID: state.sessionID, at: now)
            store.set(state)
        } catch {
            Self.logger.error("Cannot start the session: \(String(describing: error))")
            isPreparing = false
        }
    }
}

// What the page shows, once the exercises are read.
private struct WorkoutContent: View {
    let items: [WorkoutItem]
    let start: () -> Void
    @Query private var exercises: [Exercise]
    @Environment(\.locale) private var locale

    init(items: [WorkoutItem], start: @escaping () -> Void) {
        self.items = items
        self.start = start
        _exercises = Query(filter: Exercise.withIDs(items.map(\.exerciseID)))
    }

    var body: some View {
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let text = SetsText(locale: locale)
        let rows = items.map { item in
            let exercise = byID[item.exerciseID]
            let sets = PlannedSets(item.targets, type: exercise?.exerciseType ?? .weightReps, equipment: exercise?.equipment ?? [], unit: text.weightUnit)
            return PlannedExercise(item: item, exercise: exercise, sets: sets)
        }
        let setCount = rows.reduce(0) { $0 + $1.sets.working.count }
        List {
            Section {
                Button(action: start) {
                    Text("Start")
                        .font(.headline)
                        .foregroundStyle(Color(.onAccent))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(items.isEmpty)
                // A button of the watch stays narrower than the page.
                .frame(maxWidth: .infinity)
                // As far from the first exercise as from the line above.
                .padding(.bottom, 3)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                ForEach(rows) { row in
                    PlannedExerciseRow(row: row, text: text)
                }
            } header: {
                Text(verbatim: "\(String(localized: "\(items.count) exercises")) · \(String(localized: "\(setCount) sets"))")
                    .padding(.bottom, 2)
            }
        }
    }
}

private struct PlannedExercise: Identifiable {
    let item: WorkoutItem
    let exercise: Exercise?
    let sets: PlannedSets

    var id: String {
        item.id
    }
}

// An exercise of the workout: its picture, its name and its working sets ("4 × 8 · 80 kg").
private struct PlannedExerciseRow: View {
    let row: PlannedExercise
    let text: SetsText

    var body: some View {
        let exercise = row.exercise
        HStack(spacing: 10) {
            ExerciseThumbnail(mediaID: exercise?.mediaIDs.first)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: exercise?.localizedName ?? String(localized: "Exercise"))
                    .font(.headline)
                Text(verbatim: text.working(
                    row.sets,
                    type: exercise?.exerciseType ?? .weightReps,
                    perSide: row.item.doneBySide(exercise),
                    sidesPauseS: nil,
                    pauses: false
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
