import Foundation
import SwiftData

// Wire format of the sync (`shared/src/sync.ts` on the server), also used between the watch and the iPhone:
// each table's rows in JSON, with dates in UTC milliseconds. Conflicts are resolved per row: the most recent
// `updatedAt` wins.
public protocol SyncRow: Codable, Equatable, Sendable {
    var id: String { get }
    var updatedAt: Int { get }
}

// A stored model and its row. Every row has an id made on the device that created it, so a row arriving twice
// (from the server and from the other device) is stored once.
public protocol SyncedModel: PersistentModel {
    associatedtype Row: SyncRow

    var id: String { get }
    var updatedAt: Date { get }
    var row: Row { get }

    init(_ row: Row)
    func update(from row: Row)
    // A predicate on a concrete type: SwiftData cannot read a key path through a protocol.
    static func withIDs(_ ids: [String]) -> Predicate<Self>
}

extension ModelContext {
    // Stores received rows: each one replaces the local copy only if it is more recent. Nothing local is removed:
    // a deletion arrives as a row marked `deleted`.
    public func apply<Model: SyncedModel>(_ rows: [Model.Row], to _: Model.Type) throws {
        let stored = try fetch(FetchDescriptor(predicate: Model.withIDs(rows.map(\.id))))
        var byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for row in rows {
            if let model = byID[row.id] {
                if row.updatedAt > model.updatedAt.epochMilliseconds {
                    model.update(from: row)
                }
            } else {
                let model = Model(row)
                insert(model)
                byID[row.id] = model
            }
        }
    }
}

// A new row id: a lowercase UUID v4, like the web app's.
public func newRowID() -> String {
    UUID().uuidString.lowercased()
}

extension Date {
    public init(epochMilliseconds: Int) {
        self.init(timeIntervalSince1970: Double(epochMilliseconds) / 1000)
    }

    public var epochMilliseconds: Int {
        Int((timeIntervalSince1970 * 1000).rounded())
    }
}

// A field the server always expects, `null` when empty (an absent Optional would be left out of the JSON).
@propertyWrapper
public struct Nullable<Value: Codable & Sendable>: Codable, Sendable {
    public var wrappedValue: Value?

    public init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? nil : try container.decode(Value.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

extension Nullable: Equatable where Value: Equatable {}
