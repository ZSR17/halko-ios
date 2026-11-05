import Foundation
import SwiftData

// What the iPhone and the watch give each other of the sessions done: the rows changed since the last time, each
// direction with its own cursor. Only finished or deleted sessions, with all their sets: a session in progress stays on
// its device. A session finished on the watch comes with the workout items it changed, which take the values done.
// Applied like rows from the server: the most recent `updatedAt` wins, so a row arriving twice changes nothing.
public struct SessionChanges: Codable, Equatable, Sendable {
    public var sessions: [SessionRow]
    public var sets: [SetLogRow]
    public var items: [WorkoutItemRow]

    public init(sessions: [SessionRow], sets: [SetLogRow], items: [WorkoutItemRow]) {
        self.sessions = sessions
        self.sets = sets
        self.items = items
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(SessionChanges.self, from: data)
    }

    // The cursor once these rows are handed over: past the last of them, whose date is rounded to the millisecond here.
    public var cursor: Date {
        let dates = sessions.map(\.updatedAt) + sets.map(\.updatedAt) + items.map(\.updatedAt)
        return Date(epochMilliseconds: (dates.max() ?? 0) + 1)
    }
}

extension ModelContext {
    // What changed after `since`; nil when nothing is to be handed over. `items`: with the workout items changed.
    public func sessionChanges(since: Date, items withItems: Bool) throws -> SessionChanges? {
        let sessions = try fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.updatedAt > since }))
        let sets = try fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.updatedAt > since }))
        let touched = Array(Set(sessions.map(\.id) + sets.map(\.sessionID)))
        let shared = try fetch(FetchDescriptor(predicate: Session.withIDs(touched), sortBy: [SortDescriptor(\.id)]))
            .filter { $0.removed || $0.endedAt != nil }
        guard !shared.isEmpty else { return nil }
        let ids = shared.map(\.id)
        let sharedSets = try fetch(FetchDescriptor<SetLog>(predicate: #Predicate { ids.contains($0.sessionID) }, sortBy: [SortDescriptor(\.id)]))
        let items = withItems
            ? try fetch(FetchDescriptor<WorkoutItem>(predicate: #Predicate { $0.updatedAt > since }, sortBy: [SortDescriptor(\.id)]))
            : []
        return SessionChanges(sessions: shared.map(\.row), sets: sharedSets.map(\.row), items: items.map(\.row))
    }

    public func apply(_ changes: SessionChanges) throws {
        try apply(changes.sessions, to: Session.self)
        try apply(changes.sets, to: SetLog.self)
        try apply(changes.items, to: WorkoutItem.self)
        if hasChanges {
            try save()
        }
    }
}
