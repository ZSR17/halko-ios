import Foundation

// Values shared with the server (`shared/src/domain.ts`): the raw values are the ones of the sync rows.
// Units stored everywhere: grams, metres, seconds.

public enum Sport: String, Codable, Sendable, CaseIterable {
    case strength, running, cycling, cardio, other
}

public enum ExerciseSource: String, Codable, Sendable {
    case builtin, custom
}

// What a set of the exercise records.
public enum ExerciseType: String, Codable, Sendable, CaseIterable {
    case weightReps = "weight_reps"
    case bodyweightReps = "bw_reps"
    case weightedBodyweight = "weighted_bw"
    case assistedBodyweight = "assisted_bw"
    case duration
    case durationWeight = "duration_weight"
    case distanceDuration = "distance_duration"
    case weightDistance = "weight_distance"
}

// Same granularity as free-exercise-db.
public enum Muscle: String, Codable, Sendable, CaseIterable {
    case abs, abductors, adductors, biceps, calves, chest, forearms, glutes, hamstrings, lats
    case lowerback, middleback, neck, quads, shoulders, traps, triceps
}

public enum SetKind: String, Codable, Sendable, CaseIterable {
    case warmup, normal, drop, failure
}

// `simple` repeats identical targets; `perSet` gives each set its own.
public enum ItemMode: String, Codable, Sendable {
    case simple
    case perSet = "per_set"
}

// One planned set of a workout item.
public struct SetTarget: Codable, Hashable, Sendable {
    public var kind: SetKind
    public var reps: Int?
    public var weightG: Int?
    public var durationS: Double?
    public var distanceM: Double?
    public var restS: Int?

    public init(kind: SetKind, reps: Int? = nil, weightG: Int? = nil, durationS: Double? = nil, distanceM: Double? = nil, restS: Int? = nil) {
        self.kind = kind
        self.reps = reps
        self.weightG = weightG
        self.durationS = durationS
        self.distanceM = distanceM
        self.restS = restS
    }
}

// Name and instructions of a library exercise in one language.
public struct ExerciseText: Codable, Hashable, Sendable {
    public var name: String
    public var instructions: [String]
}
