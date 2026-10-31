import Foundation

// Changes to the planned sets of an exercise of a workout being edited, as the editor of the website makes them
// (`client/src/lib/targets.ts`).

// A value of a planned set: a measure of its type, or the rest after it.
public enum SetField: Hashable, Sendable {
    case reps, weight, duration, distance, rest

    public init(_ metric: Metric) {
        self = switch metric {
        case .reps: .reps
        case .weight: .weight
        case .duration: .duration
        case .distance: .distance
        }
    }
}

extension SetTarget {
    // In stored units: reps, grams, seconds, metres, seconds of rest.
    public subscript(field: SetField) -> Double? {
        get {
            switch field {
            case .reps: reps.map(Double.init)
            case .weight: weightG.map(Double.init)
            case .duration: durationS
            case .distance: distanceM
            case .rest: restS.map(Double.init)
            }
        }
        set {
            switch field {
            case .reps: reps = newValue.map { Int($0.rounded()) }
            case .weight: weightG = newValue.map { Int($0.rounded()) }
            case .duration: durationS = newValue
            case .distance: distanceM = newValue
            case .rest: restS = newValue.map { Int($0.rounded()) }
            }
        }
    }
}

public enum PlannedSetEdits {
    // What a newly added exercise plans without anything known of it: per type, as the website.
    public static func defaultTargets(_ type: ExerciseType, unit: WeightUnit) -> [SetTarget] {
        let (sets, target): (Int, SetTarget) = switch type {
        case .weightReps: (3, SetTarget(kind: .normal, reps: 10, weightG: 20_000, restS: 90))
        case .bodyweightReps: (3, SetTarget(kind: .normal, reps: 10, restS: 90))
        case .weightedBodyweight: (3, SetTarget(kind: .normal, reps: 8, weightG: 5000, restS: 90))
        case .assistedBodyweight: (3, SetTarget(kind: .normal, reps: 8, weightG: 20_000, restS: 90))
        case .duration: (3, SetTarget(kind: .normal, durationS: 30, restS: 60))
        case .durationWeight: (3, SetTarget(kind: .normal, weightG: 10_000, durationS: 30, restS: 60))
        case .distanceDuration: (1, SetTarget(kind: .normal, durationS: 1200, distanceM: 5000, restS: 0))
        case .weightDistance: (3, SetTarget(kind: .normal, weightG: 24_000, distanceM: 40, restS: 90))
        }
        var nice = target
        nice.weightG = target.weightG.map(unit.nice)
        return Array(repeating: nice, count: sets)
    }

    // Simple mode is N identical working sets: leaving set by set keeps the first working set as the model.
    public static func simple(_ targets: [SetTarget]) -> [SetTarget] {
        let working = targets.filter { $0.kind != .warmup }
        guard var model = working.first ?? targets.first else { return [] }
        model.kind = .normal
        return Array(repeating: model, count: max(1, working.count))
    }

    // Simple mode: `count` sets like the first.
    public static func withCount(_ targets: [SetTarget], _ count: Int) -> [SetTarget] {
        guard let model = targets.first, count >= 1 else { return targets }
        return Array(repeating: model, count: count)
    }

    // Simple mode: a value typed applies to every set.
    public static func settingAll(_ targets: [SetTarget], _ field: SetField, to value: Double?) -> [SetTarget] {
        targets.map { target in
            var changed = target
            changed[field] = value
            return changed
        }
    }

    // A value typed on set `index`, as in a session: when it goes up from `from` (the value it showed), the next
    // sets below it are brought up to it. A decrease stays on that set, and a warm-up value left to work out stays
    // so. The rest is the set's own.
    public static func setting(_ targets: [SetTarget], _ field: SetField, to value: Double?, at index: Int, from: Double?) -> [SetTarget] {
        let up = if field != .rest, let value, let from { value > from } else { false }
        return targets.enumerated().map { offset, target in
            var changed = target
            if offset == index {
                changed[field] = value
            } else if up, offset > index, let current = target[field], let value, current < value {
                changed[field] = value
            }
            return changed
        }
    }

    // A set like the last one shown (its warm-up values filled in), as a working set.
    public static func addingSet(_ targets: [SetTarget], shown: [SetTarget], type: ExerciseType, unit: WeightUnit) -> [SetTarget] {
        guard var last = shown.last else { return Array(defaultTargets(type, unit: unit).prefix(1)) }
        last.kind = .normal
        return targets + [last]
    }

    // Set `index` turned into a warm-up, its values left to work out from the working sets, or into a working set
    // with the values it showed. `shown`: the sets as shown (`Warmups.filledIn`).
    public static func switchingKind(_ targets: [SetTarget], shown: [SetTarget], at index: Int, type: ExerciseType) -> [SetTarget] {
        guard targets.indices.contains(index) else { return targets }
        var changed = targets
        if targets[index].kind == .warmup {
            changed[index] = shown[index]
            changed[index].kind = .normal
        } else {
            changed[index].kind = .warmup
            if Warmups.weighted.contains(type) {
                changed[index].weightG = nil
                if type == .weightReps {
                    changed[index].reps = nil
                }
            }
        }
        return changed
    }

    // Whether a warm-up value is worked out from the working sets, not typed in.
    public static func isWorkedOut(_ target: SetTarget, _ field: SetField, type: ExerciseType) -> Bool {
        target.kind == .warmup && target[field] == nil && Warmups.weighted.contains(type)
            && (field == .weight || (field == .reps && type == .weightReps))
    }

    // Whether emptying the value of a warm-up gives it back to the working sets to work out.
    public static func canWorkOut(_ target: SetTarget, _ field: SetField, type: ExerciseType) -> Bool {
        var empty = target
        empty[field] = nil
        return isWorkedOut(empty, field, type: type)
    }
}
