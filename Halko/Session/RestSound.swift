import AVFAudio
import Foundation
import os

// The end of a rest, heard over what is playing (music, podcast), without stopping or lowering it: at the media
// volume (nothing at 0 %), whether the iPhone is in silent mode or not, in headphones when there are some.
//
// Its audio is made ready when the session starts, with the app on screen, and kept until the session ends. The sound
// is handed to the audio output when the rest starts, to be played at its end: in the background, the app then never
// has to start any audio itself (`audio` background mode, while a workout of Health keeps the app running). Mixed
// with others, holding it changes nothing for what is playing.
@MainActor
final class RestSound {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")
    private static let url = Bundle.main.url(forResource: "RestOver", withExtension: "wav")

    private var player: AVAudioPlayer?
    // The sound that has just started, kept while it plays: the next one is already waiting.
    private var ringing: AVAudioPlayer?
    // The end of the rest going on, when its sound is to be heard.
    private var end: Date?
    private var observers: [any NSObjectProtocol] = []

    // From the start of a session to its end.
    func hold(_ holds: Bool) {
        guard holds == observers.isEmpty else { return }
        guard holds else {
            player?.stop()
            player = nil
            end = nil
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        // A call stops the sound waiting to be played: it waits again once the call is over.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { notification in
            let ended = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
            guard ended else { return }
            MainActor.assumeIsolated {
                self.resume()
            }
        })
        // The audio of the whole system restarted: everything made before is gone.
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
            MainActor.assumeIsolated {
                self.player = nil
                self.prepare()
                self.resume()
            }
        })
        prepare()
    }

    // The rest that started (its end), or none.
    func schedule(at end: Date?) {
        guard end != self.end else { return }
        // Over on its own: its sound, just started, plays to its end.
        let over = self.end.map { $0 <= .now } ?? false
        self.end = end
        guard end != nil || !over else { return }
        if over, player?.isPlaying == true {
            ringing = player
            prepare()
        }
        resume()
    }

    private func prepare() {
        guard let url = Self.url else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            self.player = player
        } catch {
            Self.logger.error("Cannot make the end of the rest ready: \(String(describing: error))")
        }
    }

    private func resume() {
        guard let player else { return }
        player.stop()
        player.currentTime = 0
        guard let end else { return }
        let delay = end.timeIntervalSinceNow
        guard delay > 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.logger.error("Cannot wait for the end of the rest: \(String(describing: error))")
        }
        if !player.play(atTime: player.deviceCurrentTime + delay) {
            Self.logger.error("Cannot wait for the end of the rest")
        }
    }
}
