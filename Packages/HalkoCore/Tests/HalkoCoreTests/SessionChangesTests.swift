import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct SessionChangesTests {
    // The watch's database and the iPhone's, in memory.
    let watch: ModelContext
    let phone: ModelContext
    let containers: [ModelContainer]
    let workout: Workout
    let item: WorkoutItem
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        containers = [try HalkoStore.container(inMemory: true), try HalkoStore.container(inMemory: true)]
        watch = ModelContext(containers[0])
        phone = ModelContext(containers[1])
        let workout = Workout(createdAt: start - 1000, updatedAt: start - 1000, name: "Push", position: 0)
        let item = WorkoutItem(
            createdAt: start - 1000,
            updatedAt: start - 1000,
            workoutID: workout.id,
            exerciseID: "bench",
            position: 0,
            targets: [SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 90)]
        )
        self.workout = workout
        self.item = item
        watch.insert(workout)
        watch.insert(item)
        watch.insert(Exercise(id: "bench", name: "Bench", exerciseType: .weightReps))
        try watch.save()
        try phone.apply(watch.planSnapshot())
    }

    // A session of the workout with its set done; `finish`: ended too.
    func session(finish: Bool) throws -> LiveState {
        var state = try watch.startSession(of: workout, now: start)
        try watch.logSet(&state, step: 0, values: SetValues(reps: 10, weightG: 85_000), now: start + 60)
        if finish {
            _ = try watch.finishSession(state, now: start + 120)
        }
        return state
    }

    @Test("A session in progress stays on its device")
    func inProgress() throws {
        _ = try session(finish: false)
        #expect(try watch.sessionChanges(since: .distantPast, items: true) == nil)
    }

    @Test("A finished session reaches the other device with its sets and the workout items it changed")
    func finished() throws {
        let state = try session(finish: true)
        let changes = try #require(try watch.sessionChanges(since: start - 1, items: true))
        try phone.apply(SessionChanges(decoding: changes.encoded()))

        let id = state.sessionID
        let session = try #require(try phone.fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })).first)
        #expect(session.endedAt == Date(epochMilliseconds: (start + 120).epochMilliseconds))
        #expect(try phone.sets(of: id).map(\.reps) == [10])
        let itemID = item.id
        let planned = try #require(try phone.fetch(FetchDescriptor(predicate: #Predicate<WorkoutItem> { $0.id == itemID })).first)
        #expect(planned.targets.first?.weightG == 85_000)
    }

    @Test("From the iPhone, the workout items are left out: its plan goes on its own")
    func withoutItems() throws {
        _ = try session(finish: true)
        #expect(try watch.sessionChanges(since: start - 1, items: false)?.items.isEmpty == true)
    }

    @Test("Handed over once: nothing more until something changes")
    func cursor() throws {
        _ = try session(finish: true)
        let changes = try #require(try watch.sessionChanges(since: .distantPast, items: true))
        #expect(try watch.sessionChanges(since: changes.cursor, items: true) == nil)

        // A set of history corrected later comes back with its session.
        let later = changes.cursor + 60
        let set = try #require(try watch.fetch(FetchDescriptor<SetLog>()).first)
        set.reps = 9
        set.updatedAt = later
        try watch.save()
        let correction = try #require(try watch.sessionChanges(since: changes.cursor, items: true))
        #expect(correction.sessions.count == 1)
        #expect(correction.sets.map(\.reps) == [9])
    }

    @Test("Received rows are the same on both sides: arriving twice, they change nothing")
    func twice() throws {
        let state = try session(finish: true)
        let changes = try #require(try watch.sessionChanges(since: .distantPast, items: true))
        try phone.apply(changes)
        try phone.apply(changes)
        let id = state.sessionID
        #expect(try phone.fetchCount(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })) == 1)
        #expect(try phone.sets(of: id).count == 1)
        #expect(!phone.hasChanges)
    }

    @Test("A session deleted reaches the other device as deleted")
    func deleted() throws {
        let state = try session(finish: true)
        let changes = try #require(try watch.sessionChanges(since: .distantPast, items: true))
        try phone.apply(changes)
        try watch.discardSession(state, now: start + 600)
        try phone.apply(#require(try watch.sessionChanges(since: changes.cursor, items: true)))
        let id = state.sessionID
        #expect(try phone.fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })).first?.removed == true)
        #expect(try phone.sets(of: id).isEmpty)
    }
}
