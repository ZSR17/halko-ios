import Foundation
import SwiftData

// Rows point to each other by id, as on the server: a row can arrive before the one it points to.

// A folder workouts can be sorted into (one level).
@Model
public final class Folder {
    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    // Kept, so that the deletion reaches every device (`deleted` of the rows: Core Data keeps that name).
    public var removed: Bool
    public var name: String
    public var position: Int

    public init(id: String = newRowID(), createdAt: Date = .now, updatedAt: Date = .now, removed: Bool = false, name: String, position: Int) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.removed = removed
        self.name = name
        self.position = position
    }
}

// A planned workout.
@Model
public final class Workout {
    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    public var removed: Bool
    // nil: in no folder.
    public var folderID: String?
    public var sport: Sport
    public var name: String
    public var note: String?
    public var position: Int

    public init(
        id: String = newRowID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        removed: Bool = false,
        folderID: String? = nil,
        sport: Sport = .strength,
        name: String,
        note: String? = nil,
        position: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.removed = removed
        self.folderID = folderID
        self.sport = sport
        self.name = name
        self.note = note
        self.position = position
    }
}

// An exercise of a planned workout, with its planned sets.
@Model
public final class WorkoutItem {
    #Index<WorkoutItem>([\.workoutID])

    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    public var removed: Bool
    public var workoutID: String
    public var exerciseID: String
    public var position: Int
    public var mode: ItemMode
    // Items sharing it are done as a superset.
    public var supersetGroup: String?
    public var targets: [SetTarget]
    // For a timed exercise working one side at a time: false when done here as a plain set (no sides, no pause
    // to change sides); nil: side by side.
    public var bySide: Bool?
    // Seconds to change sides; nil: the default (5 s).
    public var switchS: Int?
    public var note: String?

    public init(
        id: String = newRowID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        removed: Bool = false,
        workoutID: String,
        exerciseID: String,
        position: Int,
        mode: ItemMode = .simple,
        supersetGroup: String? = nil,
        targets: [SetTarget],
        bySide: Bool? = nil,
        switchS: Int? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.removed = removed
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        self.position = position
        self.mode = mode
        self.supersetGroup = supersetGroup
        self.targets = targets
        self.bySide = bySide
        self.switchS = switchS
        self.note = note
    }
}

public struct FolderRow: SyncRow {
    public var id: String
    public var createdAt: Int
    public var updatedAt: Int
    public var deleted: Bool
    public var name: String
    public var position: Int
}

public struct WorkoutRow: SyncRow {
    public var id: String
    public var createdAt: Int
    public var updatedAt: Int
    public var deleted: Bool
    @Nullable public var folderId: String?
    public var sport: Sport
    public var name: String
    @Nullable public var note: String?
    public var position: Int
}

public struct WorkoutItemRow: SyncRow {
    public var id: String
    public var createdAt: Int
    public var updatedAt: Int
    public var deleted: Bool
    public var workoutId: String
    public var exerciseId: String
    public var position: Int
    public var mode: ItemMode
    @Nullable public var supersetGroup: String?
    public var targets: [SetTarget]
    @Nullable public var bySide: Bool?
    @Nullable public var switchS: Int?
    @Nullable public var note: String?
}

extension Folder: SyncedModel {
    public convenience init(_ row: FolderRow) {
        self.init(
            id: row.id,
            createdAt: Date(epochMilliseconds: row.createdAt),
            updatedAt: Date(epochMilliseconds: row.updatedAt),
            removed: row.deleted,
            name: row.name,
            position: row.position
        )
    }

    public func update(from row: FolderRow) {
        createdAt = Date(epochMilliseconds: row.createdAt)
        updatedAt = Date(epochMilliseconds: row.updatedAt)
        removed = row.deleted
        name = row.name
        position = row.position
    }

    public var row: FolderRow {
        FolderRow(
            id: id,
            createdAt: createdAt.epochMilliseconds,
            updatedAt: updatedAt.epochMilliseconds,
            deleted: removed,
            name: name,
            position: position
        )
    }

    public static func withIDs(_ ids: [String]) -> Predicate<Folder> {
        #Predicate { ids.contains($0.id) }
    }
}

extension Workout: SyncedModel {
    public convenience init(_ row: WorkoutRow) {
        self.init(
            id: row.id,
            createdAt: Date(epochMilliseconds: row.createdAt),
            updatedAt: Date(epochMilliseconds: row.updatedAt),
            removed: row.deleted,
            folderID: row.folderId,
            sport: row.sport,
            name: row.name,
            note: row.note,
            position: row.position
        )
    }

    public func update(from row: WorkoutRow) {
        createdAt = Date(epochMilliseconds: row.createdAt)
        updatedAt = Date(epochMilliseconds: row.updatedAt)
        removed = row.deleted
        folderID = row.folderId
        sport = row.sport
        name = row.name
        note = row.note
        position = row.position
    }

    public var row: WorkoutRow {
        WorkoutRow(
            id: id,
            createdAt: createdAt.epochMilliseconds,
            updatedAt: updatedAt.epochMilliseconds,
            deleted: removed,
            folderId: folderID,
            sport: sport,
            name: name,
            note: note,
            position: position
        )
    }

    public static func withIDs(_ ids: [String]) -> Predicate<Workout> {
        #Predicate { ids.contains($0.id) }
    }
}

extension WorkoutItem: SyncedModel {
    public convenience init(_ row: WorkoutItemRow) {
        self.init(
            id: row.id,
            createdAt: Date(epochMilliseconds: row.createdAt),
            updatedAt: Date(epochMilliseconds: row.updatedAt),
            removed: row.deleted,
            workoutID: row.workoutId,
            exerciseID: row.exerciseId,
            position: row.position,
            mode: row.mode,
            supersetGroup: row.supersetGroup,
            targets: row.targets,
            bySide: row.bySide,
            switchS: row.switchS,
            note: row.note
        )
    }

    public func update(from row: WorkoutItemRow) {
        createdAt = Date(epochMilliseconds: row.createdAt)
        updatedAt = Date(epochMilliseconds: row.updatedAt)
        removed = row.deleted
        workoutID = row.workoutId
        exerciseID = row.exerciseId
        position = row.position
        mode = row.mode
        supersetGroup = row.supersetGroup
        targets = row.targets
        bySide = row.bySide
        switchS = row.switchS
        note = row.note
    }

    public var row: WorkoutItemRow {
        WorkoutItemRow(
            id: id,
            createdAt: createdAt.epochMilliseconds,
            updatedAt: updatedAt.epochMilliseconds,
            deleted: removed,
            workoutId: workoutID,
            exerciseId: exerciseID,
            position: position,
            mode: mode,
            supersetGroup: supersetGroup,
            targets: targets,
            bySide: bySide,
            switchS: switchS,
            note: note
        )
    }

    public static func withIDs(_ ids: [String]) -> Predicate<WorkoutItem> {
        #Predicate { ids.contains($0.id) }
    }
}
