import Foundation
import SwiftData

// What Health measured during a session, from its saved workout: absent when nothing measured it.
public struct HealthResult: Codable, Equatable, Sendable {
    public let sessionID: String
    public let activeKilocalories: Double?
    public let averageHeartRate: Double?
    public let maximumHeartRate: Double?

    public init(sessionID: String, activeKilocalories: Double?, averageHeartRate: Double?, maximumHeartRate: Double?) {
        self.sessionID = sessionID
        self.activeKilocalories = activeKilocalories
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
    }

    // With the other part of the session, when it was handed over from one device's workout to the other's: the
    // calories add up; the average is the one of the part that has one, `other` first.
    public func adding(_ other: HealthResult) -> HealthResult {
        HealthResult(
            sessionID: sessionID,
            activeKilocalories: Self.combine(activeKilocalories, other.activeKilocalories, +),
            averageHeartRate: other.averageHeartRate ?? averageHeartRate,
            maximumHeartRate: Self.combine(maximumHeartRate, other.maximumHeartRate, max)
        )
    }

    private static func combine(_ a: Double?, _ b: Double?, _ both: (Double, Double) -> Double) -> Double? {
        guard let a, let b else { return a ?? b }
        return both(a, b)
    }
}

// The session in progress as a device holds it, for the other one: everything each time, so that a message lost is made
// up for by the next. Applied any number of times, in any order: its rows like rows from the server, its state if
// more recent.
public struct LiveSnapshot: Codable, Equatable, Sendable {
    // Nil once the session is over.
    public var state: LiveState?
    public var session: SessionRow
    public var sets: [SetLogRow]
    // The workout of Health of the session runs on the sender.
    public var recordsHealth: Bool

    public init(state: LiveState?, session: SessionRow, sets: [SetLogRow], recordsHealth: Bool) {
        self.state = state
        self.session = session
        self.sets = sets
        self.recordsHealth = recordsHealth
    }

    // Nothing in it is new for a device holding `other`: a rest over on its own is no news, each device sees it itself.
    public func says(sameAs other: LiveSnapshot) -> Bool {
        (state == nil) == (other.state == nil) && state?.changedAt == other.state?.changedAt && session == other.session && sets == other.sets
    }
}

// What goes from one device of a session to the other, by the workout of Health or by WatchConnectivity.
public enum LiveMessage: Codable, Equatable, Sendable {
    case snapshot(LiveSnapshot)
    // What the device doing the workout measures.
    case measures(heartRate: Double?, kilocalories: Double?)
    // The workout saved in Health.
    case saved(HealthResult)

    // Compressed: a long session stays well below what a message can hold.
    public func encoded() throws -> Data {
        try (JSONEncoder().encode(self) as NSData).compressed(using: .lzfse) as Data
    }

    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(LiveMessage.self, from: (data as NSData).decompressed(using: .lzfse) as Data)
    }
}

// What a snapshot received comes to.
public enum LiveOutcome {
    // The session goes on, in this state.
    case going(LiveState)
    // It was saved or discarded.
    case over(Session)
    // Nothing to do here: another session is going on on this device, or this one left nothing to hold.
    case unrelated
}

extension ModelContext {
    // The session as this device holds it; nil if it does not know it.
    public func liveSnapshot(of sessionID: String, state: LiveState?, recordsHealth: Bool) throws -> LiveSnapshot? {
        guard let session = try fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == sessionID })).first else { return nil }
        let sets = try fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.sessionID == sessionID }, sortBy: [SortDescriptor(\.id)]))
        return LiveSnapshot(state: session.isOver ? nil : state, session: session.row, sets: sets.map(\.row), recordsHealth: recordsHealth)
    }

    // Takes what the other device holds, `held` being the state of the session on this one.
    public func apply(_ snapshot: LiveSnapshot, held: LiveState?) throws -> LiveOutcome {
        let id = snapshot.session.id
        if let held, held.sessionID != id {
            return .unrelated
        }
        try apply([snapshot.session], to: Session.self)
        try apply(snapshot.sets, to: SetLog.self)
        try removeSetsDoneTwice(in: id)
        if hasChanges {
            try save()
        }
        guard let session = try fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })).first else { return .unrelated }
        if session.isOver {
            return .over(session)
        }
        guard var state = Self.moreRecent(snapshot.state, held) else { return .unrelated }
        // The set to do was done meanwhile on this device.
        let done = doneKeys(try sets(of: id))
        let plan = state.livePlan
        if plan.steps.indices.contains(state.cursor), done.contains(plan.key(plan.steps[state.cursor])) {
            state.cursor = plan.firstOpen(done: done)
        }
        return .going(state)
    }

    private static func moreRecent(_ received: LiveState?, _ held: LiveState?) -> LiveState? {
        guard let received, let held else { return received ?? held }
        return (received.changedAt ?? .distantPast) > (held.changedAt ?? .distantPast) ? received : held
    }

    // The same set validated on both devices at once: one row kept, the same one on both, whichever applies this first.
    private func removeSetsDoneTwice(in sessionID: String) throws {
        var kept: [String: SetLog] = [:]
        for set in try sets(of: sessionID).sorted(by: { $0.id < $1.id }) {
            guard let itemID = set.workoutItemID else { continue }
            let key = LivePlan.key(itemID, set.setIndex)
            if let first = kept[key] {
                set.removed = true
                set.updatedAt = Date(epochMilliseconds: max(first.updatedAt.epochMilliseconds, set.updatedAt.epochMilliseconds) + 1)
            } else {
                kept[key] = set
            }
        }
    }
}

extension Session {
    // Saved or discarded.
    public var isOver: Bool {
        removed || endedAt != nil
    }

    // Ended a moment ago: the other device can still be told at once.
    public func justEnded(now: Date = .now) -> Bool {
        endedAt.map { now.timeIntervalSince($0) < 15 } == true
    }
}
