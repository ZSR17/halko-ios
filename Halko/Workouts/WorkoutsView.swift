import HalkoCore
import SwiftData
import SwiftUI

// The Workouts tab: the session in progress, the folders, then the workouts in no folder.
struct WorkoutsView: View {
    @Query(filter: #Predicate<Session> { !$0.removed && $0.endedAt == nil }, sort: \Session.startedAt, order: .reverse)
    private var sessionsInProgress: [Session]
    @Query(filter: #Predicate<Folder> { !$0.removed }, sort: \Folder.position) private var folders: [Folder]
    @Query(filter: #Predicate<Workout> { !$0.removed && $0.folderID == nil }, sort: \Workout.position)
    private var workouts: [Workout]
    @ScaledMetric(relativeTo: .headline) private var folderWidth = 150.0
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let session = sessionsInProgress.first {
                    SessionBanner(session: session)
                }
                if !folders.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: folderWidth), spacing: 10)], spacing: 10) {
                        ForEach(folders) { folder in
                            NavigationLink(value: folder) {
                                FolderCard(folder: folder)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !folders.isEmpty && !workouts.isEmpty {
                    Divider()
                }
                WorkoutCards(workouts: workouts)
            }
            .padding([.horizontal, .bottom])
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if sessionsInProgress.isEmpty && folders.isEmpty && workouts.isEmpty {
                NoWorkouts {
                    creating = true
                }
            }
        }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New workout", systemImage: "plus") {
                    creating = true
                }
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
    }
}

// The workouts of a folder.
struct FolderView: View {
    let folder: Folder
    @Query private var workouts: [Workout]

    init(folder: Folder) {
        self.folder = folder
        let id: String? = folder.id
        _workouts = Query(filter: #Predicate<Workout> { !$0.removed && $0.folderID == id }, sort: \Workout.position)
    }

    var body: some View {
        ScrollView {
            WorkoutCards(workouts: workouts)
                .padding([.horizontal, .bottom])
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if workouts.isEmpty {
                NoWorkouts()
            }
        }
        .navigationTitle(folder.name)
        .navigationSubtitle("\(workouts.count) workouts")
    }
}

private struct WorkoutCards: View {
    let workouts: [Workout]

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(workouts) { workout in
                NavigationLink(value: workout) {
                    WorkoutCard(workout: workout)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// `create`: a button to make the first one.
private struct NoWorkouts: View {
    var create: (() -> Void)?

    var body: some View {
        // The description in a darker grey than the system's, for a contrast of 4.5:1.
        ContentUnavailableView {
            Label("No workouts", systemImage: "dumbbell")
        } description: {
            Text("Your workouts will appear here.")
                .foregroundStyle(Color(.secondaryText))
        } actions: {
            if let create {
                // The text in the color made to be read on the accent color, in light and dark appearance.
                Button(action: create) {
                    Text("New workout")
                        .foregroundStyle(Color(.onAccent))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
