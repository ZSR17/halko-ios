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
    // Cards dragged to be moved, nothing else done.
    @State private var reordering = false
    @Environment(LiveSessionStore.self) private var liveSession
    @Environment(\.modelContext) private var context

    var body: some View {
        page
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if reordering {
                        Button("Done") {
                            reordering = false
                        }
                    } else {
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
            }
            // Left with another tab.
            .onDisappear {
                reordering = false
                drag.cancel()
            }
            .folderNameAlert("New folder", isPresented: $naming, action: "Create", message: "To arrange your workouts.") { name in
                do {
                    try context.createFolder(named: name)
                } catch {
                    Self.logger.error("Cannot create the folder: \(String(describing: error))")
                }
            }
            .sheet(isPresented: $creating) {
                WorkoutEditor(workout: nil, items: [])
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
        let folderCards = shownFolders.map { DraggedCard.folder($0.id) }
        let workoutCards = drag.workouts(workouts).map { DraggedCard.workout($0.id) }
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
                if reordering {
                    ReorderHint(inFolder: false)
                }
                if !folders.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: folderWidth), spacing: 10)], spacing: 10) {
                        ForEach(shownFolders) { folder in
                            Group {
                                if reordering {
                                    FolderCard(folder: folder, isTarget: drag.targetFolderID == folder.id)
                                        .draggableCard(.folder(folder.id), drag: drag, cards: folderCards, folders: shownFolders, workouts: drag.workouts(workouts))
                                } else {
                                    NavigationLink(value: folder) {
                                        FolderCard(folder: folder, isTarget: false)
                                    }
                                    .buttonStyle(.plain)
                                    .folderMenu(folder) {
                                        reordering = true
                                    }
                                }
                            }
                            .moveActions(index: shownFolders.firstIndex(of: folder) ?? 0, count: shownFolders.count, horizontal: true) { offset in
                                reorder(folders: moved(shownFolders, folder, by: offset), workouts: workouts)
                            }
                        }
                    }
                    // A folder held over the workouts.
                    .zIndex(isDragged(folder: true) ? 1 : 0)
                }
                if !folders.isEmpty && !workouts.isEmpty {
                    Divider()
                }
                WorkoutCards(workouts: workouts, folders: shownFolders, drag: drag, reordering: $reordering)
                    // A workout held over the folders.
                    .zIndex(isDragged(folder: false) ? 1 : 0)
            }
            .cardDragSpace(drag, folders: folderCards, workouts: workoutCards)
            .padding([.horizontal, .bottom])
        }
        .filedBanner(drag)
        .background(Color(.systemGroupedBackground))
        .overlay {
            if sessionsInProgress.isEmpty && folders.isEmpty && workouts.isEmpty {
                NoWorkouts {
                    creating = true
                }
            }
        }
    }

    private func isDragged(folder: Bool) -> Bool {
        switch drag.dragged {
        case .folder: folder
        case .workout: !folder
        case nil: false
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
    @State private var reordering = false
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
            VStack(alignment: .leading, spacing: 20) {
                if reordering {
                    ReorderHint(inFolder: true)
                }
                WorkoutCards(workouts: workouts, folders: [], drag: drag, reordering: $reordering)
            }
            .cardDragSpace(drag, folders: [], workouts: drag.workouts(workouts).map { DraggedCard.workout($0.id) })
            .padding([.horizontal, .bottom])
        }
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
                if reordering {
                    Button("Done") {
                        reordering = false
                    }
                } else {
                    actionsMenu
                }
            }
        }
        .onDisappear {
            reordering = false
            drag.cancel()
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

    private var actionsMenu: some View {
        Menu("More actions", systemImage: "ellipsis") {
            Button("Rename", systemImage: "pencil") {
                renaming = true
            }
            Button("New workout here", systemImage: "dumbbell") {
                creating = true
            }
            Button("Reorder", systemImage: "arrow.up.arrow.down") {
                reordering = true
            }
            .disabled(workouts.count < 2)
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

    private func delete() {
        do {
            try context.removeFolder(folder)
            dismiss()
        } catch {
            Self.logger.error("Cannot delete the folder: \(String(describing: error))")
        }
    }
}

// The workouts of the page, or of a folder (`folders` empty): opened and touched and held for their actions, or, while
// reordering, only dragged. VoiceOver moves one a place, into a folder of the page, or out of its folder.
private struct WorkoutCards: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

    let workouts: [Workout]
    let folders: [Folder]
    let drag: CardDrag
    @Binding var reordering: Bool
    @Environment(\.modelContext) private var context

    var body: some View {
        let shown = drag.workouts(workouts)
        let cards = shown.map { DraggedCard.workout($0.id) }
        // Not lazy: the places of all the cards known while one is dragged.
        VStack(spacing: 10) {
            ForEach(shown) { workout in
                Group {
                    if reordering {
                        WorkoutCard(workout: workout, reordering: true)
                            .draggableCard(.workout(workout.id), drag: drag, cards: cards, folders: folders, workouts: shown)
                    } else {
                        NavigationLink(value: workout) {
                            WorkoutCard(workout: workout, reordering: false)
                        }
                        .buttonStyle(.plain)
                        .workoutMenu(workout) {
                            reordering = true
                        }
                    }
                }
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

// What to do while reordering: shown above the cards.
private struct ReorderHint: View {
    let inFolder: Bool

    var body: some View {
        (inFolder
            ? Text("Touch and hold a workout, then drag it to move it.")
            : Text("Touch and hold a card, then drag it to move it, or let go of a workout on a folder to put it in."))
            .font(.subheadline)
            .foregroundStyle(Color(.secondaryText))
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
