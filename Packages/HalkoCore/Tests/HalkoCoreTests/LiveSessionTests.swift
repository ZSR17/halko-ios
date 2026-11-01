import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct LiveSessionTests {
    let container: ModelContainer
    let context: ModelContext
    let workout: Workout
    let items: [WorkoutItem]
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
        let workout = Workout(name: "Push A", position: 0)
        self.workout = workout
        context.insert(workout)
        context.insert(Exercise(id: "bench", name: "Bench press", exerciseType: .weightReps, equipment: ["barbell"]))
        context.insert(Exercise(id: "curl", name: "Curl", exerciseType: .weightReps, unilateral: true))
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

    @Test("Starting makes the session row and takes the plan of the workout")
    func starting() throws {
        let state = try context.startSession(of: workout, now: start)
        let session = try session(state)
        #expect(session.name == "Push A")
        #expect(session.workoutID == workout.id)
        #expect(session.endedAt == nil)
        #expect(state.plan.map(\.exerciseID) == ["bench", "curl"])
        #expect(state.plan[1].unilateral)
        #expect(state.livePlan.steps.count == 3)
    }

    @Test("A set validated is recorded, then the next one comes after the rest")
    func validating() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 10, weightG: 80_000), startedFrom: SetValues(reps: 8, weightG: 80_000), now: start + 60)
        let sets = try context.sets(of: state.sessionID)
        #expect(sets.count == 1)
        #expect(sets[0].reps == 10)
        #expect(sets[0].workoutItemID == items[0].id)
        #expect(state.cursor == 1)
        #expect(state.restEndsAt == start + 60 + 150)
        #expect(state.isResting(at: start + 100))
        // 2 more reps on the next set of the exercise.
        #expect(state.bumps[LivePlan.key(items[0].id, 1)] == SetValues(reps: 10))

        // Corrected: no new rest.
        state.endRest()
        try context.logSet(&state, step: 0, values: SetValues(reps: 9, weightG: 80_000), now: start + 120)
        #expect(try context.sets(of: state.sessionID).map(\.reps) == [9])
        #expect(state.restEndsAt == nil)
    }

    @Test("A set done one side at a time is marked so; the last set has no rest")
    func lastSet() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 8, weightG: 80_000), now: start + 60)
        try context.logSet(&state, step: 1, values: SetValues(reps: 8, weightG: 80_000), now: start + 300)
        try context.logSet(&state, step: 2, values: SetValues(reps: 10, weightG: 12_000), now: start + 600)
        #expect(try context.sets(of: state.sessionID).last?.unilateral == true)
        #expect(state.restEndsAt == nil)
        #expect(state.cursor == 2)
    }

    @Test("Undoing a set makes it the one to do and takes back what it added")
    func undoing() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 10, weightG: 80_000), startedFrom: SetValues(reps: 8, weightG: 80_000), now: start + 60)
        try context.unlogSet(&state, item: 0, set: 0, unit: .kg, now: start + 70)
        #expect(try context.sets(of: state.sessionID).isEmpty)
        #expect(state.cursor == 0)
        #expect(state.bumps[LivePlan.key(items[0].id, 1)] == nil)
    }

    @Test("A set added repeats the last one, for the session only")
    func addingASet() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.addSet(&state, item: 1, unit: .kg)
        #expect(state.livePlan.setCount(1) == 2)
        #expect(state.plan[1].targets[1] == state.plan[1].targets[0])
        #expect(items[1].targets.count == 1)
    }

    @Test("A set deleted takes its record with it; the sets after it move up")
    func deletingASet() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 8, weightG: 80_000), now: start + 60)
        try context.logSet(&state, step: 1, values: SetValues(reps: 6, weightG: 80_000), now: start + 300)
        try context.deleteSet(&state, item: 0, set: 0, now: start + 400)
        let sets = try context.sets(of: state.sessionID)
        #expect(sets.map(\.setIndex) == [0])
        #expect(sets.map(\.reps) == [6])
        #expect(state.livePlan.setCount(0) == 1)
        // The curl is the set to do.
        #expect(state.cursor == 1)
    }

    @Test("An exercise deleted takes its sets with it; one keeps a set, the session an exercise")
    func deletingAnExercise() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 8, weightG: 80_000), now: start + 60)
        try context.deleteExercise(&state, item: 0, now: start + 100)
        #expect(state.plan.map(\.exerciseID) == ["curl"])
        #expect(try context.sets(of: state.sessionID).isEmpty)
        #expect(state.cursor == 0)
        #expect(!state.canDeleteExercise)
        #expect(!state.canDeleteSet(of: 0))
    }

    @Test("Finishing ends the session and gives the workouts the values done")
    func finishing() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 8, weightG: 85_000), now: start + 60)
        try context.logSet(&state, step: 1, values: SetValues(reps: 8, weightG: 85_000), now: start + 300)
        let session = try #require(try context.finishSession(state, now: start + 900))
        #expect(session.endedAt == start + 900)
        #expect(items[0].targets.allSatisfy { $0.weightG == 85_000 })
        #expect(items[0].mode == .simple)
        // Not done: unchanged.
        #expect(items[1].targets[0].weightG == 12_000)
    }

    @Test("Finishing without a set done removes the session")
    func finishingEmpty() throws {
        let state = try context.startSession(of: workout, now: start)
        #expect(try context.finishSession(state, now: start + 60) == nil)
        #expect(try session(state).removed)
    }

    @Test("Last time: the sets of the last finished session, not those of the session in progress")
    func previous() throws {
        var first = try context.startSession(of: workout, now: start)
        try context.logSet(&first, step: 0, values: SetValues(reps: 6, weightG: 90_000), now: start + 60)
        _ = try context.finishSession(first, now: start + 900)
        var second = try context.startSession(of: workout, now: start + 86_400)
        try context.logSet(&second, step: 0, values: SetValues(reps: 8, weightG: 85_000), now: start + 86_460)
        #expect(try context.previousPerformance(of: "bench", excluding: second.sessionID) == [0: SetValues(reps: 6, weightG: 90_000)])
    }

    @Test("A session started elsewhere resumes at the first set not done")
    func resuming() throws {
        var state = try context.startSession(of: workout, now: start)
        try context.logSet(&state, step: 0, values: SetValues(reps: 8, weightG: 80_000), now: start + 60)
        let resumed = try context.resumedState(of: try session(state))
        #expect(resumed.cursor == 1)
        #expect(resumed.plan == state.plan)
    }

    @Test("The summary counts the working sets, the load moved and the records beaten")
    func summary() throws {
        var first = try context.startSession(of: workout, now: start)
        try context.logSet(&first, step: 0, values: SetValues(reps: 5, weightG: 80_000), now: start + 60)
        _ = try context.finishSession(first, now: start + 900)
        var second = try context.startSession(of: workout, now: start + 86_400)
        try context.logSet(&second, step: 0, values: SetValues(reps: 5, weightG: 90_000), now: start + 86_460)
        try context.logSet(&second, step: 2, values: SetValues(reps: 10, weightG: 12_000), now: start + 86_700)
        let session = try #require(try context.finishSession(second, now: start + 86_400 + 1800))
        let summary = try context.summary(of: session)
        #expect(summary.duration == 1800)
        #expect(summary.setCount == 2)
        // 90 × 5 + 12 × 10 per side.
        #expect(summary.volumeG == 450_000 + 240_000)
        #expect(summary.records.map(\.kind) == [.maxWeight, .oneRepMax])
        #expect(summary.records.first?.before == 80_000)
    }
}
