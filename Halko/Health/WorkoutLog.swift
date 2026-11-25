import Foundation
import WatchConnectivity

// What happened to the workout of Health of a session, on each device: the iPhone asking the watch for it, the watch
// starting it, giving it to the iPhone, and what the system said. Read on the iPhone, its last lines, for the user to
// pass on when the watch did not record a session; the watch sends its own lines there. Nothing else leaves the devices.
@MainActor
enum WorkoutLog {
    nonisolated static let key = "workoutLog"

    static func add(_ line: String) {
        let time = Date.now.formatted(.dateTime.day().month(.twoDigits).hour().minute().second())
        #if os(watchOS)
        pending.append("\(time) watch: \(line)")
        send()
        #else
        keep(["\(time) iPhone: \(line)"])
        #endif
    }

    #if os(watchOS)
    // Kept until WatchConnectivity takes them: it is not ready yet when the app is woken for a workout.
    private static var pending: [String] = []

    // Again once the link with the iPhone is ready.
    static func send() {
        guard !pending.isEmpty, WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isCompanionAppInstalled else { return }
        WCSession.default.transferUserInfo([key: pending])
        pending = []
    }
    #else
    private static let kept = 300

    // The watch's lines, in the order they were written there.
    static func received(_ lines: [String]) {
        keep(lines)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func keep(_ new: [String]) {
        let defaults = UserDefaults.standard
        let lines = (defaults.string(forKey: key) ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init) + new
        defaults.set(lines.suffix(kept).joined(separator: "\n"), forKey: key)
    }
    #endif
}
