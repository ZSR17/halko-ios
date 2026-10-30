import Foundation

// What the page of an exercise shows of the sets done of it: the bests of the measures that count for its type,
// and the last time it was done. Warm-ups are left out. From the local history: the same without a server.

public enum RecordKind: Sendable {
    case maxWeight, oneRepMax, maxReps, maxAddedWeight, minAssistance, bestTime, maxDistance

    // The value of a set for this record, in stored units (grams, reps, seconds, metres); nil when it has none.
    func value(of set: SetLog) -> Double? {
        let value: Double? = switch self {
        case .maxWeight, .maxAddedWeight, .minAssistance: set.weightG.map(Double.init)
        case .oneRepMax: set.weightG.flatMap { weightG in set.reps.map { Double(OneRepMax.recordEstimate(weightG: weightG, reps: $0)) } }
        case .maxReps: set.reps.map(Double.init)
        case .bestTime: set.durationS
        case .maxDistance: set.distanceM
        }
        return value.flatMap { $0 > 0 ? $0 : nil }
    }

    // Less assistance is better.
    func isBetter(_ value: Double, than other: Double) -> Bool {
        self == .minAssistance ? value < other : value > other
    }
}

public struct ExerciseRecord: Equatable, Sendable {
    public let kind: RecordKind
    // In stored units: grams, reps, seconds, metres.
    public let value: Double
}

public struct ExerciseRecords: Equatable, Sendable {
    public let records: [ExerciseRecord]
    // The best working set of the last session the exercise was done in.
    public let lastSet: SetTarget?

    public init(sets: [SetLog], type: ExerciseType) {
        let working = sets.filter { $0.kind != .warmup }
        let kinds = Self.kinds(type)
        records = kinds.compactMap { kind in
            let values = working.compactMap(kind.value(of:))
            guard var best = values.first else { return nil }
            for value in values.dropFirst() where kind.isBetter(value, than: best) {
                best = value
            }
            return ExerciseRecord(kind: kind, value: best)
        }
        let main = kinds[0]
        let session = working.max { $0.completedAt < $1.completedAt }?.sessionID
        let last = working.filter { $0.sessionID == session }.reduce(nil) { (best: SetLog?, set) in
            guard let best, let value = main.value(of: set) else { return best ?? set }
            guard let bestValue = main.value(of: best) else { return set }
            return main.isBetter(value, than: bestValue) ? set : best
        }
        lastSet = last.map { SetTarget(kind: $0.kind, reps: $0.reps, weightG: $0.weightG, durationS: $0.durationS, distanceM: $0.distanceM) }
    }

    public var isEmpty: Bool {
        records.isEmpty && lastSet == nil
    }

    // The measures that count for each type of exercise, the main one first.
    static func kinds(_ type: ExerciseType) -> [RecordKind] {
        switch type {
        case .weightReps: [.maxWeight, .oneRepMax]
        case .bodyweightReps: [.maxReps]
        case .weightedBodyweight: [.maxAddedWeight]
        case .assistedBodyweight: [.minAssistance]
        case .duration: [.bestTime]
        case .durationWeight, .weightDistance: [.maxWeight]
        case .distanceDuration: [.maxDistance]
        }
    }
}
