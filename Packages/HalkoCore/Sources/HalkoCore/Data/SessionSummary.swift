import Foundation
import SwiftData

// What the end of a session shows: its duration, its working sets, the load moved and the records beaten, all
// worked out from the local history.
public struct SessionSummary: Equatable, Sendable {
    public struct BeatenRecord: Hashable, Sendable {
        public let exerciseID: String
        public let kind: RecordKind
        // In stored units: grams, reps, seconds, metres.
        public let value: Double
        public let before: Double
    }

    public let duration: TimeInterval
    public let setCount: Int
    public let volumeG: Int
    // In the order the exercises were done.
    public let records: [BeatenRecord]

    // `sets`: those of the session; `earlier`: those of the same exercises in sessions before it; `exercises`: theirs.
    public init(session: Session, sets: [SetLog], earlier: [SetLog], exercises: [Exercise]) {
        duration = (session.endedAt ?? session.startedAt).timeIntervalSince(session.startedAt)
        let types = Dictionary(exercises.map { ($0.id, $0.exerciseType) }, uniquingKeysWith: { first, _ in first })
        let working = sets.filter { $0.kind != .warmup }
        setCount = working.count
        volumeG = working.reduce(0) { total, set in
            total + setVolumeG(type: types[set.exerciseID] ?? .weightReps, values: SetValues(set), unilateral: set.unilateral == true)
        }
        var order: [String] = []
        for set in sets.sorted(by: { $0.completedAt < $1.completedAt }) where !order.contains(set.exerciseID) {
            order.append(set.exerciseID)
        }
        records = order.flatMap { exerciseID -> [BeatenRecord] in
            let type = types[exerciseID] ?? .weightReps
            let before = ExerciseRecords(sets: earlier.filter { $0.exerciseID == exerciseID }, type: type).records
            let now = ExerciseRecords(sets: sets.filter { $0.exerciseID == exerciseID }, type: type).records
            // A first time beats nothing.
            return now.compactMap { record in
                guard let old = before.first(where: { $0.kind == record.kind }), record.kind.isBetter(record.value, than: old.value) else { return nil }
                return BeatenRecord(exerciseID: exerciseID, kind: record.kind, value: record.value, before: old.value)
            }
        }
    }
}

extension ModelContext {
    public func summary(of session: Session) throws -> SessionSummary {
        let sets = try sets(of: session.id)
        let ids = Array(Set(sets.map(\.exerciseID)))
        let sessionID = session.id
        let started = session.startedAt
        let before = Set(try fetch(FetchDescriptor(predicate: #Predicate<Session> {
            !$0.removed && $0.endedAt != nil && $0.id != sessionID && $0.startedAt < started
        })).map(\.id))
        let earlier = try fetch(FetchDescriptor(predicate: #Predicate<SetLog> { !$0.removed && ids.contains($0.exerciseID) }))
            .filter { before.contains($0.sessionID) }
        let exercises = try fetch(FetchDescriptor(predicate: Exercise.withIDs(ids)))
        return SessionSummary(session: session, sets: sets, earlier: earlier, exercises: exercises)
    }
}
