import Foundation

// How a session in progress runs: the order of its sets, the rests, the values each set starts with. Same as the
// website (`client/src/lib/session.ts`).

// The values of a set, without the empty ones.
public struct SetValues: Codable, Hashable, Sendable {
    public var reps: Int?
    public var weightG: Int?
    public var durationS: Double?
    public var distanceM: Double?

    public init(reps: Int? = nil, weightG: Int? = nil, durationS: Double? = nil, distanceM: Double? = nil) {
        self.reps = reps
        self.weightG = weightG
        self.durationS = durationS
        self.distanceM = distanceM
    }

    public init(_ set: SetLog) {
        self.init(reps: set.reps, weightG: set.weightG, durationS: set.durationS, distanceM: set.distanceM)
    }

    // A measure; nothing for the rest.
    public subscript(field: SetField) -> Double? {
        get {
            switch field {
            case .reps: reps.map(Double.init)
            case .weight: weightG.map(Double.init)
            case .duration: durationS
            case .distance: distanceM
            case .rest: nil
            }
        }
        set {
            switch field {
            case .reps: reps = newValue.map { Int($0.rounded()) }
            case .weight: weightG = newValue.map { Int($0.rounded()) }
            case .duration: durationS = newValue
            case .distance: distanceM = newValue
            case .rest: break
            }
        }
    }

    static let measures: [SetField] = [.reps, .weight, .duration, .distance]

    // The values above those of `other`, field by field: what the next sets of the exercise must reach (15 reps done
    // instead of 11 brings a next set of 10 to 15). Decreases are left out: a set missed out of fatigue must not lower
    // the next ones.
    public func increase(over other: SetValues) -> SetValues {
        var result = SetValues()
        for field in Self.measures {
            if let value = self[field], let from = other[field], value > from {
                result[field] = value
            }
        }
        return result
    }

    // Without what `removed` brought (a set whose validation is undone); nil when nothing is left.
    public func lowered(by removed: SetValues) -> SetValues? {
        var result = SetValues()
        for field in Self.measures {
            if let value = self[field], value != removed[field] {
                result[field] = value
            }
        }
        return result.isEmpty ? nil : result
    }

    // Brought up to `bump` (values reached on an earlier set of the session); higher values stay.
    public func raised(to bump: SetValues?) -> SetValues {
        guard let bump else { return self }
        var result = self
        for field in Self.measures {
            if let value = bump[field] {
                result[field] = max(self[field] ?? 0, value)
            }
        }
        return result
    }

    public var isEmpty: Bool {
        self == SetValues()
    }
}

// An exercise of the session as planned when it started: changing the workout during the session moves nothing. Its
// sets change with the sets added or deleted during the session.
public struct PlanItem: Codable, Hashable, Sendable {
    public let itemID: String
    public let exerciseID: String
    public let exerciseType: ExerciseType
    // A barbell exercise warms up from the empty bar.
    public let equipment: [String]
    public let supersetGroup: String?
    public internal(set) var targets: [SetTarget]
    // Done one side then the other within each set (values per side), and the seconds to change sides of a timed set.
    public let unilateral: Bool
    public let switchS: Int?
    public let note: String?

    public init(
        itemID: String,
        exerciseID: String,
        exerciseType: ExerciseType,
        equipment: [String] = [],
        supersetGroup: String? = nil,
        targets: [SetTarget],
        unilateral: Bool = false,
        switchS: Int? = nil,
        note: String? = nil
    ) {
        self.itemID = itemID
        self.exerciseID = exerciseID
        self.exerciseType = exerciseType
        self.equipment = equipment
        self.supersetGroup = supersetGroup
        self.targets = targets
        self.unilateral = unilateral
        self.switchS = switchS
        self.note = note
    }

    public init(_ item: WorkoutItem, exercise: Exercise?) {
        let bySide = item.doneBySide(exercise)
        self.init(
            itemID: item.id,
            exerciseID: item.exerciseID,
            exerciseType: exercise?.exerciseType ?? .weightReps,
            equipment: exercise?.equipment ?? [],
            supersetGroup: item.supersetGroup,
            targets: item.targets,
            unilateral: bySide,
            switchS: bySide ? item.switchS : nil,
            note: item.note.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    // The pause to change sides of a timed exercise done one side then the other; nil for any other.
    public var sidesPauseS: Int? {
        unilateral && exerciseType.metrics.contains(.duration) ? switchS ?? defaultSwitchSidesS : nil
    }

    // The set number shown: warm-ups are not counted.
    public func workingNumber(_ set: Int) -> Int {
        targets.prefix(set + 1).count(where: { $0.kind != .warmup })
    }
}

// One set to do: the exercise (index in the plan), the set of the exercise (warm-ups included) and its target.
public struct LiveStep: Hashable, Sendable {
    public let item: Int
    public let set: Int
    public let target: SetTarget
}

// The plan of the session and the order of its sets.
public struct LivePlan: Sendable {
    public let items: [PlanItem]
    // In the order they are done.
    public let steps: [LiveStep]

    public init(items: [PlanItem]) {
        self.items = items
        steps = Self.steps(items: items)
    }

    public func setCount(_ item: Int) -> Int {
        items[item].targets.count
    }

    public func target(_ item: Int, set: Int) -> SetTarget {
        items[item].targets[set]
    }

    public func key(_ step: LiveStep) -> String {
        Self.key(items[step.item].itemID, step.set)
    }

    public static func key(_ itemID: String, _ set: Int) -> String {
        "\(itemID):\(set)"
    }

    public func stepIndex(item: Int, set: Int) -> Int? {
        steps.firstIndex { $0.item == item && $0.set == set }
    }

    // The rest after a step: none between the exercises of one round of a superset, else the set's own.
    public func rest(after index: Int) -> Int {
        guard steps.indices.contains(index), steps.indices.contains(index + 1) else { return 0 }
        let current = steps[index]
        let next = steps[index + 1]
        if let group = items[current.item].supersetGroup, items[next.item].supersetGroup == group,
           next.set == current.set, next.item > current.item {
            return 0
        }
        return current.target.restS ?? 90
    }

    // The first step after `index` (going round) not done yet; nil when everything is done.
    public func nextOpen(after index: Int, done: Set<String>) -> Int? {
        guard !steps.isEmpty else { return nil }
        for offset in 1...steps.count {
            let next = (index + offset) % steps.count
            if !done.contains(key(steps[next])) {
                return next
            }
        }
        return nil
    }

    // The set to do: the first one not done yet (the last one when all are done).
    public func firstOpen(done: Set<String>) -> Int {
        steps.firstIndex { !done.contains(key($0)) } ?? max(0, steps.count - 1)
    }

    // What a set starts with: the plan (which takes what was done at the end of each session), what it leaves to work
    // out from last time, raised to what earlier sets of the session reached (`bumps`). A warm-up left to work out is
    // worked out from today's working weight when there is no last time, or when that weight is above last time's.
    public func proposed(_ item: Int, set: Int, previous: [Int: SetValues], bumps: [String: SetValues], unit: WeightUnit) -> SetValues {
        let plan = items[item]
        let start = { (set: Int) in
            Self.prefill(target(item, set: set), previous: previous[set]).raised(to: bumps[Self.key(plan.itemID, set)])
        }
        let planned = target(item, set: set)
        guard planned.kind == .warmup, let working = plan.targets.firstIndex(where: { $0.kind != .warmup }) else {
            return start(set)
        }
        let today = start(working)
        let heavier = today.weightG.flatMap { today in previous[working]?.weightG.map { today > $0 } } ?? false
        if previous[set] != nil && !heavier {
            return start(set)
        }
        let worked = Warmups.filledIn(plan.targets, type: plan.exerciseType, equipment: plan.equipment, unit: unit, workingG: today.weightG)
        var values = start(set)
        if planned.weightG == nil, let weightG = worked[set].weightG {
            values.weightG = weightG
        }
        if planned.reps == nil, let reps = worked[set].reps {
            values.reps = reps
        }
        return values.raised(to: bumps[Self.key(plan.itemID, set)])
    }

    // The plan's values, else last time's.
    static func prefill(_ target: SetTarget, previous: SetValues?) -> SetValues {
        SetValues(
            reps: target.reps ?? previous?.reps,
            weightG: target.weightG ?? previous?.weightG,
            durationS: target.durationS ?? previous?.durationS,
            distanceM: target.distanceM ?? previous?.distanceM
        )
    }

    // The items of a superset are done round by round (A1 B1 A2 B2…); one with more sets than the others finishes
    // them alone.
    static func steps(items: [PlanItem]) -> [LiveStep] {
        var steps: [LiveStep] = []
        var start = 0
        while start < items.count {
            var end = start
            if let group = items[start].supersetGroup {
                while end + 1 < items.count, items[end + 1].supersetGroup == group {
                    end += 1
                }
            }
            let counts = (start...end).map { items[$0].targets.count }
            for round in 0..<(counts.max() ?? 0) {
                for item in start...end where round < counts[item - start] {
                    steps.append(LiveStep(item: item, set: round, target: items[item].targets[round]))
                }
            }
            start = end + 1
        }
        return steps
    }
}

// Load moved: weight × reps of the loaded exercises, both sides of a set done one side at a time.
public func setVolumeG(type: ExerciseType, values: SetValues, unilateral: Bool) -> Int {
    guard type == .weightReps || type == .weightedBodyweight else { return 0 }
    return (values.weightG ?? 0) * (values.reps ?? 0) * (unilateral ? 2 : 1)
}
