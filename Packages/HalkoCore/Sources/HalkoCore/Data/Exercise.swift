import Foundation
import SwiftData

// An exercise of the library (`builtin`) or made by the user (`custom`). A library exercise has its name and
// instructions in English, the other languages in `translations`; one the user changed (`customized`) has none:
// its text is shown as is.
@Model
public final class Exercise {
    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    // Kept, so that the deletion reaches every device (`deleted` of the rows: Core Data keeps that name).
    public var removed: Bool
    public var source: ExerciseSource
    public var name: String
    public var sport: Sport
    public var exerciseType: ExerciseType
    public var category: String?
    public var level: String?
    // As free-exercise-db names it ("barbell", "body only"…).
    public var equipment: [String]
    public var primaryMuscles: [Muscle]
    public var secondaryMuscles: [Muscle]
    public var instructions: [String]
    public var mediaIDs: [String]
    public var mediaURLs: [String]
    // Works one side at a time: its sets are done one side then the other, values per side.
    public var unilateral: Bool
    public var customized: Bool
    // By language code ("fr").
    public var translations: [String: ExerciseText]
    // free-exercise-db id of a library exercise: the same on every server, unlike `id`.
    public var sourceRef: String?

    public init(
        id: String = newRowID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        removed: Bool = false,
        source: ExerciseSource = .custom,
        name: String,
        sport: Sport = .strength,
        exerciseType: ExerciseType,
        category: String? = nil,
        level: String? = nil,
        equipment: [String] = [],
        primaryMuscles: [Muscle] = [],
        secondaryMuscles: [Muscle] = [],
        instructions: [String] = [],
        mediaIDs: [String] = [],
        mediaURLs: [String] = [],
        unilateral: Bool = false,
        customized: Bool = false,
        translations: [String: ExerciseText] = [:],
        sourceRef: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.removed = removed
        self.source = source
        self.name = name
        self.sport = sport
        self.exerciseType = exerciseType
        self.category = category
        self.level = level
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions
        self.mediaIDs = mediaIDs
        self.mediaURLs = mediaURLs
        self.unilateral = unilateral
        self.customized = customized
        self.translations = translations
        self.sourceRef = sourceRef
    }
}

// The server adds `mediaUrls`, `customized`, `translations` and `sourceRef` to the exercises it sends, and
// ignores them in the ones it receives.
public struct ExerciseRow: SyncRow {
    public var id: String
    public var createdAt: Int
    public var updatedAt: Int
    public var deleted: Bool
    public var source: ExerciseSource
    public var name: String
    public var sport: Sport
    public var exerciseType: ExerciseType
    @Nullable public var category: String?
    @Nullable public var level: String?
    public var equipment: [String]
    public var primaryMuscles: [Muscle]
    public var secondaryMuscles: [Muscle]
    public var instructions: [String]
    public var mediaIds: [String]
    public var mediaUrls: [String]
    public var unilateral: Bool
    public var customized: Bool
    public var translations: [String: ExerciseText]
    @Nullable public var sourceRef: String?
}

extension Exercise: SyncedModel {
    public convenience init(_ row: ExerciseRow) {
        self.init(
            id: row.id,
            createdAt: Date(epochMilliseconds: row.createdAt),
            updatedAt: Date(epochMilliseconds: row.updatedAt),
            removed: row.deleted,
            source: row.source,
            name: row.name,
            sport: row.sport,
            exerciseType: row.exerciseType,
            category: row.category,
            level: row.level,
            equipment: row.equipment,
            primaryMuscles: row.primaryMuscles,
            secondaryMuscles: row.secondaryMuscles,
            instructions: row.instructions,
            mediaIDs: row.mediaIds,
            mediaURLs: row.mediaUrls,
            unilateral: row.unilateral,
            customized: row.customized,
            translations: row.translations,
            sourceRef: row.sourceRef
        )
    }

    public func update(from row: ExerciseRow) {
        createdAt = Date(epochMilliseconds: row.createdAt)
        updatedAt = Date(epochMilliseconds: row.updatedAt)
        removed = row.deleted
        source = row.source
        name = row.name
        sport = row.sport
        exerciseType = row.exerciseType
        category = row.category
        level = row.level
        equipment = row.equipment
        primaryMuscles = row.primaryMuscles
        secondaryMuscles = row.secondaryMuscles
        instructions = row.instructions
        mediaIDs = row.mediaIds
        mediaURLs = row.mediaUrls
        unilateral = row.unilateral
        customized = row.customized
        translations = row.translations
        sourceRef = row.sourceRef
    }

    public var row: ExerciseRow {
        ExerciseRow(
            id: id,
            createdAt: createdAt.epochMilliseconds,
            updatedAt: updatedAt.epochMilliseconds,
            deleted: removed,
            source: source,
            name: name,
            sport: sport,
            exerciseType: exerciseType,
            category: category,
            level: level,
            equipment: equipment,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            instructions: instructions,
            mediaIds: mediaIDs,
            mediaUrls: mediaURLs,
            unilateral: unilateral,
            customized: customized,
            translations: translations,
            sourceRef: sourceRef
        )
    }

    public static func withIDs(_ ids: [String]) -> Predicate<Exercise> {
        #Predicate { ids.contains($0.id) }
    }
}

extension Exercise {
    // Its name in `language` ("fr"), if the library has it in it.
    public func name(in language: String) -> String {
        translations[language]?.name ?? name
    }

    public func instructions(in language: String) -> [String] {
        translations[language]?.instructions ?? instructions
    }
}
