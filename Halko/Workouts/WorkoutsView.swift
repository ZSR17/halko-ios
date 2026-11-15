import HalkoCore
import os
import SwiftData
import SwiftUI

// The Workouts tab: the session in progress, the folders, then the workouts in no folder.
struct WorkoutsView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

    @Query(filter: #Predicate<Session> { !$0.removed && $0.endedAt == nil }, sort: \Session.startedAt, order: .reverse)
    private var sessionsInProgress: [Session]
    @Query(filter: #Predicate<Folder> { !$0.removed }, sort: \Folder.position) private var folders: [Folder]
    @Query(filter: #Predicate<Workout> { !$0.removed && $0.folderID == nil }, sort: \Workout.position)
    private var workouts: [Workout]
    @ScaledMetric(relativeTo: .headline) private var folderWidth = 150.0
    @State private var creating = false
    @State private var naming = false
    @State private var drag = CardDrag()
    // The folder just created, opened.
    @State private var created: Folder?
    @Environment(LiveSessionStore.self) private var liveSession
    @Environment(\.modelContext) private var context

    var body: some View {
        page
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Add", systemImage: "plus") {
                        Button("New workout", systemImage: "dumbbell") {
                            creating = true
                        }
                        Button("New folder", systemImage: "folder.badge.plus") {
                            naming = true
                        }
                    }
                }
            }
            .folderNameAlert("New folder", isPresented: $naming, action: "Create", message: "To arrange your workouts.") { name in
                do {
                    created = try context.createFolder(named: name)
                } catch {
                    Self.logger.error("Cannot create the folder: \(String(describing: error))")
                }
            }
            .sheet(isPresented: $creating) {
                WorkoutEditor(workout: nil, items: [])
            }
            .navigationDestination(item: $created) { folder in
                FolderView(folder: folder)
            }
            .navigationDestination(for: Folder.self) { folder in
                FolderView(folder: folder)
            }
            .navigationDestination(for: Workout.self) { workout in
                WorkoutView(workout: workout)
            }
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseView(exercise: exercise)
            }
            // From the progress on the page of an exercise.
            .navigationDestination(for: PastSessionLink.self) { link in
                PastSessionView(link: link)
            }
    }

    private var page: some View {
        let shownFolders = drag.folders(folders)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let session = sessionsInProgress.first {
                    Button {
                        do {
                            try liveSession.open(session, in: context)
                        } catch {
                            Self.logger.error("Cannot open the session in progress: \(String(describing: error))")
                        }
                    } label: {
                        SessionBanner(session: session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the session."))
                }
                if !folders.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: folderWidth), spacing: 10)], spacing: 10) {
                        ForEach(shownFolders) { folder in
                            NavigationLink(value: folder) {
                                FolderCard(folder: folder, isTarget: drag.targetFolderID == folder.id)
                            }
                            .buttonStyle(.plain)
                            .draggableCard(.folder(folder.id), drag: drag, folders: folders, workouts: workouts)
                            .moveActions(index: shownFolders.firstIndex(of: folder) ?? 0, count: shownFolders.count, horizontal: true) { offset in
                                reorder(folders: moved(shownFolders, folder, by: offset), workouts: workouts)
                            }
                        }
                    }
                }
                if !folders.isEmpty && !workouts.isEmpty {
                    Divider()
                }
                WorkoutCards(workouts: workouts, folders: folders, drag: drag)
            }
            .padding([.horizontal, .bottom])
        }
        .cardDrops(drag, folders: folders, workouts: workouts)
        .background(Color(.systemGroupedBackground))
        .overlay {
            if sessionsInProgress.isEmpty && folders.isEmpty && workouts.isEmpty {
                NoWorkouts {
                    creating = true
                }
            }
        }
    }

    private func reorder(folders: [Folder], workouts: [Workout]) {
        do {
            try context.order(folders: folders, workouts: workouts)
        } catch {
            Self.logger.error("Cannot reorder the workouts: \(String(describing: error))")
        }
    }
}

// `list` with `model` one place before (-1) or after (1).
private func moved<Model: PersistentModel>(_ list: [Model], _ model: Model, by offset: Int) -> [Model] {
    var list = list
    guard let index = list.firstIndex(of: model), list.indices.contains(index + offset) else { return list }
    list.swapAt(index, index + offset)
    return list
}

// The workouts of a folder, dragged to be reordered, and what can be done of it: renamed, a workout created in it,
// deleted.
struct FolderView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

    let folder: Folder
    @Query private var workouts: [Workout]
    @State private var renaming = false
    @State private var creating = false
    @State private var drag = CardDrag()
    @State private var confirmingDelete = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    init(folder: Folder) {
        self.folder = folder
        let id: String? = folder.id
        _workouts = Query(filter: #Predicate<Workout> { !$0.removed && $0.folderID == id }, sort: \Workout.position)
    }

    var body: some View {
        ScrollView {
            WorkoutCards(workouts: workouts, folders: [], drag: drag)
                .padding([.horizontal, .bottom])
        }
        .cardDrops(drag, folders: [], workouts: workouts)
        .background(Color(.systemGroupedBackground))
        .overlay {
            if workouts.isEmpty {
                NoWorkouts(inFolder: true)
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationSubtitle("\(workouts.count) workouts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More actions", systemImage: "ellipsis") {
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
                // Asked where the menu was.
                .confirmationDialog("Delete the folder “\(folder.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete the folder", role: .destructive, action: delete)
                } message: {
                    Text("Its \(workouts.count) workouts go back to Workouts. None is deleted.")
                }
            }
        }
        .folderNameAlert("Rename the folder", isPresented: $renaming, action: "Rename", name: folder.name) { name in
            do {
                try context.renameFolder(folder, to: name)
            } catch {
                Self.logger.error("Cannot rename the folder: \(String(describing: error))")
            }
        }
        .sheet(isPresented: $creating) {
            WorkoutEditor(workout: nil, items: [], folder: folder)
        }
    }

    private func delete() {
        do {
            try context.removeFolder(folder)
            dismiss()
        } catch {
            Self.logger.error("Cannot delete the folder: \(String(describing: error))")
        }
    }
}

// The workouts of the page, or of a folder (`folders` empty). VoiceOver moves one a place, into a folder of the page,
// or out of its folder.
private struct WorkoutCards: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

    let workouts: [Workout]
    let folders: [Folder]
    let drag: CardDrag
    @Environment(\.modelContext) private var context

    var body: some View {
        let shown = drag.workouts(workouts)
        LazyVStack(spacing: 10) {
            ForEach(shown) { workout in
                NavigationLink(value: workout) {
                    WorkoutCard(workout: workout)
                }
                .buttonStyle(.plain)
                .draggableCard(.workout(workout.id), drag: drag, folders: folders, workouts: workouts)
                .moveActions(index: shown.firstIndex(of: workout) ?? 0, count: shown.count) { offset in
                    change { try context.order(folders: folders, workouts: moved(shown, workout, by: offset)) }
                }
                .accessibilityActions {
                    if workout.folderID != nil {
                        Button("Out of the folder") {
                            change { try context.moveWorkout(workout, to: nil) }
                        }
                    }
                    ForEach(folders) { folder in
                        Button("Move to “\(folder.name)”") {
                            change { try context.moveWorkout(workout, to: folder.id) }
                        }
                    }
                }
            }
        }
    }

    private func change(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            Self.logger.error("Cannot move the workout: \(String(describing: error))")
        }
    }
}

// `create`: a button to make the first one. In a folder, how to put one in it.
private struct NoWorkouts: View {
    var inFolder = false
    var create: (() -> Void)?

    var body: some View {
        // The description in a darker grey than the system's, for a contrast of 4.5:1.
        ContentUnavailableView {
            Label {
                inFolder ? Text("No workouts in this folder") : Text("No workouts")
            } icon: {
                Image(systemName: "dumbbell")
            }
        } description: {
            (inFolder ? Text("Put one here from its page: … › Move to folder.") : Text("Your workouts will appear here."))
                .foregroundStyle(Color(.secondaryText))
        } actions: {
            if let create {
                // The text in the color made to be read on the accent color, in light and dark appearance.
                Button(action: create) {
                    Text("New workout")
                        .foregroundStyle(.onTint)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
