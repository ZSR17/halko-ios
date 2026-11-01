import Foundation
import Observation
import os

// The live state of the session being done on this device, kept in a file so that it comes back after the app is
// stopped; without a file (the interface tests' sample data), in memory only.
@MainActor
@Observable
public final class LiveSessionStore {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")

    public private(set) var state: LiveState?
    // Shown in full screen; hidden, the session goes on.
    public var isPresented = false
    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            state = try JSONDecoder().decode(LiveState.self, from: data)
        } catch {
            Self.logger.error("Cannot read the session in progress: \(String(describing: error))")
        }
    }

    // In Application Support, beside the database.
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "live-session.json")
    }

    public func set(_ state: LiveState?) {
        guard state != self.state else { return }
        self.state = state
        guard let fileURL else { return }
        do {
            if let state {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: fileURL.path()) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            Self.logger.error("Cannot keep the session in progress: \(String(describing: error))")
        }
    }

    // Changes the state, if there is one.
    public func change(_ body: (inout LiveState) throws -> Void) rethrows {
        guard var state else { return }
        try body(&state)
        set(state)
    }
}
