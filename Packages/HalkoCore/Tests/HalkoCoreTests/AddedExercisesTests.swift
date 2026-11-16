import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct AddedExercisesTests {
    let container: ModelContainer
    let context: ModelContext
    let workout: Workout
    let items: [WorkoutItem]
    let dips: Exercise
    let fly: Exercise
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
        let workout = Workout(name: "Push A", position: 0)
        self.workout = workout
        context.insert(workout)
        context.insert(Exercise(id: "bench", name: "Bench press", exerciseType: .weightReps, equipment: ["barbell"]))
        context.insert(Exercise(id: "curl", name: "Curl", exerciseType: .weightReps))
        dips = Exercise(id: "dips", name: "Dips", exerciseType: .bodyweightReps)
        fly = Exercise(id: "fly", name: "Fly", exerciseType: .weightReps)
        context.insert(dips)
        context.insert(fly)
        let set = SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 150)
        let curl = SetTarget(kind: .normal, reps: 10, weightG: 12_000, restS: 60)
        items = [
            WorkoutItem(workoutID: workout.id, exerciseID: "bench", position: 0, targets: [set, set]),
            WorkoutItem(workoutID: workout.id, exerciseID: "curl", position: 1, targets: [curl]),
        ]
        for item in items {
            context.insert(item)
        }
        try context.save()
    }

    func session(_ state: LiveState) throws -> Session {
        let id = state.sessionID
        return try #require(try context.fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })).first)
    }

    @Test("Exercises added go at the end, planned as in a workout; the set to do stays")
    func addingAtTheEnd() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 8, weightG: 80_000), now: start + 60)
        let cursor = state.cursor
        try context.addExercises(&state, [dips, fly], unit: .kg)
        #expect(state.plan.map(\.exerciseID) == ["bench", "curl", "dips", "fly"])
        #expect(state.plan[2].targets.count == 3)
        #expect(state.isAdded(2) && state.isAdded(3) && !state.isAdded(0))
        #expect(state.cursor == cursor)
    }

    @Test("An exercise added after another goes right after it, and the sets done keep their exercise")
    func addingAfter() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 8, weightG: 80_000), now: start + 60)
        try context.logSet(&state, step: 1, values: SetValues(reps: 8, weightG: 80_000), now: start + 120)
        try context.addExercises(&state, [dips], after: 0, unit: .kg)
        #expect(state.plan.map(\.exerciseID) == ["bench", "dips", "curl"])
        // The curl, still the set to do.
        #expect(state.livePlan.steps[state.cursor].item == 2)
        let curlStep = try #require(state.livePlan.stepIndex(item: 2, set: 0))
        try context.logSet(&state, step: curlStep, values: SetValues(reps: 10, weightG: 12_000), now: start + 180)
        let sets = try context.sets(of: state.sessionID)
        #expect(sets.first { $0.exerciseID == "curl" }?.position == 2)
    }

    @Test("Every set done: the exercise added is the set to do")
    func addingOnceDone() throws {
        var state = try context.startSession(of: workout, now: start)
        for step in 0..<3 {
            try context.logSet(&state, step: step, values: SetValues(reps: 8, weightG: 80_000), now: start + Double(60 * (step + 1)))
        }
        try context.addExercises(&state, [dips], unit: .kg)
        #expect(state.livePlan.steps[state.cursor].item == 2)
    }

    @Test("Once finished, the exercises added are found, and kept in the workout where they were done")
    func keeping() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 8, weightG: 80_000), now: start + 60)
        try context.addExercises(&state, [dips], after: 0, unit: .kg)
        let dipsStep = try #require(state.livePlan.stepIndex(item: 1, set: 0))
        try context.logSet(&state, step: dipsStep, values: SetValues(reps: 12), now: start + 120)
        let finished = try #require(try context.finishSession(state, now: start + 600))
        #expect(try context.addedExercises(of: finished) == ["dips"])

        try context.keepAddedExercises(of: finished, now: start + 700)
        let id = workout.id
        let kept = try context.fetch(FetchDescriptor(
            predicate: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id },
            sortBy: [SortDescriptor(\.position)]
        ))
        #expect(kept.map(\.exerciseID) == ["bench", "dips", "curl"])
        #expect(kept[1].targets.map(\.reps) == [12])
        #expect(try context.addedExercises(of: finished).isEmpty)
    }
}
