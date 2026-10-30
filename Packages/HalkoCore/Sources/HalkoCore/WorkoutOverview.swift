// What the list of workouts shows of a workout or of a session in progress, at a glance.

public enum MuscleRole: Sendable {
    case primary, secondary
}

public struct WorkedMuscle: Hashable, Sendable {
    public let muscle: Muscle
    public let role: MuscleRole
}

public enum WorkedMuscles {
    // The muscles a workout works most: the primary muscles of its exercises, the most frequent first, then their
    // secondary ones. Equal counts keep the order of the workout. `exercises` may lack some of the items' exercises.
    public static func main(items: [WorkoutItem], exercises: [Exercise], limit: Int) -> [WorkedMuscle] {
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let worked = items.compactMap { byID[$0.exerciseID] }
        let primary = ranked(worked.map(\.primaryMuscles))
        let secondary = ranked(worked.map(\.secondaryMuscles)).filter { !primary.contains($0) }
        let muscles = primary.map { WorkedMuscle(muscle: $0, role: .primary) }
            + secondary.map { WorkedMuscle(muscle: $0, role: .secondary) }
        return Array(muscles.prefix(limit))
    }

    private static func ranked(_ lists: [[Muscle]]) -> [Muscle] {
        var counts: [Muscle: Int] = [:]
        var order: [Muscle] = []
        for muscle in lists.joined() {
            if counts[muscle] == nil {
                order.append(muscle)
            }
            counts[muscle, default: 0] += 1
        }
        return order.enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
            .map(\.element)
    }
}

// Where a session in progress is: the exercise being done, out of all of them.
public struct SessionProgress: Equatable, Sendable {
    // From 1.
    public let exercise: Int
    public let exerciseCount: Int

    public init(exercise: Int, exerciseCount: Int) {
        self.exercise = exercise
        self.exerciseCount = exerciseCount
    }

    // `items`: the planned exercises of the session's workout, in order. The one being done is the first with
    // working sets left (warm-ups are not counted); without a plan, the last exercise started. nil before
    // anything is planned or done.
    public init?(items: [WorkoutItem], sets: [SetLog]) {
        let working = sets.filter { $0.kind != .warmup }
        if items.isEmpty {
            let exercises = Set(working.map(\.exerciseID))
            guard !exercises.isEmpty else { return nil }
            self.init(exercise: exercises.count, exerciseCount: exercises.count)
            return
        }
        var done: [String: Int] = [:]
        for set in working {
            if let item = set.workoutItemID {
                done[item, default: 0] += 1
            }
        }
        let current = items.firstIndex { item in
            done[item.id, default: 0] < item.targets.count(where: { $0.kind != .warmup })
        }
        self.init(exercise: (current ?? items.count - 1) + 1, exerciseCount: items.count)
    }
}
