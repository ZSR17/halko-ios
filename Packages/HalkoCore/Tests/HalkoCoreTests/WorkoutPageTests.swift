import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct WorkoutPageTests {
    func item(_ id: String, superset: String? = nil, bySide: Bool? = nil, switchS: Int? = nil) -> WorkoutItem {
        WorkoutItem(id: id, workoutID: "w", exerciseID: id, position: 0, supersetGroup: superset, targets: [], bySide: bySide, switchS: switchS)
    }

    @Test("Puts the items of a superset together")
    func blocks() {
        let items = [item("1"), item("2", superset: "a"), item("3", superset: "a"), item("4", superset: "b"), item("5")]
        let blocks = ItemBlock.blocks(items)
        #expect(blocks.map { $0.items.map(\.id) } == [["1"], ["2", "3"], ["4"], ["5"]])
        #expect(blocks.map(\.isSuperset) == [false, true, false, false])
        #expect(blocks.map(\.id) == ["1", "2", "4", "5"])
    }

    @Test("Shows working sets alike once, with the warm-ups worked out")
    func plannedSets() {
        let working = SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 150)
        let targets = [SetTarget(kind: .warmup, restS: 60), SetTarget(kind: .warmup, restS: 60), working, working]
        let sets = PlannedSets(targets, type: .weightReps, equipment: ["barbell"], unit: .kg)
        #expect(sets.warmups.map(\.weightG) == [20_000, 67_500])
        #expect(sets.workedOut)
        #expect(sets.working == [working, working])
        #expect(sets.alike)
        #expect(sets.rest == 150)

        var heavier = working
        heavier.weightG = 85_000
        let pyramid = PlannedSets([working, heavier], type: .weightReps, equipment: [], unit: .kg)
        #expect(!pyramid.alike)
        #expect(pyramid.rest == 150)
        #expect(!pyramid.workedOut)

        var shorterRest = working
        shorterRest.restS = 90
        #expect(PlannedSets([working, shorterRest], type: .weightReps, equipment: [], unit: .kg).rest == nil)
        #expect(PlannedSets([SetTarget(kind: .normal, reps: 8, restS: 0)], type: .bodyweightReps, equipment: [], unit: .kg).rest == nil)
    }

    @Test("Does one side then the other, with a pause to change sides when timed")
    func sides() {
        let plank = Exercise(name: "Side bridge", exerciseType: .duration, unilateral: true)
        let lunge = Exercise(name: "Lunge", exerciseType: .weightReps, unilateral: true)
        let squat = Exercise(name: "Squat", exerciseType: .weightReps)
        #expect(item("1").doneBySide(plank))
        #expect(!item("1", bySide: false).doneBySide(plank))
        #expect(!item("1").doneBySide(squat))
        #expect(!item("1").doneBySide(nil))
        #expect(item("1").sidesPauseS(plank) == 5)
        #expect(item("1", switchS: 10).sidesPauseS(plank) == 10)
        #expect(item("1", bySide: false).sidesPauseS(plank) == nil)
        #expect(item("1").sidesPauseS(lunge) == nil)
    }

    @Test("Names a library exercise in the language of the app")
    func names() {
        let bench = Exercise(name: "Barbell Bench Press", exerciseType: .weightReps, translations: ["fr": ExerciseText(name: "Développé couché", instructions: [])])
        #expect(bench.name(in: "fr") == "Développé couché")
        #expect(bench.name(in: "en") == "Barbell Bench Press")
    }
}

struct WorkoutActionsTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
    }

    func items(of workout: Workout) throws -> [WorkoutItem] {
        let id = workout.id
        return try context.fetch(FetchDescriptor(predicate: #Predicate<WorkoutItem> { $0.workoutID == id }, sortBy: [SortDescriptor(\.position)]))
    }

    @Test("Duplicates a workout last, with its exercises and supersets of its own")
    func duplicate() throws {
        let folder = Folder(name: "PPL", position: 3)
        let push = Workout(folderID: folder.id, name: "Push", position: 0)
        context.insert(folder)
        context.insert(push)
        let targets = [SetTarget(kind: .normal, reps: 8, weightG: 80_000)]
        context.insert(WorkoutItem(workoutID: push.id, exerciseID: "bench", position: 0, targets: targets))
        context.insert(WorkoutItem(workoutID: push.id, exerciseID: "fly", position: 1, supersetGroup: "a", targets: targets))
        context.insert(WorkoutItem(workoutID: push.id, exerciseID: "dips", position: 2, supersetGroup: "a", targets: targets, bySide: false))
        context.insert(WorkoutItem(deleted: true, workoutID: push.id, exerciseID: "gone", position: 3, targets: targets))

        let copy = try context.duplicateWorkout(push, named: "Push (copy)")
        #expect(copy.id != push.id)
        #expect(copy.name == "Push (copy)")
        #expect(copy.folderID == folder.id)
        #expect(copy.position == 4)
        let copied = try items(of: copy)
        #expect(copied.map(\.exerciseID) == ["bench", "fly", "dips"])
        #expect(copied.allSatisfy { $0.targets == targets })
        #expect(copied[2].bySide == false)
        #expect(copied[0].supersetGroup == nil)
        #expect(copied[1].supersetGroup == copied[2].supersetGroup)
        #expect(copied[1].supersetGroup != "a")
        #expect(!context.hasChanges)
    }

    @Test("Deletes a workout with its exercises, kept for the sync")
    func remove() throws {
        let push = Workout(updatedAt: .distantPast, name: "Push", position: 0)
        context.insert(push)
        context.insert(WorkoutItem(workoutID: push.id, exerciseID: "bench", position: 0, targets: []))

        try context.removeWorkout(push)
        #expect(push.deleted)
        #expect(push.updatedAt > .distantPast)
        #expect(try items(of: push).allSatisfy(\.deleted))
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 1)
    }

    @Test("Moves a workout in and out of folders")
    func move() throws {
        let folder = Folder(name: "PPL", position: 0)
        let push = Workout(name: "Push", position: 1)
        let legs = Workout(name: "Legs", position: 2)
        for model in [folder, push, legs] as [any PersistentModel] {
            context.insert(model)
        }

        try context.moveWorkout(push, to: folder.id)
        #expect(push.folderID == folder.id)
        #expect(push.position == 1)
        try context.moveWorkout(push, to: nil)
        #expect(push.folderID == nil)
        #expect(push.position == 3)
    }
}
