import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct ExerciseEditingTests {
    let container: ModelContainer
    let context: ModelContext
    let bench: ExerciseRow

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
        bench = try #require(try ExerciseLibrary.rows().first { $0.id == "lib-Barbell_Bench_Press_-_Medium_Grip" })
        try context.installLibrary([bench])
    }

    func stored(_ id: String) throws -> Exercise {
        try #require(try context.fetch(FetchDescriptor(predicate: Exercise.withIDs([id]))).first)
    }

    @Test("Reads a library exercise in the language of the app")
    func draftOfLibraryExercise() throws {
        let draft = ExerciseDraft(try stored(bench.id), language: "fr")
        #expect(draft.name == bench.translations["fr"]?.name)
        #expect(draft.steps.map(\.text) == bench.translations["fr"]?.instructions)
        #expect(draft.muscles.primary == [.chest])
        #expect(draft.equipment == ["barbell"])
        #expect(draft.mediaIDs == bench.mediaIds)
    }

    @Test("Keeps a muscle among both lists as a primary one")
    func overlappingMuscles() {
        let pick = MusclePick(primary: [.chest], secondary: [.chest, .triceps])
        #expect(pick.primary == [.chest])
        #expect(pick.secondary == [.triceps])
    }

    @Test("Counts as a change only what saving keeps")
    func differs() throws {
        let original = ExerciseDraft(try stored(bench.id), language: "en")
        var draft = original
        draft.name += "  "
        draft.steps.append(ExerciseStep(" "))
        #expect(!draft.differs(from: original))

        draft.toggle(.dumbbell)
        #expect(draft.differs(from: original))
        draft.toggle(.dumbbell)
        #expect(!draft.differs(from: original))

        draft.muscles.cycle([.triceps])
        #expect(draft.differs(from: original))
    }

    @Test("Needs a name")
    func canSave() {
        var draft = ExerciseDraft()
        #expect(!draft.canSave)
        draft.name = "   "
        #expect(!draft.canSave)
        draft.name = "Wall sit"
        #expect(draft.canSave)
    }

    @Test("Creates the user's own exercise")
    func create() throws {
        var draft = ExerciseDraft()
        draft.name = " Wall sit "
        draft.exerciseType = .duration
        draft.toggle(.bodyOnly)
        draft.muscles.cycle([.quads])
        draft.muscles.cycle([.glutes])
        draft.muscles.cycle([.glutes])
        draft.steps = [ExerciseStep("Back against the wall."), ExerciseStep(""), ExerciseStep("Thighs level. ")]

        let exercise = try context.createExercise(draft)

        let saved = try stored(exercise.id)
        #expect(saved.source == .custom && !saved.customized)
        #expect(saved.name == "Wall sit")
        #expect(saved.exerciseType == .duration)
        #expect(saved.equipment == ["body only"])
        #expect(saved.primaryMuscles == [.quads])
        #expect(saved.secondaryMuscles == [.glutes])
        #expect(saved.instructions == ["Back against the wall.", "Thighs level."])
        #expect(!context.hasChanges)
    }

    @Test("Makes the user's version of a library exercise, then goes back to the original")
    func versionAndRevert() throws {
        let exercise = try stored(bench.id)
        var draft = ExerciseDraft(exercise, language: "fr")
        draft.name = "Mon développé"
        draft.unilateral = true
        let before = exercise.updatedAt

        try context.updateExercise(exercise, with: draft)

        #expect(exercise.customized)
        #expect(exercise.translations.isEmpty)
        #expect(exercise.name(in: "fr") == "Mon développé")
        #expect(exercise.name(in: "en") == "Mon développé")
        #expect(exercise.unilateral)
        #expect(exercise.updatedAt > before)

        let changed = exercise.updatedAt
        try context.revertToLibrary(exercise)

        #expect(!exercise.customized)
        #expect(exercise.name == bench.name)
        #expect(exercise.translations == bench.translations)
        #expect(!exercise.unilateral)
        #expect(exercise.updatedAt > changed)
        #expect(!context.hasChanges)
    }

    @Test("Edits a custom exercise without making it a version")
    func editCustom() throws {
        var draft = ExerciseDraft()
        draft.name = "Wall sit"
        let exercise = try context.createExercise(draft)
        draft.name = "Wall squat hold"

        try context.updateExercise(exercise, with: draft)

        #expect(exercise.name == "Wall squat hold")
        #expect(!exercise.customized)
    }

    @Test("Deletes an exercise and keeps its sets")
    func remove() throws {
        var draft = ExerciseDraft()
        draft.name = "Wall sit"
        let exercise = try context.createExercise(draft)
        context.insert(SetLog(sessionID: "s", exerciseID: exercise.id, position: 0, setIndex: 0, durationS: 60, completedAt: .now))
        context.insert(SetLog(removed: true, sessionID: "s", exerciseID: exercise.id, position: 0, setIndex: 1, durationS: 50, completedAt: .now))
        try context.save()
        #expect(try context.doneSetCount(of: exercise) == 1)

        try context.removeExercise(exercise)

        #expect(try stored(exercise.id).removed)
        #expect(try context.doneSetCount(of: exercise) == 1)
    }
}
