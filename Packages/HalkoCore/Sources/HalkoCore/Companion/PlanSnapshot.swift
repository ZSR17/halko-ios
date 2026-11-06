import Foundation
import SwiftData

// What the iPhone gives the watch to train on its own: the planned workouts, their folders and the exercises they
// use, as sync rows. The library's exercises are embedded in both apps: those sent carry the user's changes. Every
// row is sent, deleted ones included, and applied like rows from the server: the most recent `updatedAt` wins.
public struct PlanSnapshot: Codable, Equatable, Sendable {
    public var folders: [FolderRow]
    public var workouts: [WorkoutRow]
    public var items: [WorkoutItemRow]
    public var exercises: [ExerciseRow]

    public init(folders: [FolderRow], workouts: [WorkoutRow], items: [WorkoutItemRow], exercises: [ExerciseRow]) {
        self.folders = folders
        self.workouts = workouts
        self.items = items
        self.exercises = exercises
    }

    // The same plan always gives the same bytes: rows in the order of their ids, keys sorted.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(PlanSnapshot.self, from: data)
    }
}

extension ModelContext {
    public func planSnapshot() throws -> PlanSnapshot {
        let items = try fetch(FetchDescriptor<WorkoutItem>(sortBy: [SortDescriptor(\.id)]))
        let exerciseIDs = Array(Set(items.map(\.exerciseID)))
        return PlanSnapshot(
            folders: try fetch(FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.id)])).map(\.row),
            workouts: try fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.id)])).map(\.row),
            items: items.map(\.row),
            exercises: try fetch(FetchDescriptor(predicate: Exercise.withIDs(exerciseIDs), sortBy: [SortDescriptor(\.id)])).map(\.row)
        )
    }

    public func apply(_ snapshot: PlanSnapshot) throws {
        try apply(snapshot.folders, to: Folder.self)
        try apply(snapshot.workouts, to: Workout.self)
        try apply(snapshot.items, to: WorkoutItem.self)
        try apply(snapshot.exercises, to: Exercise.self)
        if hasChanges {
            try save()
        }
    }

    // The pictures the watch shows: the first one of each exercise of its workouts.
    public func planMediaIDs() throws -> Set<String> {
        let workouts = Set(try fetch(FetchDescriptor<Workout>(predicate: #Predicate { !$0.removed })).map(\.id))
        let items = try fetch(FetchDescriptor<WorkoutItem>(predicate: #Predicate { !$0.removed }))
            .filter { workouts.contains($0.workoutID) }
        let exercises = try fetch(FetchDescriptor(predicate: Exercise.withIDs(items.map(\.exerciseID))))
        return Set(exercises.compactMap(\.mediaIDs.first))
    }
}

// What the iPhone and the watch tell each other besides rows (WatchConnectivity).
public enum CompanionMessage {
    // In the metadata of a file: what it holds, a plan (`PlanSnapshot`), sessions (`SessionChanges`) or the picture of a
    // media id.
    public static let kindKey = "kind"
    public static let planKind = "plan"
    public static let sessionsKind = "sessions"
    public static let thumbnailKind = "thumbnail"
    public static let mediaIDKey = "mediaID"
    // From the watch: send the plan (a first launch, or the app installed again), and the pictures of these media
    // ids, which it lacks.
    public static let planRequestKey = "sendPlan"
    public static let thumbnailsKey = "thumbnails"
    // In a message, the application context or a user info: a `LiveMessage`.
    public static let liveKey = "live"
}
