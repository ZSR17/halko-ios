import Foundation
import SwiftData

// What the History tab shows of the sessions finished: this week's figures, the sessions by month, and for the
// exercises done, what each session reached. Same as the website (`client/src/pages/History.tsx`,
// `client/src/lib/progress.ts`). From the local history: the same without a server.

public struct HistoryWeek: Equatable, Sendable {
    public let sessionCount: Int
    public let volumeG: Int
    public let duration: TimeInterval
}

public struct HistorySession: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let startedAt: Date
    public let duration: TimeInterval
    // Warm-ups left out.
    public let setCount: Int
    public let volumeG: Int
    // A record beaten against the sessions before it.
    public let beatRecord: Bool
}

public struct HistoryMonth: Identifiable, Equatable, Sendable {
    public let id: String
    // The latest first.
    public let sessions: [HistorySession]

    public var date: Date {
        sessions[0].startedAt
    }

    public var volumeG: Int {
        sessions.reduce(0) { $0 + $1.volumeG }
    }
}

// What can be followed of an exercise: the measures that count for its type, the main one first.
public enum ProgressMeasure: String, Sendable, CaseIterable {
    case maxWeight, sessionVolume, bestSetVolume, totalReps, oneRepMax, maxReps, maxAddedWeight, minAssistance, bestTime, maxDistance

    public static func measures(for type: ExerciseType) -> [ProgressMeasure] {
        switch type {
        case .weightReps: [.maxWeight, .sessionVolume, .bestSetVolume, .totalReps, .oneRepMax]
        case .bodyweightReps: [.maxReps]
        case .weightedBodyweight: [.maxAddedWeight]
        case .assistedBodyweight: [.minAssistance]
        case .duration: [.bestTime]
        case .durationWeight, .weightDistance: [.maxWeight]
        case .distanceDuration: [.maxDistance]
        }
    }

    // An estimate is not a weight actually lifted.
    public var isRecord: Bool {
        self != .oneRepMax
    }

    // Less assistance is better.
    var lowerIsBetter: Bool {
        self == .minAssistance
    }

    // What the sets of a session reach, in stored units (grams, reps, seconds, metres); nil without a value.
    func value(of sets: [SetLog], type: ExerciseType) -> Double? {
        let working = sets.filter { $0.kind != .warmup }
        let volumes = working.map { setVolumeG(type: type, values: SetValues($0), unilateral: $0.unilateral == true) }
        let value: Double? = switch self {
        case .maxWeight, .maxAddedWeight: working.compactMap(\.weightG).filter { $0 > 0 }.max().map(Double.init)
        case .minAssistance: working.compactMap(\.weightG).filter { $0 > 0 }.min().map(Double.init)
        case .sessionVolume: Double(volumes.reduce(0, +))
        case .bestSetVolume: volumes.max().map(Double.init)
        case .totalReps: Double(working.compactMap(\.reps).reduce(0, +))
        case .oneRepMax: working.compactMap { RecordKind.oneRepMax.value(of: $0) }.max()
        case .maxReps: working.compactMap(\.reps).max().map(Double.init)
        case .bestTime: working.compactMap(\.durationS).max()
        case .maxDistance: working.compactMap(\.distanceM).max()
        }
        return value.flatMap { $0 > 0 ? $0 : nil }
    }
}

// How far back the chart of an exercise goes.
public enum ProgressPeriod: String, Sendable, CaseIterable {
    case oneMonth, threeMonths, oneYear, all

    var months: Int? {
        switch self {
        case .oneMonth: 1
        case .threeMonths: 3
        case .oneYear: 12
        case .all: nil
        }
    }
}

public struct ProgressPoint: Identifiable, Equatable, Sendable {
    // Of the session.
    public let id: String
    public let date: Date
    // In stored units: grams, reps, seconds, metres.
    public let value: Double
}

// What each session reached of a measure of an exercise, the oldest first.
public struct ExerciseProgress: Equatable, Sendable {
    public let measure: ProgressMeasure
    public let points: [ProgressPoint]

    // The first session to reach it, on a tie.
    public var best: ProgressPoint? {
        guard var best = points.first else { return nil }
        for point in points.dropFirst() where measure.lowerIsBetter ? point.value < best.value : point.value > best.value {
            best = point
        }
        return best
    }

    public func points(in period: ProgressPeriod, now: Date, calendar: Calendar) -> [ProgressPoint] {
        guard let months = period.months, let start = calendar.date(byAdding: .month, value: -months, to: now) else { return points }
        return points.filter { $0.date >= start }
    }
}

public struct SessionHistory {
    private struct DoneSession {
        let sessionID: String
        let date: Date
        let sets: [SetLog]
    }

    public let week: HistoryWeek
    // The latest first.
    public let months: [HistoryMonth]
    // Those done, the last one done first.
    public let exercises: [Exercise]
    private let done: [String: [DoneSession]]

    // `sessions`: those finished; `sets`: theirs; `exercises`: those of the sets.
    public init(sessions: [Session], sets: [SetLog], exercises: [Exercise], now: Date, calendar: Calendar) {
        let types = Dictionary(exercises.map { ($0.id, $0.exerciseType) }, uniquingKeysWith: { first, _ in first })
        let bySession = Dictionary(grouping: sets, by: \.sessionID)
        // The oldest first: a record is beaten against the sessions before it.
        var bests: [String: [RecordKind: Double]] = [:]
        var done: [String: [DoneSession]] = [:]
        var rows: [HistorySession] = []
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let sessionSets = bySession[session.id] ?? []
            var beatRecord = false
            for (exerciseID, exerciseSets) in Dictionary(grouping: sessionSets, by: \.exerciseID) {
                done[exerciseID, default: []].append(DoneSession(sessionID: session.id, date: session.startedAt, sets: exerciseSets))
                for record in ExerciseRecords(sets: exerciseSets, type: types[exerciseID] ?? .weightReps).records where !record.kind.isEstimate {
                    guard let old = bests[exerciseID]?[record.kind] else {
                        // A first time beats nothing.
                        bests[exerciseID, default: [:]][record.kind] = record.value
                        continue
                    }
                    if record.kind.isBetter(record.value, than: old) {
                        beatRecord = true
                        bests[exerciseID, default: [:]][record.kind] = record.value
                    }
                }
            }
            rows.append(HistorySession(
                id: session.id,
                name: session.name,
                startedAt: session.startedAt,
                duration: (session.endedAt ?? session.startedAt).timeIntervalSince(session.startedAt),
                setCount: sessionSets.count(where: { $0.kind != .warmup }),
                volumeG: SessionSummary.volumeG(of: sessionSets, types: types),
                beatRecord: beatRecord
            ))
        }
        rows.reverse()

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let thisWeek = rows.filter { $0.startedAt >= weekStart }
        week = HistoryWeek(
            sessionCount: thisWeek.count,
            volumeG: thisWeek.reduce(0) { $0 + $1.volumeG },
            duration: thisWeek.reduce(0) { $0 + $1.duration }
        )

        var months: [HistoryMonth] = []
        var monthRows: [HistorySession] = []
        var monthID: String?
        for row in rows {
            let parts = calendar.dateComponents([.year, .month], from: row.startedAt)
            let id = "\(parts.year ?? 0)-\(parts.month ?? 0)"
            if id != monthID {
                if let monthID {
                    months.append(HistoryMonth(id: monthID, sessions: monthRows))
                }
                monthID = id
                monthRows = []
            }
            monthRows.append(row)
        }
        if let monthID {
            months.append(HistoryMonth(id: monthID, sessions: monthRows))
        }
        self.months = months

        let lastDone = Dictionary(sets.map { ($0.exerciseID, $0.completedAt) }, uniquingKeysWith: { max($0, $1) })
        self.exercises = exercises
            .filter { lastDone[$0.id] != nil }
            .sorted { lastDone[$0.id] ?? .distantPast > lastDone[$1.id] ?? .distantPast }
        self.done = done
    }

    public var isEmpty: Bool {
        months.isEmpty
    }

    public func progress(of exercise: Exercise, measure: ProgressMeasure) -> ExerciseProgress {
        let points = (done[exercise.id] ?? []).compactMap { session in
            measure.value(of: session.sets, type: exercise.exerciseType).map {
                ProgressPoint(id: session.sessionID, date: session.date, value: $0)
            }
        }
        return ExerciseProgress(measure: measure, points: points)
    }
}

// A set of a past session, as it is listed.
public struct PastSet: Identifiable, Equatable, Sendable {
    public let id: String
    public let isWarmup: Bool
    // Among the warm-ups, or among the working sets.
    public let number: Int
    public let values: SetValues
}

// An exercise of a past session, with its sets in the order they were done.
public struct PastExercise: Identifiable, Equatable, Sendable {
    public let id: String
    public let exerciseID: String
    public let perSide: Bool
    public let sets: [PastSet]

    // The sets of a session, by exercise, in the order of the session.
    public static func exercises(of sets: [SetLog]) -> [PastExercise] {
        let ordered = sets.sorted { ($0.position, $0.setIndex) < ($1.position, $1.setIndex) }
        var runs: [[SetLog]] = []
        for set in ordered {
            if let last = runs.last?.last, last.position == set.position, last.exerciseID == set.exerciseID {
                runs[runs.count - 1].append(set)
            } else {
                runs.append([set])
            }
        }
        return runs.map { run in
            var warmups = 0
            var working = 0
            let shown = run.map { set -> PastSet in
                if set.kind == .warmup {
                    warmups += 1
                    return PastSet(id: set.id, isWarmup: true, number: warmups, values: SetValues(set))
                }
                working += 1
                return PastSet(id: set.id, isWarmup: false, number: working, values: SetValues(set))
            }
            return PastExercise(id: run[0].id, exerciseID: run[0].exerciseID, perSide: run.contains { $0.unilateral == true }, sets: shown)
        }
    }
}

extension ModelContext {
    public func sessionHistory(now: Date = .now, calendar: Calendar = .current) throws -> SessionHistory {
        let sessions = try fetch(FetchDescriptor(predicate: #Predicate<Session> { !$0.removed && $0.endedAt != nil }))
        let finished = Set(sessions.map(\.id))
        let sets = try fetch(FetchDescriptor(predicate: #Predicate<SetLog> { !$0.removed })).filter { finished.contains($0.sessionID) }
        let ids = Array(Set(sets.map(\.exerciseID)))
        let exercises = try fetch(FetchDescriptor(predicate: Exercise.withIDs(ids)))
        return SessionHistory(sessions: sessions, sets: sets, exercises: exercises, now: now, calendar: calendar)
    }
}
