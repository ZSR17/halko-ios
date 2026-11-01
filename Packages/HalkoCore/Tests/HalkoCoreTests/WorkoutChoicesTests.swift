import Foundation
import Testing
@testable import HalkoCore

struct WorkoutChoicesTests {
    let program = Folder(name: "PPL program", position: 1)
    let mobility = Folder(name: "Mobility", position: 0)
    let empty = Folder(name: "Empty", position: 2)

    func item(_ workout: Workout, _ exercise: String, position: Int = 0, removed: Bool = false) -> WorkoutItem {
        WorkoutItem(removed: removed, workoutID: workout.id, exerciseID: exercise, position: position, targets: [])
    }

    @Test func groupsInTheOrderOfTheWorkoutsTab() {
        let push = Workout(folderID: program.id, name: "Push A", position: 0)
        let pull = Workout(folderID: program.id, name: "Pull A", position: 1)
        let hips = Workout(folderID: mobility.id, name: "Hips", position: 0)
        let core = Workout(name: "Core", position: 1)
        let fullBody = Workout(name: "Full body", position: 0)
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
        let push = Workout(name: "Push A", position: 0)
        let pull = Workout(name: "Pull A", position: 1)
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
        let gone = Folder(removed: true, name: "Gone", position: 3)
        let orphan = Workout(folderID: gone.id, name: "Orphan", position: 0)
        let removed = Workout(removed: true, name: "Removed", position: 1)
        let groups = WorkoutChoiceGroup.groups(workouts: [orphan, removed], folders: [gone], items: [], exerciseID: "bench")
        // Its folder gone, the workout counts as in no folder.
        #expect(groups.map(\.folder?.name) == [nil])
        #expect(groups[0].choices.map(\.workout.name) == ["Orphan"])
    }

    @Test func nothingWithoutWorkouts() {
        #expect(WorkoutChoiceGroup.groups(workouts: [], folders: [program], items: [], exerciseID: "bench").isEmpty)
    }
}
