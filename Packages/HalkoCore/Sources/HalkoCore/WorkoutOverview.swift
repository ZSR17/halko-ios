// What the list of workouts and the page of a workout show of a workout, or of a session in progress, at a glance.

public enum MuscleRole: Sendable {
    case primary, secondary
}

public struct WorkedMuscle: Hashable, Sendable {
    public let muscle: Muscle
    public let role: MuscleRole

    public init(muscle: Muscle, role: MuscleRole) {
        self.muscle = muscle
        self.role = role
    }

    // The muscles of an exercise: a muscle both primary and secondary is a primary one.
    public static func of(_ exercise: Exercise) -> [WorkedMuscle] {
        exercise.primaryMuscles.map { WorkedMuscle(muscle: $0, role: .primary) }
            + exercise.secondaryMuscles.filter { !exercise.primaryMuscles.contains($0) }.map { WorkedMuscle(muscle: $0, role: .secondary) }
    }
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

// The exercises of a workout in blocks, in order: the items of a superset together, every other item alone.
public struct ItemBlock: Identifiable {
    public let items: [WorkoutItem]

    public var id: String {
        items[0].id
    }

    // Done in turn without rest: a superset needs two items at least.
    public var isSuperset: Bool {
        items.count > 1
    }

    // `items` in order.
    public static func blocks(_ items: [WorkoutItem]) -> [ItemBlock] {
        var blocks: [[WorkoutItem]] = []
        for item in items {
            if let group = item.supersetGroup, let last = blocks.last?.last, last.supersetGroup == group {
                blocks[blocks.count - 1].append(item)
            } else {
                blocks.append([item])
            }
        }
        return blocks.map(ItemBlock.init)
    }
}

// The sets planned for an exercise of a workout, as its page shows them: the warm-ups with the values left to work
// out filled in, then the working sets.
public struct PlannedSets: Equatable, Sendable {
    public let warmups: [SetTarget]
    // Some warm-up value is worked out from the working sets rather than typed in.
    public let workedOut: Bool
    public let working: [SetTarget]

    public init(_ targets: [SetTarget], type: ExerciseType, equipment: [String], unit: WeightUnit) {
        let filled = Warmups.filledIn(targets, type: type, equipment: equipment, unit: unit)
        warmups = filled.filter { $0.kind == .warmup }
        workedOut = filled != targets
        working = filled.filter { $0.kind != .warmup }
    }

    // The working sets all have the same values and rest: shown once, with their number.
    public var alike: Bool {
        working.allSatisfy { $0.sameValues(as: working[0]) && $0.restS == working[0].restS }
    }

    // The rest after each working set, when it is the same for all of them and there is one.
    public var rest: Int? {
        guard let rest = working.first?.restS, rest > 0, working.allSatisfy({ $0.restS == rest }) else { return nil }
        return rest
    }
}

extension SetTarget {
    func sameValues(as other: SetTarget) -> Bool {
        reps == other.reps && weightG == other.weightG && durationS == other.durationS && distanceM == other.distanceM
    }
}

extension WorkoutItem {
    // Whether its sets are done one side then the other: an exercise working one side at a time, unless the workout
    // does it as a plain set.
    public func doneBySide(_ exercise: Exercise?) -> Bool {
        exercise?.unilateral == true && bySide != false
    }

    // The pause to change sides of a timed exercise done one side then the other; nil for any other.
    public func sidesPauseS(_ exercise: Exercise?) -> Int? {
        guard let exercise, doneBySide(exercise), exercise.exerciseType.metrics.contains(.duration) else { return nil }
        return switchS ?? defaultSwitchSidesS
    }
}
