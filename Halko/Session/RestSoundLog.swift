import AVFAudio
import Foundation
import UIKit

// What happened to the sound of the end of a rest: made ready, waiting, played, and what the system did to it
// (interruptions, a change of headphones). Kept on the iPhone only, the last lines, for the user to read and pass on
// when the sound was not heard; nothing leaves the device by itself.
@MainActor
enum RestSoundLog {
    static let key = "restSoundLog"
    private static let kept = 300

    static func add(_ line: String) {
        let defaults = UserDefaults.standard
        let time = Date.now.formatted(.dateTime.day().month(.twoDigits).hour().minute().second())
        var lines = (defaults.string(forKey: key) ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        lines.append("\(time) [\(state)] \(line)")
        defaults.set(lines.suffix(kept).joined(separator: "\n"), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // The app on screen or not, and where the sound goes.
    private static var state: String {
        let app = switch UIApplication.shared.applicationState {
        case .active: "on screen"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+")
        return "\(app), \(outputs.isEmpty ? "no output" : outputs)\(session.isOtherAudioPlaying ? ", other audio" : "")"
    }
}
