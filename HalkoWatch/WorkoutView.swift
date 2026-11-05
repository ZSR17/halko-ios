import HalkoCore
import SwiftData
import SwiftUI

// The page of a workout: its exercises with their picture and the sets planned.
struct WorkoutView: View {
    let workout: Workout
    @Query private var items: [WorkoutItem]

    init(workout: Workout) {
        self.workout = workout
        let id = workout.id
        _items = Query(filter: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id }, sort: \WorkoutItem.position)
    }

    var body: some View {
        WorkoutContent(items: items)
            .navigationTitle(workout.name)
    }
}

// What the page shows of the exercises, once they are read.
private struct WorkoutContent: View {
    let items: [WorkoutItem]
    @Query private var exercises: [Exercise]
    @Environment(\.locale) private var locale

    init(items: [WorkoutItem]) {
        self.items = items
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
                ForEach(rows) { row in
                    PlannedExerciseRow(row: row, text: text)
                }
            } header: {
                Text(verbatim: "\(String(localized: "\(items.count) exercises")) · \(String(localized: "\(setCount) sets"))")
                    // As far from the first exercise as the exercises are from each other.
                    .padding(.bottom, 6)
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
