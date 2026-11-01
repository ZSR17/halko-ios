import HalkoCore
import SwiftData
import SwiftUI

// The workout an exercise is added to, from its page: a new one, the workouts in no folder, then those of each
// folder. `choose` gets nil for a new workout. Pulled down, the sheet closes without changing anything.
struct AddToWorkoutSheet: View {
    let exercise: Exercise
    let choose: (Workout?) -> Void
    @Query(filter: #Predicate<Folder> { !$0.removed }) private var folders: [Folder]
    @Query(filter: #Predicate<Workout> { !$0.removed }) private var workouts: [Workout]
    @Query(filter: #Predicate<WorkoutItem> { !$0.removed }) private var items: [WorkoutItem]

    var body: some View {
        let groups = WorkoutChoiceGroup.groups(workouts: workouts, folders: folders, items: items, exerciseID: exercise.id)
        NavigationStack {
            List {
                Section {
                    Button {
                        choose(nil)
                    } label: {
                        Label("New workout", systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.choices) { choice in
                            Button {
                                choose(choice.workout)
                            } label: {
                                ChoiceRow(choice: choice)
                            }
                        }
                    } header: {
                        if let folder = group.folder {
                            Label {
                                Text(verbatim: folder.name)
                            } icon: {
                                Image(systemName: "folder")
                            }
                            .foregroundStyle(Color(.secondaryText))
                        }
                    }
                }
            }
            .navigationTitle("Add to a workout")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// "Push A", "5 exercises · already has this exercise".
private struct ChoiceRow: View {
    let choice: WorkoutChoice

    var body: some View {
        let count = Text("\(choice.exerciseCount) exercises")
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: choice.workout.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Group {
                    if choice.hasExercise {
                        Text("\(count) · \(Text("already has this exercise"))")
                    } else {
                        count
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryText))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.secondaryText))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

// The editor of the workout chosen, with the exercise added at the end; nil: a new workout with only the exercise.
struct AddingEditor: View {
    let workout: Workout?
    let exercise: Exercise
    @Query private var items: [WorkoutItem]

    init(workout: Workout?, exercise: Exercise) {
        self.workout = workout
        self.exercise = exercise
        // A new workout has no items: nothing has this id.
        let id = workout?.id ?? ""
        _items = Query(filter: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id }, sort: \WorkoutItem.position)
    }

    var body: some View {
        WorkoutEditor(workout: workout, items: items, adding: exercise)
    }
}
