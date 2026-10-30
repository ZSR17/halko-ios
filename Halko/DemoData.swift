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
        let fullBody = Workout(name: "Full body express", position: 0)
        let core = Workout(name: "Core 15 min", position: 1)
        context.insert(program)
        context.insert(mobility)
        for workout in [
            push,
            Workout(folderID: program.id, name: "Pull A", position: 1),
            Workout(folderID: program.id, name: "Legs", position: 2),
            Workout(folderID: mobility.id, name: "Morning mobility", position: 0),
            Workout(folderID: mobility.id, name: "Hips", position: 1),
            fullBody,
            core,
        ] {
            context.insert(workout)
        }

        let plan: [(Workout, [String])] = [
            (push, ["Barbell_Bench_Press_-_Medium_Grip", "Dumbbell_Shoulder_Press", "Cable_Crossover", "Dips_-_Triceps_Version", "Side_Bridge"]),
            (fullBody, ["Barbell_Full_Squat", "Barbell_Bench_Press_-_Medium_Grip", "Pullups", "Dumbbell_Lunges", "Barbell_Deadlift", "Plank"]),
            (core, ["Plank", "Crunches", "Side_Bridge", "Russian_Twist"]),
        ]
        var pushItems: [WorkoutItem] = []
        for (workout, exercises) in plan {
            for (position, sourceRef) in exercises.enumerated() {
                let item = WorkoutItem(
                    workoutID: workout.id,
                    exerciseID: "lib-\(sourceRef)",
                    position: position,
                    targets: Array(repeating: SetTarget(kind: .normal, reps: 8, weightG: 60_000, restS: 120), count: 4)
                )
                context.insert(item)
                if workout === push {
                    pushItems.append(item)
                }
            }
        }

        context.insert(Session(workoutID: fullBody.id, name: fullBody.name, startedAt: .now - 5 * day, endedAt: .now - 5 * day + 3000))
        context.insert(Session(workoutID: core.id, name: core.name, startedAt: .now - day, endedAt: .now - day + 900))
        // Push A in progress: the first exercise done.
        let session = Session(workoutID: push.id, name: push.name, startedAt: .now - 24 * 60 - 12)
        context.insert(session)
        for setIndex in 0..<4 {
            context.insert(SetLog(
                sessionID: session.id,
                exerciseID: pushItems[0].exerciseID,
                workoutItemID: pushItems[0].id,
                position: 0,
                setIndex: setIndex,
                reps: 8,
                weightG: 60_000,
                completedAt: .now - Double(20 - 4 * setIndex) * 60
            ))
        }
        try context.save()
        return container
    }
}
#endif
