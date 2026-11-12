import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct BackupTests {
    // The device exported from, and another one.
    let old: ModelContext
    let new: ModelContext
    let containers: [ModelContainer]
    let workout: Workout
    let original: ExerciseRow
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        containers = [try HalkoStore.container(inMemory: true), try HalkoStore.container(inMemory: true)]
        old = ModelContext(containers[0])
        new = ModelContext(containers[1])
        let workout = Workout(createdAt: start - 1000, updatedAt: start - 1000, name: "Push", position: 0)
        self.workout = workout
        old.insert(workout)
        old.insert(WorkoutItem(
            createdAt: start - 1000,
            updatedAt: start - 1000,
            workoutID: workout.id,
            exerciseID: "bench",
            position: 0,
            targets: [SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 90)]
        ))
        old.insert(Exercise(id: "bench", name: "Bench", exerciseType: .weightReps))
        // A library exercise the user changed.
        original = try #require(try ExerciseLibrary.rows().first)
        let changed = Exercise(original)
        changed.name = "Mine"
        changed.customized = true
        old.insert(changed)
        try old.save()
    }

    // A session of the workout with a set done; `finish`: ended too.
    @discardableResult
    func session(finish: Bool, at date: Date) throws -> LiveState {
        var state = try old.startSession(of: workout, now: date)
        try old.logSet(&state, step: 0, values: SetValues(reps: 10, weightG: 85_000), now: date + 60)
        if finish {
            _ = try old.finishSession(state, now: date + 120)
        }
        return state
    }

    // One session, one workout and one exercise of the user's, each new or there already.
    func imported(added: Int, alreadyThere: Int) -> ImportResult {
        let tally = ImportResult.Tally(added: added, alreadyThere: alreadyThere)
        return ImportResult(sessions: tally, workouts: tally, exercises: tally)
    }

    @Test("A file brings everything to another device once, the session in progress left out")
    func exportAndImport() throws {
        try session(finish: true, at: start)
        try session(finish: false, at: start + 1000)
        let plates = PlateSettings(barG: 20_000, plates: [Plate(weightG: 20_000, count: 2)])
        let file = try old.backup(plates: plates, at: start + 2000).encoded()

        let backup = try Backup(decoding: file)
        #expect(backup.plates == plates)
        #expect(backup.sessions.count == 1)
        #expect(backup.sets.count == 1)
        #expect(Set(backup.exercises.map(\.id)) == ["bench", original.id])
        #expect(try new.restore(backup) == imported(added: 1, alreadyThere: 0))
        #expect(try new.dataCounts() == DataCounts(sessions: 1, workouts: 1, exercises: 1))

        // Again: nothing twice.
        #expect(try new.restore(backup) == imported(added: 0, alreadyThere: 1))
        #expect(try new.fetchCount(FetchDescriptor<SetLog>()) == 1)
    }

    @Test("Nothing deleted by an import: a row deleted in the file is not applied")
    func importDeletesNothing() throws {
        try session(finish: true, at: start)
        var backup = try old.backup(plates: nil)
        _ = try new.restore(backup)
        backup.workouts[0].deleted = true
        backup.workouts[0].updatedAt += 1000
        _ = try new.restore(backup)
        #expect(try new.dataCounts().workouts == 1)
    }

    @Test("Everything back from a file after erasing, dated now so that the watch takes it back")
    func importAfterErase() throws {
        try session(finish: true, at: start)
        let backup = try old.backup(plates: nil, at: start + 1000)
        try old.eraseAll(at: start + 2000)

        #expect(try old.restore(backup, at: start + 3000) == imported(added: 1, alreadyThere: 0))
        #expect(try old.dataCounts() == DataCounts(sessions: 1, workouts: 1, exercises: 1))
        #expect(try old.fetchCount(FetchDescriptor<SetLog>(predicate: #Predicate { !$0.removed })) == 1)
        let snapshot = try old.planSnapshot()
        #expect(snapshot.workouts.allSatisfy { !$0.deleted && $0.updatedAt == (start + 3000).epochMilliseconds })
        let id = original.id
        let changed = try #require(try old.fetch(FetchDescriptor(predicate: #Predicate<Exercise> { $0.id == id })).first)
        #expect(changed.name == "Mine" && changed.customized)
    }

    @Test("A file of a later version is refused")
    func newerFormat() throws {
        var backup = try old.backup(plates: nil)
        backup.format = Backup.currentFormat + 1
        #expect(throws: Backup.ReadError.newerFormat) {
            try Backup(decoding: backup.encoded())
        }
    }

    @Test("Everything erased as deleted rows, the library back as it was, the session in progress kept")
    func eraseAll() throws {
        try session(finish: true, at: start)
        let current = try session(finish: false, at: start + 1000)
        try old.eraseAll(at: start + 2000)

        #expect(try old.dataCounts() == DataCounts(sessions: 0, workouts: 0, exercises: 0))
        // Rows the watch receives as deleted.
        #expect(try old.planSnapshot().workouts.allSatisfy(\.deleted))
        let id = original.id
        let restored = try #require(try old.fetch(FetchDescriptor(predicate: #Predicate<Exercise> { $0.id == id })).first)
        #expect(restored.name == original.name)
        #expect(!restored.customized && !restored.removed)
        #expect(restored.updatedAt == start + 2000)
        let currentID = current.sessionID
        let inProgress = try #require(try old.fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == currentID })).first)
        #expect(!inProgress.removed)
    }
}
