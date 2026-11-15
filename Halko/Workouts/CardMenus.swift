import HalkoCore
import os
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

extension View {
    // What can be done of a workout from its card, touched and held without moving: as in the menu of its page, and
    // started.
    func workoutMenu(_ workout: Workout) -> some View {
        modifier(WorkoutMenu(workout: workout))
    }

    // What can be done of a folder from its card, touched and held without moving: as in the menu of its page.
    func folderMenu(_ folder: Folder) -> some View {
        modifier(FolderMenu(folder: folder))
    }
}

private struct WorkoutMenu: ViewModifier {
    let workout: Workout
    @Query private var items: [WorkoutItem]
    @Query(filter: #Predicate<Folder> { !$0.removed }, sort: \Folder.position) private var folders: [Folder]
    @State private var starting = false
    @State private var editing = false
    @State private var confirmingDelete = false
    @Environment(\.modelContext) private var context

    init(workout: Workout) {
        self.workout = workout
        let id = workout.id
        _items = Query(filter: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id }, sort: \WorkoutItem.position)
    }

    func body(content: Content) -> some View {
        content
            // Lifted with the rounded corners of the card.
            .contentShape(.contextMenuPreview, .rect(cornerRadius: 16))
            .contextMenu {
                // Nothing to start in a workout without exercises, as on its card.
                if !items.isEmpty {
                    Button("Start", systemImage: "play") {
                        starting = true
                    }
                }
                Button("Edit", systemImage: "pencil") {
                    editing = true
                }
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
                // Red as its text: the icons of a menu take the color of the theme.
                .tint(.red)
            }
            .startsWorkout(workout, when: $starting)
            .confirmationDialog("Delete the workout “\(workout.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete the workout", role: .destructive) {
                    change { try context.removeWorkout(workout) }
                }
            } message: {
                Text("Sessions already done stay in the history.")
            }
            .sheet(isPresented: $editing) {
                WorkoutEditor(workout: workout, items: items)
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
            logger.error("Cannot change the workout: \(String(describing: error))")
        }
    }
}

private struct FolderMenu: ViewModifier {
    let folder: Folder
    @Query private var workouts: [Workout]
    @State private var renaming = false
    @State private var creating = false
    @State private var confirmingDelete = false
    @Environment(\.modelContext) private var context

    init(folder: Folder) {
        self.folder = folder
        let id: String? = folder.id
        _workouts = Query(filter: #Predicate<Workout> { !$0.removed && $0.folderID == id })
    }

    func body(content: Content) -> some View {
        content
            // Lifted with the rounded corners of the card.
            .contentShape(.contextMenuPreview, .rect(cornerRadius: 16))
            .contextMenu {
                Button("Rename", systemImage: "pencil") {
                    renaming = true
                }
                Button("New workout here", systemImage: "dumbbell") {
                    creating = true
                }
                Button("Delete the folder", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
                // Red as its text: the icons of a menu take the color of the theme.
                .tint(.red)
            }
            .confirmationDialog("Delete the folder “\(folder.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete the folder", role: .destructive) {
                    change { try context.removeFolder(folder) }
                }
            } message: {
                Text("Its \(workouts.count) workouts go back to Workouts. None is deleted.")
            }
            .folderNameAlert("Rename the folder", isPresented: $renaming, action: "Rename", name: folder.name) { name in
                change { try context.renameFolder(folder, to: name) }
            }
            .sheet(isPresented: $creating) {
                WorkoutEditor(workout: nil, items: [], folder: folder)
            }
    }

    private func change(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            logger.error("Cannot change the folder: \(String(describing: error))")
        }
    }
}
