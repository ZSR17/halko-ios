import HalkoCore
import os
import SwiftData
import SwiftUI

// The Workouts tab: its cards on a screen of an iPhone; with room (the iPhone Duo open), two columns, the workouts on
// the left and the page of the one chosen on the right.
struct WorkoutsTab: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            WorkoutsSplit()
        } else {
            NavigationStack {
                WorkoutsView()
                    .toolbarTitleDisplayMode(.inlineLarge)
            }
        }
    }
}

private struct WorkoutsSplit: View {
    @Query(filter: #Predicate<Folder> { !$0.removed }, sort: \Folder.position) private var folders: [Folder]
    @Query(filter: #Predicate<Workout> { !$0.removed }, sort: \Workout.position) private var workouts: [Workout]
    // Nil: the first workout, until another one is chosen.
    @State private var chosenID: String?

    var body: some View {
        let ordered = WorkoutsList.ordered(workouts, folders: folders)
        let chosen = ordered.first { $0.id == chosenID } ?? ordered.first
        NavigationSplitView {
            WorkoutsList(folders: folders, workouts: workouts, chosenID: selection(default: chosen?.id))
                .navigationTitle("Workouts")
                .toolbarTitleDisplayMode(.inlineLarge)
        } detail: {
            NavigationStack {
                Group {
                    if let chosen {
                        WorkoutView(workout: chosen)
                    } else {
                        NoWorkouts()
                    }
                }
                .navigationDestination(for: Exercise.self) { exercise in
                    ExerciseView(exercise: exercise)
                }
                // From the progress on the page of an exercise.
                .navigationDestination(for: PastSessionLink.self) { link in
                    PastSessionView(link: link)
                }
            }
            // Another workout chosen: its page, without the pages opened from the one before.
            .id(chosen?.id)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func selection(default id: String?) -> Binding<String?> {
        Binding {
            chosenID ?? id
        } set: { id in
            chosenID = id
        }
    }
}

// The session in progress, the folders with their workouts, then the workouts in no folder; the workout chosen shown
// beside.
private struct WorkoutsList: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

    let folders: [Folder]
    let workouts: [Workout]
    @Binding var chosenID: String?
    @Query(filter: #Predicate<Session> { !$0.removed && $0.endedAt == nil }, sort: \Session.startedAt, order: .reverse)
    private var sessionsInProgress: [Session]
    @State private var collapsed: Set<String> = []
    @State private var creating = false
    @State private var naming = false
    @Environment(LiveSessionStore.self) private var liveSession
    @Environment(\.modelContext) private var context

    // In the order of the list: folder by folder, then those in no folder.
    static func ordered(_ workouts: [Workout], folders: [Folder]) -> [Workout] {
        folders.flatMap { folder in workouts.filter { $0.folderID == folder.id } } + workouts.filter { $0.folderID == nil }
    }

    var body: some View {
        List(selection: $chosenID) {
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
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
            ForEach(folders) { folder in
                DisclosureGroup(isExpanded: expanded(folder)) {
                    ForEach(workouts.filter { $0.folderID == folder.id }) { workout in
                        WorkoutRow(workout: workout)
                            .tag(Optional(workout.id))
                    }
                } label: {
                    FolderRow(folder: folder)
                }
            }
            ForEach(workouts.filter { $0.folderID == nil }) { workout in
                WorkoutRow(workout: workout)
                    .tag(Optional(workout.id))
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if sessionsInProgress.isEmpty && folders.isEmpty && workouts.isEmpty {
                NoWorkouts {
                    creating = true
                }
            }
        }
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
                try context.createFolder(named: name)
            } catch {
                Self.logger.error("Cannot create the folder: \(String(describing: error))")
            }
        }
        .sheet(isPresented: $creating) {
            WorkoutEditor(workout: nil, items: [])
        }
    }

    private func expanded(_ folder: Folder) -> Binding<Bool> {
        Binding {
            !collapsed.contains(folder.id)
        } set: { isExpanded in
            if isExpanded {
                collapsed.remove(folder.id)
            } else {
                collapsed.insert(folder.id)
            }
        }
    }
}

// A folder: its name and how many workouts it holds; touched and held, what can be done of it.
private struct FolderRow: View {
    let folder: Folder
    @Query private var workouts: [Workout]

    init(folder: Folder) {
        self.folder = folder
        let id: String? = folder.id
        _workouts = Query(filter: #Predicate<Workout> { !$0.removed && $0.folderID == id })
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.headline)
                Text("\(workouts.count) workouts")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
            }
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(.tint)
        }
        .folderMenu(folder, reorder: nil)
    }
}

// A workout: its name, number of exercises and when it was last done; chosen, its page beside; touched and held, what
// can be done of it.
private struct WorkoutRow: View {
    let workout: Workout
    @Query private var items: [WorkoutItem]
    @Query private var lastSessions: [Session]

    init(workout: Workout) {
        self.workout = workout
        let id = workout.id
        let sessionWorkoutID: String? = workout.id
        _items = Query(filter: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id })
        var last = FetchDescriptor<Session>(
            predicate: #Predicate { !$0.removed && $0.workoutID == sessionWorkoutID && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        last.fetchLimit = 1
        _lastSessions = Query(last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workout.name)
                .font(.headline)
            details
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryText))
        }
        .workoutMenu(workout, reorder: nil)
    }

    private var details: Text {
        let exercises = Text("\(items.count) exercises")
        guard let last = lastSessions.first else { return exercises }
        return Text("\(exercises) · \(last.startedAt, format: .relative(presentation: .named))")
    }
}
