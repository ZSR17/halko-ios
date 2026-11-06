import ActivityKit
import Foundation

// The session in progress on the lock screen and in the Dynamic Island (Live Activity), in the iPhone app which keeps
// it up to date and in the widgets which draw it. The texts are written by the app, in its language and units.
nonisolated struct SessionActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        // The exercise of the set to do, or of the one after the rest; nil once every set is done.
        var exercise: String?
        // "Set 3", "Warm-up".
        var set: String?
        // "80 kg × 8".
        var values: String?
        // While resting: its end, an absolute time like everywhere else, and its length.
        var restEndsAt: Date?
        var restTotalS: Int
        // Beats per minute, only while Health measures them.
        var heartRate: Int?
        // The timer of the set to do, while it runs.
        var timer: Timer?

        nonisolated struct Timer: Codable, Hashable {
            var startsAt: Date
            var targetEnd: Date?
            // Its wait is the pause between two sides.
            var isPause: Bool
            var waitTitle: String
            var holdTitle: String
            var overTitle: String
            var stopTitle: String
        }
    }

    let sessionID: String
    let startedAt: Date
}

extension SessionActivityAttributes {
    // Opens the session in progress in the app.
    static let sessionURL = URL(string: "halko://session")!
}
