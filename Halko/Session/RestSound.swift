import AVFAudio
import Foundation
import os

// The end of a rest, heard over what is playing (music, podcast), without stopping or lowering it: at the media
// volume (nothing at 0 %), whether the iPhone is in silent mode or not, in headphones when there are some. Played in
// the background too, while a workout of Health keeps the app running (the `audio` background mode).
@MainActor
final class RestSound {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")
    private static let url = Bundle.main.url(forResource: "RestOver", withExtension: "wav")

    private var playing: (player: AVAudioPlayer, done: Task<Void, Never>)?

    func play() {
        guard let url = Self.url else { return }
        playing?.done.cancel()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            // Given back once played.
            let done = Task { [weak self] in
                try? await Task.sleep(for: .seconds(player.duration + 0.2))
                guard !Task.isCancelled else { return }
                self?.playing = nil
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            playing = (player, done)
        } catch {
            Self.logger.error("Cannot play the end of the rest: \(String(describing: error))")
        }
    }
}
