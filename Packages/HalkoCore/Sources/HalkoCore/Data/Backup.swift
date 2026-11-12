import Foundation
import SwiftData

// Everything of the user's in one file, to keep or to take to another device: the sessions done, the workouts and their
// folders, the exercises they made or changed, and the plates. The library's exercises are embedded in the app: only
// the user's are in it. Rows as in the sync, deleted ones left out.
public struct Backup: Codable, Equatable, Sendable {
    // Raised when a file of this version could no longer be read as it is.
    public static let currentFormat = 1

    public var format: Int
    public var exportedAt: Int
    public var folders: [FolderRow]
    public var workouts: [WorkoutRow]
    public var items: [WorkoutItemRow]
    public var exercises: [ExerciseRow]
    public var sessions: [SessionRow]
    public var sets: [SetLogRow]
    public var plates: PlateSettings?

    public enum ReadError: Error {
        // Made by a later version of the app.
        case newerFormat
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(Backup.self, from: data)
        guard format <= Self.currentFormat else {
            throw ReadError.newerFormat
        }
    }

    init(
        exportedAt: Date, folders: [FolderRow], workouts: [WorkoutRow], items: [WorkoutItemRow], exercises: [ExerciseRow],
        sessions: [SessionRow], sets: [SetLogRow], plates: PlateSettings?
    ) {
        format = Self.currentFormat
        self.exportedAt = exportedAt.epochMilliseconds
        self.folders = folders
        self.workouts = workouts
        self.items = items
        self.exercises = exercises
        self.sessions = sessions
        self.sets = sets
        self.plates = plates
    }
}

// What the device holds of the user's.
public struct DataCounts: Equatable, Sendable {
    public var sessions: Int
    public var workouts: Int
    public var exercises: Int
}

// The sessions of a file imported: those new to the device, and those it had already.
public struct ImportResult: Equatable, Sendable {
    public var added: Int
    public var alreadyThere: Int
}

extension ModelContext {
    public func dataCounts() throws -> DataCounts {
        DataCounts(
            sessions: try fetchCount(FetchDescriptor<Session>(predicate: #Predicate { !$0.removed && $0.endedAt != nil })),
            workouts: try fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { !$0.removed })),
            exercises: try fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.removed })).filter { $0.source == .custom }.count
        )
    }

    // The sessions in progress stay out: they go in once finished.
    public func backup(plates: PlateSettings?, at date: Date = .now) throws -> Backup {
        let sessions = try fetch(FetchDescriptor<Session>(predicate: #Predicate { !$0.removed && $0.endedAt != nil }, sortBy: [SortDescriptor(\.id)]))
        let sessionIDs = sessions.map(\.id)
        return Backup(
            exportedAt: date,
            folders: try fetch(FetchDescriptor<Folder>(predicate: #Predicate { !$0.removed }, sortBy: [SortDescriptor(\.id)])).map(\.row),
            workouts: try fetch(FetchDescriptor<Workout>(predicate: #Predicate { !$0.removed }, sortBy: [SortDescriptor(\.id)])).map(\.row),
            items: try fetch(FetchDescriptor<WorkoutItem>(predicate: #Predicate { !$0.removed }, sortBy: [SortDescriptor(\.id)])).map(\.row),
            exercises: try fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.removed }, sortBy: [SortDescriptor(\.id)]))
                .filter { $0.source == .custom || $0.customized }
                .map(\.row),
            sessions: sessions.map(\.row),
            sets: try fetch(FetchDescriptor<SetLog>(predicate: #Predicate { !$0.removed && sessionIDs.contains($0.sessionID) }, sortBy: [SortDescriptor(\.id)]))
                .map(\.row),
            plates: plates
        )
    }

    // Added to what is there, nothing removed: a row the device has already is kept, or replaced by a more recent
    // version, as in the sync. Deleted rows in the file are not applied.
    public func restore(_ backup: Backup) throws -> ImportResult {
        let ids = backup.sessions.filter { !$0.deleted }.map(\.id)
        let known = try fetch(FetchDescriptor(predicate: Session.withIDs(ids))).count
        try apply(backup.folders.filter { !$0.deleted }, to: Folder.self)
        try apply(backup.workouts.filter { !$0.deleted }, to: Workout.self)
        try apply(backup.items.filter { !$0.deleted }, to: WorkoutItem.self)
        try apply(backup.exercises.filter { !$0.deleted }, to: Exercise.self)
        try apply(backup.sessions.filter { !$0.deleted }, to: Session.self)
        try apply(backup.sets.filter { !$0.deleted }, to: SetLog.self)
        if hasChanges {
            try save()
        }
        return ImportResult(added: ids.count - known, alreadyThere: known)
    }

    // Everything of the user's deleted, as rows marked deleted so that the watch deletes them too. The library's
    // exercises stay, back as the library has them. The session in progress, if any, stays.
    public func eraseAll(at date: Date = .now) throws {
        for folder in try fetch(FetchDescriptor<Folder>(predicate: #Predicate { !$0.removed })) {
            folder.removed = true
            folder.updatedAt = date
        }
        for workout in try fetch(FetchDescriptor<Workout>(predicate: #Predicate { !$0.removed })) {
            workout.removed = true
            workout.updatedAt = date
        }
        for item in try fetch(FetchDescriptor<WorkoutItem>(predicate: #Predicate { !$0.removed })) {
            item.removed = true
            item.updatedAt = date
        }
        let sessions = try fetch(FetchDescriptor<Session>(predicate: #Predicate { !$0.removed && $0.endedAt != nil }))
        let sessionIDs = sessions.map(\.id)
        for session in sessions {
            session.removed = true
            session.updatedAt = date
        }
        for set in try fetch(FetchDescriptor<SetLog>(predicate: #Predicate { !$0.removed && sessionIDs.contains($0.sessionID) })) {
            set.removed = true
            set.updatedAt = date
        }
        let library = Dictionary(try ExerciseLibrary.rows().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for exercise in try fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.removed })) {
            if let original = library[exercise.id] {
                if exercise.customized {
                    exercise.update(from: original)
                    exercise.updatedAt = date
                }
            } else {
                exercise.removed = true
                exercise.updatedAt = date
            }
        }
        if hasChanges {
            try save()
        }
    }
}
