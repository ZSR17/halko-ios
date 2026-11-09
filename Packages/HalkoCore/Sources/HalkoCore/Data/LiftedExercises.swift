import Foundation
import SwiftData

// What the 1RM calculator can start from: the exercises done with a weight and reps, and their working sets. Same as the
// website (`liftedSets` of `client/src/db/sessions.ts`).
public struct LiftedExercise {
    public struct LiftedSet: Equatable, Sendable {
        public let weightG: Int
        public let reps: Int
    }

    public let exercise: Exercise
    public let sets: [LiftedSet]

    // The set with the highest estimate, the first one on a tie; a set past the formulas' range is left out.
    public func best(formula: OneRepMaxFormula) -> LiftedSet? {
        var best: (set: LiftedSet, estimate: Int)?
        for set in sets where set.reps <= OneRepMax.maxReps {
            let estimate = OneRepMax.estimate(weightG: set.weightG, reps: set.reps, formula: formula)
            if estimate > best?.estimate ?? 0 {
                best = (set, estimate)
            }
        }
        return best?.set
    }
}

extension ModelContext {
    public func liftedExercises() throws -> [LiftedExercise] {
        let finished = Set(try fetch(FetchDescriptor(predicate: #Predicate<Session> { !$0.removed && $0.endedAt != nil })).map(\.id))
        let sets = try fetch(FetchDescriptor(predicate: #Predicate<SetLog> { !$0.removed }, sortBy: [SortDescriptor(\.completedAt)]))
            .filter { finished.contains($0.sessionID) && $0.kind != .warmup && ($0.weightG ?? 0) > 0 && ($0.reps ?? 0) > 0 }
        let byExercise = Dictionary(grouping: sets, by: \.exerciseID)
        return try fetch(FetchDescriptor(predicate: Exercise.withIDs(Array(byExercise.keys))))
            .filter { !$0.removed && $0.exerciseType == .weightReps }
            .map { exercise in
                LiftedExercise(
                    exercise: exercise,
                    sets: (byExercise[exercise.id] ?? []).map { LiftedExercise.LiftedSet(weightG: $0.weightG ?? 0, reps: $0.reps ?? 0) }
                )
            }
            .sorted { $0.exercise.localizedName.localizedStandardCompare($1.exercise.localizedName) == .orderedAscending }
    }
}
