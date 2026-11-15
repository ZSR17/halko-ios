import HalkoCore
import os
import SwiftData
import SwiftUI

// The workouts page or a folder, its cards as rows to drag by their handles: the folders among themselves, the
// workouts among themselves. VoiceOver moves them with Move up and Move down. The headers in the darker grey of the app, for a
// contrast of 4.5:1.
struct ReorderList: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

    let folders: [Folder]
    let workouts: [Workout]
    // To count those of each folder and the exercises of each workout.
    @Query(filter: #Predicate<Workout> { !$0.removed }) private var allWorkouts: [Workout]
    @Query(filter: #Predicate<WorkoutItem> { !$0.removed }) private var items: [WorkoutItem]
    @Environment(\.modelContext) private var context

    var body: some View {
        let workoutCounts = Dictionary(grouping: allWorkouts.compactMap(\.folderID), by: { $0 }).mapValues(\.count)
        let exerciseCounts = Dictionary(grouping: items, by: \.workoutID).mapValues(\.count)
        List {
            if !folders.isEmpty {
                Section {
                    ForEach(folders) { folder in
                        row(index: folders.firstIndex(of: folder) ?? 0, count: folders.count) { offset in
                            order(folders: moved(folders, folder, by: offset), workouts: workouts)
                        } label: {
                            Label {
                                HStack {
                                    Text(verbatim: folder.name)
                                    Spacer()
                                    Text("\(workoutCounts[folder.id] ?? 0) workouts")
                                        .foregroundStyle(Color(.secondaryText))
                                }
                            } icon: {
                                Image(systemName: "folder")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .onMove { offsets, destination in
                        var folders = folders
                        folders.move(fromOffsets: offsets, toOffset: destination)
                        order(folders: folders, workouts: workouts)
                    }
                } header: {
                    Text("Folders")
                        .foregroundStyle(Color(.secondaryText))
                }
            }
            if !workouts.isEmpty {
                Section {
                    ForEach(workouts) { workout in
                        row(index: workouts.firstIndex(of: workout) ?? 0, count: workouts.count) { offset in
                            order(folders: folders, workouts: moved(workouts, workout, by: offset))
                        } label: {
                            HStack {
                                Text(verbatim: workout.name)
                                Spacer()
                                Text("\(exerciseCounts[workout.id] ?? 0) exercises")
                                    .foregroundStyle(Color(.secondaryText))
                            }
                        }
                    }
                    .onMove { offsets, destination in
                        var workouts = workouts
                        workouts.move(fromOffsets: offsets, toOffset: destination)
                        order(folders: folders, workouts: workouts)
                    }
                } header: {
                    if !folders.isEmpty {
                        Text("Workouts in no folder")
                            .foregroundStyle(Color(.secondaryText))
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    // A row, and its moves for VoiceOver: one place up or down, where there is one.
    private func row(index: Int, count: Int, move: @escaping (Int) -> Void, @ViewBuilder label: () -> some View) -> some View {
        label()
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityActions {
                if index > 0 {
                    Button("Move up") {
                        move(-1)
                    }
                }
                if index < count - 1 {
                    Button("Move down") {
                        move(1)
                    }
                }
            }
    }

    private func moved<Model: PersistentModel>(_ list: [Model], _ model: Model, by offset: Int) -> [Model] {
        var list = list
        guard let index = list.firstIndex(of: model) else { return list }
        list.swapAt(index, index + offset)
        return list
    }

    private func order(folders: [Folder], workouts: [Workout]) {
        do {
            try context.order(folders: folders, workouts: workouts)
        } catch {
            Self.logger.error("Cannot reorder the workouts: \(String(describing: error))")
        }
    }
}
