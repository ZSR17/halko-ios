import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct SessionGlanceTests {
    let container: ModelContainer
    let context: ModelContext
    let workout: Workout
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
        let workout = Workout(name: "Push A", position: 0)
        self.workout = workout
        context.insert(workout)
        context.insert(Exercise(id: "bench", name: "Bench press", exerciseType: .weightReps, equipment: ["barbell"]))
        context.insert(Exercise(id: "curl", name: "Curl", exerciseType: .weightReps))
        let warmup = SetTarget(kind: .warmup, reps: 10, weightG: 20_000, restS: 60)
        let set = SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 150)
        context.insert(WorkoutItem(workoutID: workout.id, exerciseID: "bench", position: 0, targets: [warmup, set, set]))
        context.insert(WorkoutItem(workoutID: workout.id, exerciseID: "curl", position: 1, targets: [SetTarget(kind: .normal, reps: 10, weightG: 12_000)]))
        try context.save()
    }

    @Test("The set to do, as planned: a warm-up is not counted")
    func first() throws {
        let state = try context.startSession(of: workout, now: start)
        let glance = try #require(try context.glance(of: state, unit: .kg))
        #expect(glance.exerciseID == "bench")
        #expect(glance.isWarmup)
        #expect(glance.values == SetValues(reps: 10, weightG: 20_000))

        var next = state
        try context.logSet(&next, step: 0, values: SetValues(reps: 10, weightG: 20_000), now: start + 60)
        let working = try #require(try context.glance(of: next, unit: .kg))
        #expect(!working.isWarmup)
        #expect(working.set == 1)
        #expect(working.workingNumber == 1)
    }

    @Test("During the rest, the set after it, raised to what the last set reached")
    func afterRest() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 10, weightG: 20_000), now: start + 60)
        try context.logSet(&state, step: 1, values: SetValues(reps: 10, weightG: 80_000), startedFrom: SetValues(reps: 8, weightG: 80_000), now: start + 200)
        #expect(state.isResting(at: start + 210))
        let glance = try #require(try context.glance(of: state, unit: .kg))
        #expect(glance.set == 2)
        #expect(glance.workingNumber == 2)
        #expect(glance.values == SetValues(reps: 10, weightG: 80_000))
    }

    @Test("Values changed on either device show outside the app; what they add is counted from the values offered")
    func changed() throws {
        var state = try context.startSession(of: workout, now: start)
        state.edits[state.livePlan.key(state.livePlan.steps[0])] = SetValues(reps: 12, weightG: 22_500)
        let glance = try #require(try context.glance(of: state, unit: .kg))
        #expect(glance.values == SetValues(reps: 12, weightG: 22_500))
        #expect(glance.startedFrom == SetValues(reps: 10, weightG: 20_000))
    }

    @Test("Every set done: nothing to show")
    func allDone() throws {
        var state = try context.startSession(of: workout, now: start)
        for (step, values) in [SetValues(reps: 10, weightG: 20_000), SetValues(reps: 8, weightG: 80_000), SetValues(reps: 8, weightG: 80_000), SetValues(reps: 10, weightG: 12_000)].enumerated() {
            try context.logSet(&state, step: step, values: values, now: start + Double(step * 100))
        }
        #expect(try context.glance(of: state, unit: .kg) == nil)
    }
}
