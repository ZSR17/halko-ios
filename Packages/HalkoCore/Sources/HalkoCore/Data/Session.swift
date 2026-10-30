import Foundation
import SwiftData

// A workout done (or in progress while `endedAt` is nil), from a planned workout or not.
@Model
public final class Session {
    #Index<Session>([\.startedAt])

    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    // Kept, so that the deletion reaches every device (`deleted` of the rows: Core Data keeps that name).
    public var removed: Bool
    public var workoutID: String?
    public var sport: Sport
    public var name: String
    public var startedAt: Date
    public var endedAt: Date?
    public var note: String?

    public init(
        id: String = newRowID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        removed: Bool = false,
        workoutID: String? = nil,
        sport: Sport = .strength,
        name: String,
        startedAt: Date,
        endedAt: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.removed = removed
        self.workoutID = workoutID
        self.sport = sport
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
    }
}

// A set performed during a session.
@Model
public final class SetLog {
    #Index<SetLog>([\.sessionID], [\.exerciseID, \.completedAt])

    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    public var removed: Bool
    public var sessionID: String
    public var exerciseID: String
    public var workoutItemID: String?
    // Order of the exercise in the session, and of the set within the exercise (warm-ups included).
    public var position: Int
    public var setIndex: Int
    public var kind: SetKind
    public var reps: Int?
    public var weightG: Int?
    public var durationS: Double?
    public var distanceM: Double?
    // The values are per side (copied from the exercise when the set was done).
    public var unilateral: Bool?
    public var completedAt: Date

    public init(
        id: String = newRowID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        removed: Bool = false,
        sessionID: String,
        exerciseID: String,
        workoutItemID: String? = nil,
        position: Int,
        setIndex: Int,
        kind: SetKind = .normal,
        reps: Int? = nil,
        weightG: Int? = nil,
        durationS: Double? = nil,
        distanceM: Double? = nil,
        unilateral: Bool? = nil,
        completedAt: Date
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.removed = removed
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.workoutItemID = workoutItemID
        self.position = position
        self.setIndex = setIndex
        self.kind = kind
        self.reps = reps
        self.weightG = weightG
        self.durationS = durationS
        self.distanceM = distanceM
        self.unilateral = unilateral
        self.completedAt = completedAt
    }
}

public struct SessionRow: SyncRow {
    public var id: String
    public var createdAt: Int
    public var updatedAt: Int
    public var deleted: Bool
    @Nullable public var workoutId: String?
    public var sport: Sport
    public var name: String
    public var startedAt: Int
    @Nullable public var endedAt: Int?
    @Nullable public var note: String?
}

// The measures are left out of the JSON when absent.
public struct SetLogRow: SyncRow {
    public var id: String
    public var createdAt: Int
    public var updatedAt: Int
    public var deleted: Bool
    public var sessionId: String
    public var exerciseId: String
    @Nullable public var workoutItemId: String?
    public var position: Int
    public var setIndex: Int
    public var kind: SetKind
    public var reps: Int?
    public var weightG: Int?
    public var durationS: Double?
    public var distanceM: Double?
    public var unilateral: Bool?
    public var completedAt: Int
}

extension Session: SyncedModel {
    public convenience init(_ row: SessionRow) {
        self.init(
            id: row.id,
            createdAt: Date(epochMilliseconds: row.createdAt),
            updatedAt: Date(epochMilliseconds: row.updatedAt),
            removed: row.deleted,
            workoutID: row.workoutId,
            sport: row.sport,
            name: row.name,
            startedAt: Date(epochMilliseconds: row.startedAt),
            endedAt: row.endedAt.map(Date.init(epochMilliseconds:)),
            note: row.note
        )
    }

    public func update(from row: SessionRow) {
        createdAt = Date(epochMilliseconds: row.createdAt)
        updatedAt = Date(epochMilliseconds: row.updatedAt)
        removed = row.deleted
        workoutID = row.workoutId
        sport = row.sport
        name = row.name
        startedAt = Date(epochMilliseconds: row.startedAt)
        endedAt = row.endedAt.map(Date.init(epochMilliseconds:))
        note = row.note
    }

    public var row: SessionRow {
        SessionRow(
            id: id,
            createdAt: createdAt.epochMilliseconds,
            updatedAt: updatedAt.epochMilliseconds,
            deleted: removed,
            workoutId: workoutID,
            sport: sport,
            name: name,
            startedAt: startedAt.epochMilliseconds,
            endedAt: endedAt?.epochMilliseconds,
            note: note
        )
    }

    public static func withIDs(_ ids: [String]) -> Predicate<Session> {
        #Predicate { ids.contains($0.id) }
    }
}

extension SetLog: SyncedModel {
    public convenience init(_ row: SetLogRow) {
        self.init(
            id: row.id,
            createdAt: Date(epochMilliseconds: row.createdAt),
            updatedAt: Date(epochMilliseconds: row.updatedAt),
            removed: row.deleted,
            sessionID: row.sessionId,
            exerciseID: row.exerciseId,
            workoutItemID: row.workoutItemId,
            position: row.position,
            setIndex: row.setIndex,
            kind: row.kind,
            reps: row.reps,
            weightG: row.weightG,
            durationS: row.durationS,
            distanceM: row.distanceM,
            unilateral: row.unilateral,
            completedAt: Date(epochMilliseconds: row.completedAt)
        )
    }

    public func update(from row: SetLogRow) {
        createdAt = Date(epochMilliseconds: row.createdAt)
        updatedAt = Date(epochMilliseconds: row.updatedAt)
        removed = row.deleted
        sessionID = row.sessionId
        exerciseID = row.exerciseId
        workoutItemID = row.workoutItemId
        position = row.position
        setIndex = row.setIndex
        kind = row.kind
        reps = row.reps
        weightG = row.weightG
        durationS = row.durationS
        distanceM = row.distanceM
        unilateral = row.unilateral
        completedAt = Date(epochMilliseconds: row.completedAt)
    }

    public var row: SetLogRow {
        SetLogRow(
            id: id,
            createdAt: createdAt.epochMilliseconds,
            updatedAt: updatedAt.epochMilliseconds,
            deleted: removed,
            sessionId: sessionID,
            exerciseId: exerciseID,
            workoutItemId: workoutItemID,
            position: position,
            setIndex: setIndex,
            kind: kind,
            reps: reps,
            weightG: weightG,
            durationS: durationS,
            distanceM: distanceM,
            unilateral: unilateral,
            completedAt: completedAt.epochMilliseconds
        )
    }

    public static func withIDs(_ ids: [String]) -> Predicate<SetLog> {
        #Predicate { ids.contains($0.id) }
    }
}
