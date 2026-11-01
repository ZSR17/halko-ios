#if DEBUG
import Foundation
import HalkoCore
import SwiftData

// Sample workouts for the interface tests (launch argument `-demo`), in a database kept in memory: the device's
// own data is never touched. The exercises are the embedded library's.
enum DemoData {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo")
    }

    static func container() throws -> ModelContainer {
        let container = try HalkoStore.container(inMemory: true)
        let context = container.mainContext
        let day: TimeInterval = 24 * 60 * 60

        let program = Folder(name: "PPL program", position: 0)
        let mobility = Folder(name: "Mobility", position: 1)
        let push = Workout(folderID: program.id, name: "Push A", position: 0)
        let pull = Workout(folderID: program.id, name: "Pull A", position: 1)
        let legs = Workout(folderID: program.id, name: "Legs", position: 2)
        let fullBody = Workout(name: "Full body express", position: 0)
        let core = Workout(name: "Core 15 min", position: 1)
        context.insert(program)
        context.insert(mobility)
        for workout in [
            push,
            pull,
            legs,
            Workout(folderID: mobility.id, name: "Morning mobility", position: 0),
            Workout(folderID: mobility.id, name: "Hips", position: 1),
            fullBody,
            core,
        ] {
            context.insert(workout)
        }

        // Push A as on the mockups: warm-ups worked out, a superset, an exercise done one side at a time.
        let work = { (sets: Int, target: SetTarget) in Array(repeating: target, count: sets) }
        let pushPlan: [(sourceRef: String, mode: ItemMode, superset: String?, targets: [SetTarget])] = [
            ("Barbell_Bench_Press_-_Medium_Grip", .perSet, nil, Array(repeating: SetTarget(kind: .warmup, restS: 60), count: 4)
                + work(4, SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 150))),
            ("Dumbbell_Shoulder_Press", .simple, nil, work(3, SetTarget(kind: .normal, reps: 10, weightG: 22_000, restS: 120))),
            ("Cable_Crossover", .simple, "push-superset", work(3, SetTarget(kind: .normal, reps: 12, weightG: 15_000))),
            ("Dips_-_Triceps_Version", .simple, "push-superset", work(3, SetTarget(kind: .normal, reps: 10, restS: 120))),
            ("Side_Bridge", .simple, nil, work(3, SetTarget(kind: .normal, durationS: 40, restS: 60))),
        ]
        let pushItems = pushPlan.enumerated().map { position, plan in
            WorkoutItem(
                workoutID: push.id,
                exerciseID: "lib-\(plan.sourceRef)",
                position: position,
                mode: plan.mode,
                supersetGroup: plan.superset,
                targets: plan.targets
            )
        }
        for item in pushItems {
            context.insert(item)
        }

        let plan: [(Workout, [String])] = [
            (pull, ["Pullups", "Bent_Over_Barbell_Row", "Seated_Cable_Rows", "Romanian_Deadlift", "Hanging_Leg_Raise"]),
            (legs, ["Barbell_Full_Squat", "Leg_Press", "Dumbbell_Lunges", "Romanian_Deadlift", "Standing_Calf_Raises", "Superman"]),
            (fullBody, ["Barbell_Full_Squat", "Barbell_Bench_Press_-_Medium_Grip", "Pullups", "Dumbbell_Lunges", "Barbell_Deadlift", "Plank"]),
            (core, ["Plank", "Crunches", "Side_Bridge", "Russian_Twist"]),
        ]
        for (workout, exercises) in plan {
            for (position, sourceRef) in exercises.enumerated() {
                context.insert(WorkoutItem(
                    workoutID: workout.id,
                    exerciseID: "lib-\(sourceRef)",
                    position: position,
                    targets: Array(repeating: SetTarget(kind: .normal, reps: 8, weightG: 60_000, restS: 120), count: 4)
                ))
            }
        }

        // An exercise made by the user, beside the library's.
        context.insert(Exercise(
            name: "Home weighted push-ups",
            exerciseType: .weightedBodyweight,
            equipment: ["body only"],
            primaryMuscles: [.chest],
            secondaryMuscles: [.shoulders, .triceps]
        ))

        context.insert(Session(workoutID: fullBody.id, name: fullBody.name, startedAt: .now - 5 * day, endedAt: .now - 5 * day + 3000))
        // Push A done before, heavier on the bench press: its records, with the session in progress.
        let earlier = Session(workoutID: push.id, name: push.name, startedAt: .now - 4 * day, endedAt: .now - 4 * day + 3600)
        context.insert(earlier)
        typealias DoneSet = (kind: SetKind, reps: Int, weightG: Int)
        let warmups: [DoneSet] = [(.warmup, 10, 20_000), (.warmup, 5, 32_500), (.warmup, 3, 50_000), (.warmup, 2, 67_500)]
        let benchSets: [DoneSet] = warmups + [(.normal, 3, 85_000), (.normal, 3, 85_000)]
        for (setIndex, set) in benchSets.enumerated() {
            context.insert(SetLog(
                sessionID: earlier.id,
                exerciseID: pushItems[0].exerciseID,
                workoutItemID: pushItems[0].id,
                position: 0,
                setIndex: setIndex,
                kind: set.kind,
                reps: set.reps,
                weightG: set.weightG,
                completedAt: earlier.startedAt + Double(5 + 4 * setIndex) * 60
            ))
        }
        context.insert(Session(workoutID: core.id, name: core.name, startedAt: .now - day, endedAt: .now - day + 900))
        // Push A in progress, as on the mockups: the warm-ups and the first working set of the bench press done.
        let session = Session(workoutID: push.id, name: push.name, startedAt: .now - 24 * 60 - 12)
        context.insert(session)
        let todaySets: [DoneSet] = warmups + [(.normal, 8, 80_000)]
        for (setIndex, set) in todaySets.enumerated() {
            context.insert(SetLog(
                sessionID: session.id,
                exerciseID: pushItems[0].exerciseID,
                workoutItemID: pushItems[0].id,
                position: 0,
                setIndex: setIndex,
                kind: set.kind,
                reps: set.reps,
                weightG: set.weightG,
                completedAt: .now - Double(20 - 3 * setIndex) * 60
            ))
        }
        try context.save()
        return container
    }
}
#endif
