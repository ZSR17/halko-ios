import HalkoCore
import SwiftData
import SwiftUI

// The workouts the iPhone sent, kept on the watch: those of each folder under its name, then those in no folder.
struct WorkoutsView: View {
    @Query(filter: #Predicate<Folder> { !$0.removed }, sort: \Folder.position) private var folders: [Folder]
    @Query(filter: #Predicate<Workout> { !$0.removed }, sort: \Workout.position) private var workouts: [Workout]
    @Query(filter: #Predicate<WorkoutItem> { !$0.removed }) private var items: [WorkoutItem]

    var body: some View {
        let groups = WorkoutGroup.groups(folders: folders, workouts: workouts)
        let exerciseCounts = Dictionary(grouping: items, by: \.workoutID).mapValues(\.count)
        Group {
            if groups.isEmpty {
                ContentUnavailableView("No workouts", systemImage: "dumbbell", description: Text("The workouts you make in Halko on your iPhone appear here."))
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.workouts) { workout in
                                NavigationLink(value: workout) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: workout.name)
                                            .font(.headline)
                                        Text("\(exerciseCounts[workout.id, default: 0]) exercises")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } header: {
                            if let name = group.name {
                                Text(verbatim: name)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Workouts")
        .navigationDestination(for: Workout.self) { workout in
            WorkoutView(workout: workout)
        }
    }
}

// The workouts of a folder, or those in none (`name` nil), in order.
private struct WorkoutGroup: Identifiable {
    let id: String
    let name: String?
    let workouts: [Workout]

    // The folders holding a workout, then the workouts in no folder, or in one the watch does not have.
    static func groups(folders: [Folder], workouts: [Workout]) -> [WorkoutGroup] {
        let byFolder = Dictionary(grouping: workouts) { $0.folderID ?? "" }
        let groups = folders.compactMap { folder in
            byFolder[folder.id].map { WorkoutGroup(id: folder.id, name: folder.name, workouts: $0) }
        }
        let folderIDs = Set(folders.map(\.id))
        let loose = workouts.filter { workout in workout.folderID.map { !folderIDs.contains($0) } ?? true }
        return loose.isEmpty ? groups : groups + [WorkoutGroup(id: "", name: nil, workouts: loose)]
    }
}
