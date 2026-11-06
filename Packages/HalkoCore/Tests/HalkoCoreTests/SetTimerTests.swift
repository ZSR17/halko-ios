import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct SetTimerTests {
    let context: ModelContext
    let container: ModelContainer
    let workout: Workout
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let values = SetValues(durationS: 60)

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
        let workout = Workout(createdAt: start - 1000, updatedAt: start - 1000, name: "Core", position: 0)
        let target = SetTarget(kind: .normal, durationS: 60, restS: 90)
        context.insert(workout)
        context.insert(WorkoutItem(createdAt: start - 1000, updatedAt: start - 1000, workoutID: workout.id, exerciseID: "plank", position: 0, targets: [target, target]))
        self.workout = workout
        try context.save()
    }

    private func started(_ settings: SetTimerSettings = SetTimerSettings(), sidesPauseS: Int? = nil, values: SetValues? = nil) throws -> LiveState {
        var state = try context.startSession(of: workout, now: start)
        let plan = state.livePlan
        state.startTimer(stepKey: plan.key(plan.steps[0]), values: values ?? self.values, startedFrom: self.values, sidesPauseS: sidesPauseS, settings: settings, now: start)
        return state
    }

    @Test("The time to get in position comes first, then the target, then nothing more")
    func changes() throws {
        let timer = try #require(try started().setTimer)
        #expect(timer.isWaiting(at: start + 4))
        #expect(timer.nextChange(after: start) == start + 5)
        #expect(!timer.isWaiting(at: start + 5))
        #expect(timer.nextChange(after: start + 5) == start + 65)
        #expect(timer.isOver(at: start + 65))
        #expect(timer.nextChange(after: start + 65) == nil)
    }

    @Test("Without getting in position, holding starts at once; begun early, it starts then")
    func position() throws {
        let off = try #require(try started(SetTimerSettings(getsInPosition: false)).setTimer)
        #expect(off.startsAt == start)
        var state = try started()
        state.beginHolding(now: start + 2)
        #expect(state.setTimer?.startsAt == start + 2)
    }

    @Test("The set is recorded with the time held, beyond the target too, and the next sets are not raised to it")
    func held() throws {
        var state = try started()
        try context.stopTimer(&state, now: start + 73)
        let sets = try context.sets(of: state.sessionID)
        #expect(sets.map(\.durationS) == [68])
        #expect(state.setTimer == nil)
        #expect(state.cursor == 1)
        #expect(state.restEndsAt == start + 73 + 90)
        #expect(state.bumps.isEmpty)
    }

    @Test("Stopped on its own, the time held is the target, however late")
    func stopsAtTarget() throws {
        var state = try started(SetTimerSettings(stopsAtTarget: true))
        let timer = try #require(state.setTimer)
        #expect(!timer.isDue(at: start + 64))
        #expect(timer.isDue(at: start + 65))
        try context.stopTimer(&state, now: start + 200)
        #expect(try context.sets(of: state.sessionID).map(\.durationS) == [60])
    }

    @Test("Without a target it goes on until stopped, even set to stop at the target")
    func noTarget() throws {
        let timer = try #require(try started(SetTimerSettings(stopsAtTarget: true), values: SetValues()).setTimer)
        #expect(timer.targetS == nil)
        #expect(!timer.stopsAtTarget)
        #expect(!timer.isDue(at: start + 1000))
        #expect(timer.nextChange(after: start + 5) == nil)
    }

    @Test("By sides: one side, the pause, the other side, and the shorter side is recorded")
    func sides() throws {
        var state = try started(sidesPauseS: 10)
        try context.stopTimer(&state, now: start + 45)
        let pause = try #require(state.setTimer)
        #expect(pause.firstSideS == 40)
        #expect(pause.isWaiting(at: start + 50))
        #expect(pause.startsAt == start + 55)
        #expect(!pause.isFirstSide)
        #expect(try context.sets(of: state.sessionID).isEmpty)
        try context.stopTimer(&state, now: start + 90)
        #expect(try context.sets(of: state.sessionID).map(\.durationS) == [35])
    }

    @Test("The other values of the set go with it")
    func otherValues() throws {
        var state = try started(values: SetValues(weightG: 10_000, durationS: 60))
        try context.stopTimer(&state, now: start + 35)
        let set = try #require(try context.sets(of: state.sessionID).first)
        #expect(set.weightG == 10_000)
        #expect(set.durationS == 30)
    }

    @Test("A timer goes from one device to the other, and ends once its set was done over there")
    func shared() throws {
        let other = try HalkoStore.container(inMemory: true)
        let phone = ModelContext(other)
        var state = try started()
        let snapshot = try #require(try context.liveSnapshot(of: state.sessionID, state: state, recordsHealth: false))
        guard case let .going(received) = try phone.apply(snapshot, held: nil) else {
            Issue.record("The session should go on")
            return
        }
        #expect(received.setTimer == state.setTimer)

        try context.stopTimer(&state, now: start + 35)
        var done = try #require(try context.liveSnapshot(of: state.sessionID, state: state, recordsHealth: false))
        done.state?.changedAt = nil
        guard case let .going(after) = try phone.apply(done, held: received) else {
            Issue.record("The session should go on")
            return
        }
        #expect(after.setTimer == nil)
    }

    @Test("The settings come back as they were saved, and default to five seconds and going on")
    func settings() throws {
        let defaults = try #require(UserDefaults(suiteName: "SetTimerTests-\(UUID().uuidString)"))
        #expect(SetTimerSettings(defaults: defaults) == SetTimerSettings())
        let chosen = SetTimerSettings(stopsAtTarget: true, getsInPosition: false, positionS: 12)
        chosen.save(to: defaults)
        #expect(SetTimerSettings(defaults: defaults) == chosen)
    }
}
