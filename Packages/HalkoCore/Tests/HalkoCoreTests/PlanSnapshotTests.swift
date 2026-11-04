import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct PlanSnapshotTests {
    // The iPhone's database and the watch's, in memory.
    let phone: ModelContext
    let watch: ModelContext
    let containers: [ModelContainer]

    init() throws {
        containers = [try HalkoStore.container(inMemory: true), try HalkoStore.container(inMemory: true)]
        phone = ModelContext(containers[0])
        watch = ModelContext(containers[1])
    }

    func exercise(_ id: String, media: [String]) -> Exercise {
        Exercise(id: id, name: id, exerciseType: .weightReps, mediaIDs: media)
    }

    @Test("Gives the watch the workouts, their folders and the exercises they use, and nothing else")
    func copiesThePlan() throws {
        let folder = Folder(name: "PPL", position: 0)
        let workout = Workout(folderID: folder.id, name: "Push", position: 0)
        phone.insert(folder)
        phone.insert(workout)
        phone.insert(WorkoutItem(workoutID: workout.id, exerciseID: "bench", position: 0, targets: [SetTarget(kind: .normal, reps: 8)]))
        phone.insert(exercise("bench", media: []))
        phone.insert(exercise("unused", media: []))
        try phone.save()

        let snapshot = try phone.planSnapshot()
        try watch.apply(PlanSnapshot(decoding: snapshot.encoded()))

        #expect(try watch.planSnapshot() == snapshot)
        #expect(snapshot.exercises.map(\.id) == ["bench"])
        #expect(try watch.fetchCount(FetchDescriptor<Exercise>()) == 1)
    }

    @Test("The same plan gives the same bytes, so that it is sent once")
    func sameBytes() throws {
        for position in 0..<5 {
            phone.insert(Workout(name: "W\(position)", position: position))
        }
        let exercise = exercise("e", media: [])
        exercise.translations = ["fr": ExerciseText(name: "E", instructions: []), "de": ExerciseText(name: "Ü", instructions: [])]
        phone.insert(exercise)
        try phone.save()

        #expect(try phone.planSnapshot().encoded() == phone.planSnapshot().encoded())
    }

    @Test("A row the watch has more recent is kept, a deleted one stays deleted")
    func newerWins() throws {
        let workout = Workout(name: "Push", position: 0)
        phone.insert(workout)
        try phone.save()
        try watch.apply(phone.planSnapshot())

        let older = try phone.planSnapshot()
        workout.name = "Push B"
        workout.removed = true
        workout.updatedAt = .now + 60
        try phone.save()
        try watch.apply(phone.planSnapshot())
        try watch.apply(older)

        let kept = try #require(try watch.fetch(FetchDescriptor<Workout>()).first)
        #expect(kept.name == "Push B")
        #expect(kept.removed)
    }

    @Test("The pictures to show: the first of each exercise of a workout still there")
    func mediaIDs() throws {
        let kept = Workout(name: "Push", position: 0)
        let deleted = Workout(removed: true, name: "Old", position: 1)
        watch.insert(kept)
        watch.insert(deleted)
        watch.insert(WorkoutItem(workoutID: kept.id, exerciseID: "bench", position: 0, targets: []))
        watch.insert(WorkoutItem(removed: true, workoutID: kept.id, exerciseID: "fly", position: 1, targets: []))
        watch.insert(WorkoutItem(workoutID: kept.id, exerciseID: "plank", position: 2, targets: []))
        watch.insert(WorkoutItem(workoutID: deleted.id, exerciseID: "squat", position: 0, targets: []))
        watch.insert(exercise("bench", media: ["b1", "b2"]))
        watch.insert(exercise("fly", media: ["f1"]))
        watch.insert(exercise("plank", media: []))
        watch.insert(exercise("squat", media: ["s1"]))
        try watch.save()

        #expect(try watch.planMediaIDs() == ["b1"])
    }
}
