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
        workout.removed = true
        workout.updatedAt = now
        for item in try items(of: workout) {
            item.removed = true
            item.updatedAt = now
        }
        try save()
    }

    // Puts `workout` last in the folder `folderID`, or out of any folder with nil: then last on the workouts page.
    public func moveWorkout(_ workout: Workout, to folderID: String?) throws {
        guard workout.folderID != folderID else { return }
        if folderID != nil {
            var last = FetchDescriptor<Workout>(
                predicate: #Predicate { !$0.removed && $0.folderID == folderID },
                sortBy: [SortDescriptor(\.position, order: .reverse)]
            )
            last.fetchLimit = 1
            workout.position = (try fetch(last).first?.position ?? -1) + 1
        } else {
            workout.position = try nextPosition()
        }
        workout.folderID = folderID
        workout.updatedAt = .now
        try save()
    }

    // A new folder, after every folder and workout of the workouts page.
    @discardableResult
    public func createFolder(named name: String) throws -> Folder {
        let folder = Folder(name: name, position: try nextPosition())
        insert(folder)
        try save()
        return folder
    }

    public func renameFolder(_ folder: Folder, to name: String) throws {
        guard folder.name != name else { return }
        folder.name = name
        folder.updatedAt = .now
        try save()
    }

    // Deleted; its workouts go back to the workouts page, last and in their order. None is deleted.
    public func removeFolder(_ folder: Folder) throws {
        let now = Date.now
        let id: String? = folder.id
        let workouts = try fetch(FetchDescriptor(
            predicate: #Predicate<Workout> { !$0.removed && $0.folderID == id },
            sortBy: [SortDescriptor(\.position)]
        ))
        let first = try nextPosition()
        for (offset, workout) in workouts.enumerated() {
            workout.folderID = nil
            workout.position = first + offset
            workout.updatedAt = now
        }
        folder.removed = true
        folder.updatedAt = now
        try save()
    }

    // The order of a page: on the workouts page, its folders then the workouts in none, which share one order; in a
    // folder, its workouts. Only those whose place changed are changed.
    public func order(folders: [Folder] = [], workouts: [Workout]) throws {
        let now = Date.now
        for (position, folder) in folders.enumerated() where folder.position != position {
            folder.position = position
            folder.updatedAt = now
        }
        for (offset, workout) in workouts.enumerated() where workout.position != folders.count + offset {
            workout.position = folders.count + offset
            workout.updatedAt = now
        }
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
            predicate: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id },
            sortBy: [SortDescriptor(\.position)]
        ))
    }
}
