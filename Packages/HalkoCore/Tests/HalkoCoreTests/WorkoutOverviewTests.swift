import Foundation
import Testing
@testable import HalkoCore

struct WorkoutOverviewTests {
    let squat = Exercise(id: "squat", name: "Squat", exerciseType: .weightReps, primaryMuscles: [.quads], secondaryMuscles: [.glutes, .hamstrings])
    let lunge = Exercise(id: "lunge", name: "Lunge", exerciseType: .weightReps, primaryMuscles: [.quads, .glutes], secondaryMuscles: [.hamstrings])
    let bench = Exercise(id: "bench", name: "Bench press", exerciseType: .weightReps, primaryMuscles: [.chest], secondaryMuscles: [.shoulders, .triceps])
    let plank = Exercise(id: "plank", name: "Plank", exerciseType: .duration, primaryMuscles: [.abs], secondaryMuscles: [.shoulders, .lowerback])

    func item(_ id: String, _ exercise: Exercise, sets: Int = 3, warmups: Int = 0) -> WorkoutItem {
        let targets = Array(repeating: SetTarget(kind: .warmup, reps: 5), count: warmups)
            + Array(repeating: SetTarget(kind: .normal, reps: 8), count: sets)
        return WorkoutItem(id: id, workoutID: "w", exerciseID: exercise.id, position: 0, targets: targets)
    }

    func set(_ item: WorkoutItem?, exercise: String? = nil, kind: SetKind = .normal) -> SetLog {
        SetLog(sessionID: "s", exerciseID: exercise ?? item?.exerciseID ?? "", workoutItemID: item?.id, position: 0, setIndex: 0, kind: kind, completedAt: .now)
    }

    @Test("Puts the most frequent primary muscles first, then the secondary ones")
    func mainMuscles() {
        let items = [item("1", bench), item("2", squat), item("3", lunge), item("4", plank)]
        let muscles = WorkedMuscles.main(items: items, exercises: [squat, lunge, bench, plank], limit: 6)
        #expect(muscles == [
            WorkedMuscle(muscle: .quads, role: .primary),
            WorkedMuscle(muscle: .chest, role: .primary),
            WorkedMuscle(muscle: .glutes, role: .primary),
            WorkedMuscle(muscle: .abs, role: .primary),
            WorkedMuscle(muscle: .shoulders, role: .secondary),
            WorkedMuscle(muscle: .hamstrings, role: .secondary),
        ])
        #expect(WorkedMuscles.main(items: items, exercises: [squat, lunge, bench, plank], limit: 2).count == 2)
    }

    @Test("Leaves out the exercises not there yet")
    func missingExercise() {
        let muscles = WorkedMuscles.main(items: [item("1", bench), item("2", squat)], exercises: [squat], limit: 3)
        #expect(muscles.map(\.muscle) == [.quads, .glutes, .hamstrings])
    }

    @Test("Finds the first planned exercise with working sets left")
    func plannedProgress() {
        let items = [item("1", bench, sets: 2, warmups: 2), item("2", squat), item("3", plank)]
        #expect(SessionProgress(items: items, sets: []) == SessionProgress(exercise: 1, exerciseCount: 3))

        let warmedUp = [set(items[0], kind: .warmup), set(items[0], kind: .warmup), set(items[0])]
        #expect(SessionProgress(items: items, sets: warmedUp) == SessionProgress(exercise: 1, exerciseCount: 3))
        #expect(SessionProgress(items: items, sets: warmedUp + [set(items[0])]) == SessionProgress(exercise: 2, exerciseCount: 3))

        let all = items.flatMap { item in (0..<3).map { _ in set(item) } }
        #expect(SessionProgress(items: items, sets: all) == SessionProgress(exercise: 3, exerciseCount: 3))
    }

    @Test("Counts the exercises done without a plan")
    func freeProgress() {
        #expect(SessionProgress(items: [], sets: []) == nil)
        #expect(SessionProgress(items: [], sets: [set(nil, exercise: "bench", kind: .warmup)]) == nil)
        let sets = [set(nil, exercise: "bench"), set(nil, exercise: "bench"), set(nil, exercise: "squat")]
        #expect(SessionProgress(items: [], sets: sets) == SessionProgress(exercise: 2, exerciseCount: 2))
    }
}
