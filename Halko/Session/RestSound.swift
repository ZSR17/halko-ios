import AVFAudio
import Foundation
import os

// The end of a rest, heard over what is playing (music, podcast), without stopping or lowering it: at the media
// volume (nothing at 0 %), whether the iPhone is in silent mode or not, in headphones when there are some.
//
// Its audio is made ready when the session starts, with the app on screen, and kept until the session ends: iOS lets
// an app in the background play audio it already holds, not always start some (`audio` background mode, while a
// workout of Health keeps the app running). Mixed with others, holding it changes nothing for what is playing.
@MainActor
final class RestSound {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")
    private static let url = Bundle.main.url(forResource: "RestOver", withExtension: "wav")

    private var player: AVAudioPlayer?

    // From the start of a session to its end.
    func hold(_ holds: Bool) {
        guard holds != (player != nil) else { return }
        let session = AVAudioSession.sharedInstance()
        guard holds else {
            player = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        guard let url = Self.url else { return }
        do {
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            self.player = player
        } catch {
            Self.logger.error("Cannot make the end of the rest ready: \(String(describing: error))")
        }
    }

    func play() {
        guard let player else { return }
        do {
            // Again after an interruption (a call), which deactivates it.
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.logger.error("Cannot play the end of the rest: \(String(describing: error))")
        }
        player.currentTime = 0
        player.play()
    }
}
