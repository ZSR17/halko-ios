import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct LiveSnapshotTests {
    // The watch's database and the iPhone's, in memory.
    let watch: ModelContext
    let phone: ModelContext
    let containers: [ModelContainer]
    let workout: Workout
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let values = SetValues(reps: 8, weightG: 80_000)

    init() throws {
        containers = [try HalkoStore.container(inMemory: true), try HalkoStore.container(inMemory: true)]
        watch = ModelContext(containers[0])
        phone = ModelContext(containers[1])
        let workout = Workout(createdAt: start - 1000, updatedAt: start - 1000, name: "Push", position: 0)
        let target = SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 90)
        watch.insert(workout)
        watch.insert(WorkoutItem(createdAt: start - 1000, updatedAt: start - 1000, workoutID: workout.id, exerciseID: "bench", position: 0, targets: [target, target, target]))
        self.workout = workout
        try watch.save()
    }

    private func snapshot(_ context: ModelContext, _ state: LiveState) throws -> LiveSnapshot {
        try #require(try context.liveSnapshot(of: state.sessionID, state: state, recordsHealth: false))
    }

    // The state the snapshot comes to on the iPhone; nil when it does not go on.
    private func going(_ snapshot: LiveSnapshot, held: LiveState?) throws -> LiveState? {
        if case let .going(state) = try phone.apply(snapshot, held: held) {
            return state
        }
        return nil
    }

    @Test("A session started on one device goes on on the other with its sets and the set to do")
    func started() throws {
        var state = try watch.startSession(of: workout, now: start)
        try watch.logSet(&state, step: 0, values: values, now: start + 60)

        let received = try #require(try going(snapshot(watch, state), held: nil))

        #expect(received == state)
        #expect(try phone.sets(of: state.sessionID).map(\.reps) == [8])
    }

    @Test("The most recent action wins, whichever arrives last")
    func mostRecent() throws {
        let old = try watch.startSession(of: workout, now: start)
        let first = try snapshot(watch, old)
        var recent = old
        recent.restEndsAt = start + 90
        recent.changedAt = start + 1

        #expect(try going(first, held: recent) == recent)
        var second = first
        second.state = recent
        #expect(try going(second, held: old) == recent)
    }

    @Test("A session over ends on the other device, and stays over whatever arrives late")
    func over() throws {
        var state = try watch.startSession(of: workout, now: start)
        try watch.logSet(&state, step: 0, values: values, now: start + 60)
        let late = try snapshot(watch, state)
        _ = try #require(try watch.finishSession(state, now: start + 120))

        let last = try snapshot(watch, state)
        #expect(last.state == nil)
        guard case let .over(session) = try phone.apply(last, held: state) else {
            Issue.record("The session should be over")
            return
        }
        #expect(session.endedAt == start + 120)
        guard case .over = try phone.apply(late, held: nil) else {
            Issue.record("The session should stay over")
            return
        }
    }

    @Test("A session of the other device is left alone while another one goes on here")
    func unrelated() throws {
        let state = try watch.startSession(of: workout, now: start)
        let other = LiveState(sessionID: "other", workoutID: nil, plan: [])
        guard case .unrelated = try phone.apply(snapshot(watch, state), held: other) else {
            Issue.record("The session should be left alone")
            return
        }
        #expect(try phone.fetch(FetchDescriptor<Session>()).isEmpty)
    }

    @Test("The same set validated on both devices at once is kept once, and the next one is to do")
    func doneTwice() throws {
        var onWatch = try watch.startSession(of: workout, now: start)
        let started = try snapshot(watch, onWatch)
        var onPhone = try #require(try going(started, held: nil))
        try watch.logSet(&onWatch, step: 0, values: values, now: start + 60)
        try phone.logSet(&onPhone, step: 0, values: values, now: start + 61)
        let fromWatch = try snapshot(watch, onWatch)
        let fromPhone = try snapshot(phone, onPhone)

        onPhone = try #require(try going(fromWatch, held: onPhone))
        guard case let .going(state) = try watch.apply(fromPhone, held: onWatch) else {
            Issue.record("The session should go on")
            return
        }

        let id = onPhone.sessionID
        #expect(try phone.sets(of: id).map(\.id) == watch.sets(of: id).map(\.id))
        #expect(try phone.sets(of: id).count == 1)
        #expect(onPhone.cursor == 1)
        #expect(state.cursor == 1)
        #expect(try snapshot(phone, onPhone).says(sameAs: snapshot(watch, state)))
    }

    @Test("A rest over on its own is no news; an action is")
    func news() throws {
        var state = try watch.startSession(of: workout, now: start)
        try watch.logSet(&state, step: 0, values: values, now: start + 60)
        let before = try snapshot(watch, state)
        state.endRest()
        #expect(try snapshot(watch, state).says(sameAs: before))
        state.changedAt = start + 61
        #expect(try !snapshot(watch, state).says(sameAs: before))
    }

    @Test("A message comes out as it went in")
    func message() throws {
        let state = try watch.startSession(of: workout, now: start)
        let sent = try LiveMessage.snapshot(snapshot(watch, state))
        #expect(try LiveMessage(decoding: sent.encoded()) == sent)
    }

    @Test("Two parts of a workout make one result")
    func twoParts() {
        let phonePart = HealthResult(sessionID: "a", activeKilocalories: 20, averageHeartRate: nil, maximumHeartRate: nil)
        let watchPart = HealthResult(sessionID: "a", activeKilocalories: 100, averageHeartRate: 120, maximumHeartRate: 150)
        #expect(phonePart.adding(watchPart) == HealthResult(sessionID: "a", activeKilocalories: 120, averageHeartRate: 120, maximumHeartRate: 150))
    }
}

struct LiveSessionStoreTests {
    @MainActor
    @Test("An action is dated, after the last one whatever the clock says; the end of a rest on its own is not")
    func changedAt() {
        let store = LiveSessionStore(fileURL: nil)
        let future = Date.now + 1000
        store.set(LiveState(sessionID: "a", workoutID: nil, plan: [], restEndsAt: future, restTotalS: 90, changedAt: future))
        store.change { $0.lengthenRest() }
        let acted = store.state?.changedAt
        #expect(acted.map { $0 > future } == true)
        store.restOver()
        #expect(store.state?.restEndsAt == nil)
        #expect(store.state?.changedAt == acted)
    }
}
