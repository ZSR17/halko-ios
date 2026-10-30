import Foundation
import SwiftData

// Changes to the planned workouts, written to the local database only: the sync sends them later. Same as the
// website (`client/src/db/workouts.ts`, `folders.ts`).
extension ModelContext {
    // A copy of `workout` named `name`, last in the same folder, with copies of its exercises: the copied
    // supersets get groups of their own.
    public func duplicateWorkout(_ workout: Workout, named name: String) throws -> Workout {
        let copy = Workout(folderID: workout.folderID, sport: workout.sport, name: name, note: workout.note, position: try nextPosition())
        insert(copy)
        var groups: [String: String] = [:]
        for item in try items(of: workout) {
            var group: String?
            if let original = item.supersetGroup {
                group = groups[original] ?? newRowID()
                groups[original] = group
            }
            insert(WorkoutItem(
                workoutID: copy.id,
                exerciseID: item.exerciseID,
                position: item.position,
                mode: item.mode,
                supersetGroup: group,
                targets: item.targets,
                bySide: item.bySide,
                switchS: item.switchS,
                note: item.note
            ))
        }
        try save()
        return copy
    }

    // Deleted with its exercises; the sessions done from it stay in the history.
    public func removeWorkout(_ workout: Workout) throws {
        let now = Date.now
        workout.deleted = true
        workout.updatedAt = now
        for item in try items(of: workout) {
            item.deleted = true
            item.updatedAt = now
        }
        try save()
    }

    // Puts `workout` in the folder `folderID`, or out of any folder with nil: then last on the workouts page.
    public func moveWorkout(_ workout: Workout, to folderID: String?) throws {
        guard workout.folderID != folderID else { return }
        if folderID == nil {
            workout.position = try nextPosition()
        }
        workout.folderID = folderID
        workout.updatedAt = .now
        try save()
    }

    // After every folder and workout: what comes next on the workouts page, where folders and the workouts in none
    // share one order.
    func nextPosition() throws -> Int {
        var lastWorkout = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.position, order: .reverse)])
        lastWorkout.fetchLimit = 1
        var lastFolder = FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.position, order: .reverse)])
        lastFolder.fetchLimit = 1
        return max(try fetch(lastWorkout).first?.position ?? -1, try fetch(lastFolder).first?.position ?? -1) + 1
    }

    private func items(of workout: Workout) throws -> [WorkoutItem] {
        let id = workout.id
        return try fetch(FetchDescriptor(
            predicate: #Predicate<WorkoutItem> { !$0.deleted && $0.workoutID == id },
            sortBy: [SortDescriptor(\.position)]
        ))
    }
}
