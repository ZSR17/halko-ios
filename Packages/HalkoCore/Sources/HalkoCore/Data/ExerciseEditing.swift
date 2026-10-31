import Foundation
import SwiftData

// What the exercise editor changes, before it is saved: everything of an exercise the user may change. Same fields
// as the editor of the website (`client/src/pages/ExerciseEditor.tsx`), plus one side at a time.
public struct ExerciseDraft: Equatable, Sendable {
    public var name: String
    public var exerciseType: ExerciseType
    public var unilateral: Bool
    // As free-exercise-db names it, in the order chosen.
    public var equipment: [String]
    public var muscles: MusclePick
    public var steps: [ExerciseStep]
    // The first is the thumbnail.
    public var mediaIDs: [String]

    // A new exercise.
    public init() {
        name = ""
        exerciseType = .weightReps
        unilateral = false
        equipment = []
        muscles = MusclePick()
        steps = []
        mediaIDs = []
    }

    // The exercise as the user reads it: a library exercise in `language` ("fr").
    public init(_ exercise: Exercise, language: String) {
        name = exercise.name(in: language)
        exerciseType = exercise.exerciseType
        unilateral = exercise.unilateral
        equipment = exercise.equipment
        muscles = MusclePick(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles)
        steps = exercise.instructions(in: language).map(ExerciseStep.init)
        mediaIDs = exercise.mediaIDs
    }

    // An exercise needs a name.
    public var canSave: Bool {
        !savedName.isEmpty
    }

    // Whether saving would change something: blanks around the name and empty steps are not kept.
    public func differs(from other: ExerciseDraft) -> Bool {
        savedName != other.savedName
            || exerciseType != other.exerciseType
            || unilateral != other.unilateral
            || equipment != other.equipment
            || muscles != other.muscles
            || savedSteps != other.savedSteps
            || mediaIDs != other.mediaIDs
    }

    public func uses(_ equipment: Equipment) -> Bool {
        self.equipment.contains(equipment.rawValue)
    }

    public mutating func toggle(_ equipment: Equipment) {
        if uses(equipment) {
            self.equipment.removeAll { $0 == equipment.rawValue }
        } else {
            self.equipment.append(equipment.rawValue)
        }
    }

    var savedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var savedSteps: [String] {
        steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func write(to exercise: Exercise) {
        exercise.name = savedName
        exercise.exerciseType = exerciseType
        exercise.unilateral = unilateral
        exercise.equipment = equipment
        exercise.primaryMuscles = muscles.primary
        exercise.secondaryMuscles = muscles.secondary
        exercise.instructions = savedSteps
        exercise.mediaIDs = mediaIDs
    }
}

// One step of how to do an exercise, with an identity of its own while it is edited.
public struct ExerciseStep: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String

    public init(_ text: String) {
        id = UUID()
        self.text = text
    }
}

// Exercises created and changed on the device, written to the local database only: the sync sends them later.
// Same as the website (`client/src/db/exercises.ts`).
extension ModelContext {
    public func createExercise(_ draft: ExerciseDraft) throws -> Exercise {
        let exercise = Exercise(name: draft.savedName, exerciseType: draft.exerciseType)
        draft.write(to: exercise)
        insert(exercise)
        try save()
        return exercise
    }

    // A library exercise becomes the user's version: its text is now theirs, shown as is in every language.
    public func updateExercise(_ exercise: Exercise, with draft: ExerciseDraft) throws {
        draft.write(to: exercise)
        exercise.translations = [:]
        exercise.customized = exercise.source == .builtin
        exercise.updatedAt = .now
        try save()
    }

    // The library's version of an exercise the user changed, from the embedded library. Dated now, so that it
    // replaces the user's version on the other devices too.
    public func revertToLibrary(_ exercise: Exercise) throws {
        guard let row = try ExerciseLibrary.rows().first(where: { $0.id == exercise.id }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        exercise.update(from: row)
        exercise.updatedAt = .now
        try save()
    }

    // Only the user's own exercises can be deleted; the sets done of them stay in the history.
    public func removeExercise(_ exercise: Exercise) throws {
        exercise.removed = true
        exercise.updatedAt = .now
        try save()
    }

    // The sets done of an exercise, warm-ups included.
    public func doneSetCount(of exercise: Exercise) throws -> Int {
        let id = exercise.id
        return try fetchCount(FetchDescriptor<SetLog>(predicate: #Predicate { !$0.removed && $0.exerciseID == id }))
    }
}
