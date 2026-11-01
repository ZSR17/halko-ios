import Foundation

// A workout an exercise can be added to, from the exercise's page.
public struct WorkoutChoice: Identifiable {
    public let workout: Workout
    public let exerciseCount: Int
    // Added again, it is done twice.
    public let hasExercise: Bool

    public var id: String {
        workout.id
    }
}

// The workouts in no folder (`folder` nil), or those of a folder.
public struct WorkoutChoiceGroup: Identifiable {
    public let folder: Folder?
    public let choices: [WorkoutChoice]

    public var id: String {
        folder?.id ?? ""
    }

    // In the order of the Workouts tab: the workouts in no folder, then each folder with workouts. A workout whose
    // folder is gone counts as in no folder.
    public static func groups(workouts: [Workout], folders: [Folder], items: [WorkoutItem], exerciseID: String) -> [WorkoutChoiceGroup] {
        var counts: [String: Int] = [:]
        var having: Set<String> = []
        for item in items where !item.removed {
            counts[item.workoutID, default: 0] += 1
            if item.exerciseID == exerciseID {
                having.insert(item.workoutID)
            }
        }
        let liveFolders = folders.filter { !$0.removed }.sorted { $0.position < $1.position }
        let folderIDs = Set(liveFolders.map(\.id))
        var loose: [WorkoutChoice] = []
        var inFolder: [String: [WorkoutChoice]] = [:]
        for workout in workouts.filter({ !$0.removed }).sorted(by: { $0.position < $1.position }) {
            let choice = WorkoutChoice(workout: workout, exerciseCount: counts[workout.id] ?? 0, hasExercise: having.contains(workout.id))
            if let folderID = workout.folderID, folderIDs.contains(folderID) {
                inFolder[folderID, default: []].append(choice)
            } else {
                loose.append(choice)
            }
        }
        let folderGroups = liveFolders.compactMap { folder in
            inFolder[folder.id].map { WorkoutChoiceGroup(folder: folder, choices: $0) }
        }
        return (loose.isEmpty ? [] : [WorkoutChoiceGroup(folder: nil, choices: loose)]) + folderGroups
    }
}
