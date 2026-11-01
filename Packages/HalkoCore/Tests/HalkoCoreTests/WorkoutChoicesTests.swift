import Foundation
import SwiftData
import Testing
@testable import HalkoCore

// The models in a database of their own, as in the app: made without one, while other tests make theirs, they can
// crash the tests.
struct WorkoutChoicesTests {
    let container: ModelContainer
    let context: ModelContext
    let program: Folder
    let mobility: Folder
    let empty: Folder

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
        program = Folder(name: "PPL program", position: 1)
        mobility = Folder(name: "Mobility", position: 0)
        empty = Folder(name: "Empty", position: 2)
        for folder in [program, mobility, empty] {
            context.insert(folder)
        }
    }

    func kept<Model: PersistentModel>(_ model: Model) -> Model {
        context.insert(model)
        return model
    }

    func item(_ workout: Workout, _ exercise: String, position: Int = 0, removed: Bool = false) -> WorkoutItem {
        kept(WorkoutItem(removed: removed, workoutID: workout.id, exerciseID: exercise, position: position, targets: []))
    }

    @Test func groupsInTheOrderOfTheWorkoutsTab() {
        let push = kept(Workout(folderID: program.id, name: "Push A", position: 0))
        let pull = kept(Workout(folderID: program.id, name: "Pull A", position: 1))
        let hips = kept(Workout(folderID: mobility.id, name: "Hips", position: 0))
        let core = kept(Workout(name: "Core", position: 1))
        let fullBody = kept(Workout(name: "Full body", position: 0))
        let groups = WorkoutChoiceGroup.groups(
            workouts: [pull, core, hips, push, fullBody],
            folders: [program, empty, mobility],
            items: [],
            exerciseID: "bench"
        )
        // No group for a folder without workouts.
        #expect(groups.map(\.folder?.name) == [nil, "Mobility", "PPL program"])
        #expect(groups.map { $0.choices.map(\.workout.name) } == [["Full body", "Core"], ["Hips"], ["Push A", "Pull A"]])
    }

    @Test func countsTheExercisesAndFindsTheOneAdded() {
        let push = kept(Workout(name: "Push A", position: 0))
        let pull = kept(Workout(name: "Pull A", position: 1))
        let groups = WorkoutChoiceGroup.groups(
            workouts: [push, pull],
            folders: [],
            items: [item(push, "bench"), item(push, "dips", position: 1), item(pull, "row"), item(pull, "bench", removed: true)],
            exerciseID: "bench"
        )
        let choices = groups[0].choices
        #expect(choices.map(\.exerciseCount) == [2, 1])
        // Taken off Pull A: no longer in it.
        #expect(choices.map(\.hasExercise) == [true, false])
    }

    @Test func leavesOutWhatIsRemoved() {
        let gone = kept(Folder(removed: true, name: "Gone", position: 3))
        let orphan = kept(Workout(folderID: gone.id, name: "Orphan", position: 0))
        let removed = kept(Workout(removed: true, name: "Removed", position: 1))
        let groups = WorkoutChoiceGroup.groups(workouts: [orphan, removed], folders: [gone], items: [], exerciseID: "bench")
        // Its folder gone, the workout counts as in no folder.
        #expect(groups.map(\.folder?.name) == [nil])
        #expect(groups[0].choices.map(\.workout.name) == ["Orphan"])
    }

    @Test func nothingWithoutWorkouts() {
        #expect(WorkoutChoiceGroup.groups(workouts: [], folders: [program], items: [], exerciseID: "bench").isEmpty)
    }
}
