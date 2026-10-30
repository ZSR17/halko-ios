import HalkoCore
import os
import SwiftData
import SwiftUI

// The page of a planned workout: the muscles it works, then its exercises with the sets planned.
struct WorkoutView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

    let workout: Workout
    @Query private var items: [WorkoutItem]
    @Query(filter: #Predicate<Folder> { !$0.removed }, sort: \Folder.position) private var folders: [Folder]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    init(workout: Workout) {
        self.workout = workout
        let id = workout.id
        _items = Query(filter: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id }, sort: \WorkoutItem.position)
    }

    var body: some View {
        ScrollView {
            WorkoutContent(items: items)
                .padding([.horizontal, .bottom])
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(workout.name)
        .navigationSubtitle("\(items.count) exercises")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More actions", systemImage: "ellipsis") {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        change { _ = try context.duplicateWorkout(workout, named: String(localized: "\(workout.name) (copy)")) }
                    }
                    Picker(selection: folder) {
                        Text("No folder")
                            .tag(String?.none)
                        ForEach(folders) { folder in
                            Text(verbatim: folder.name)
                                .tag(Optional(folder.id))
                        }
                    } label: {
                        Label("Move to folder", systemImage: "folder")
                    }
                    .pickerStyle(.menu)
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
        }
        .confirmationDialog("Delete the workout “\(workout.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete the workout", role: .destructive) {
                change { try context.removeWorkout(workout) }
                dismiss()
            }
        } message: {
            Text("Sessions already done stay in the history.")
        }
    }

    private var folder: Binding<String?> {
        Binding {
            workout.folderID
        } set: { folderID in
            change { try context.moveWorkout(workout, to: folderID) }
        }
    }

    private func change(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            Self.logger.error("Cannot change the workout: \(String(describing: error))")
        }
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
        let muscles = WorkedMuscles.main(items: items, exercises: exercises, limit: .max)
        VStack(alignment: .leading, spacing: 8) {
            if !muscles.isEmpty {
                WorkedMusclesCard(muscles: muscles)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ItemBlock.blocks(items)) { block in
                    ItemBlockView(block: block, exercises: byID, text: SetsText(locale: locale))
                    Divider()
                }
            }
        }
    }
}

// An exercise alone, or the exercises of a superset under its tag, with a bar along them.
private struct ItemBlockView: View {
    let block: ItemBlock
    let exercises: [String: Exercise]
    let text: SetsText

    var body: some View {
        if block.isSuperset {
            VStack(alignment: .leading, spacing: 0) {
                Tag(Text("Superset · no rest in between"), color: Color(.superset))
                    .padding(.top, 12)
                rows
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color(.superset))
                            .frame(width: 3)
                            .padding(.vertical, 12)
                    }
            }
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(block.items) { item in
                PlannedExerciseRow(item: item, exercise: exercises[item.exerciseID], text: text)
            }
        }
    }
}

// An exercise of the workout: its picture, its name, the sets planned and the warm-ups worked out.
private struct PlannedExerciseRow: View {
    let item: WorkoutItem
    let exercise: Exercise?
    let text: SetsText

    var body: some View {
        let type = exercise?.exerciseType ?? .weightReps
        let sets = PlannedSets(item.targets, type: type, equipment: exercise?.equipment ?? [], unit: text.weightUnit)
        HStack(alignment: .top, spacing: 12) {
            ExerciseThumbnail(mediaID: exercise?.mediaIDs.first)
            VStack(alignment: .leading, spacing: 4) {
                FlowLayout(spacing: 8, lineSpacing: 4) {
                    Text(verbatim: name)
                        .font(.headline)
                    if item.doneBySide(exercise) {
                        Tag(Text("One side at a time"), color: Color(.oneSide))
                    }
                }
                Text(verbatim: text.working(sets, type: type, perSide: item.doneBySide(exercise), sidesPauseS: item.sidesPauseS(exercise)))
                    .font(.subheadline)
                if !sets.warmups.isEmpty {
                    Text(verbatim: text.warmups(sets, type: type))
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryText))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        exercise?.localizedName ?? String(localized: "Exercise")
    }
}
