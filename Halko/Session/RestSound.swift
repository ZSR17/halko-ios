import AVFAudio
import Foundation
import HalkoCore
import os

// The end of a rest, heard over what is playing (music, podcast), without stopping or lowering it: at the media
// volume (nothing at 0 %), whether the iPhone is in silent mode or not, in headphones when there are some. The beeps
// before it too.
//
// Its audio is made ready when the session starts, with the app on screen, and kept until the session ends. The sounds
// are handed to the audio output when the rest starts, to be played at their time (`audio` background mode). In the
// background, iOS lets an app start a sound only while its audio plays (seen on device: every rest started there was
// refused, error 561015905): a silent sound loops from the start of the session to its end, the user's choice of
// 2026-11-25. Mixed with others, it changes nothing for what is playing. What happens goes in `RestSoundLog`.
@MainActor
final class RestSound {
    // What is heard of a rest, or of the timer of a set: a sound at its end, the beeps before.
    struct Alarm: Equatable {
        let end: Date
        var ticks: [Date] = []
    }

    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")
    // As many beeps as a countdown has at most.
    private static let tickCount = 3

    private var tone: RestAlertSettings.Tone?
    private var volume: Float = 1
    private var player: AVAudioPlayer?
    private var silence: AVAudioPlayer?
    private var tickPlayers: [AVAudioPlayer] = []
    // The sound that has just started, kept while it plays: the next one is already waiting.
    private var ringing: AVAudioPlayer?
    private var alarm: Alarm?
    // iOS did not let the sound wait for the end of the rest: started in the background, with nothing playing, the app
    // may not start its audio (seen on device, error 561015905). Tried again with the app on screen.
    private(set) var refused = false
    private var observers: [any NSObjectProtocol] = []
    private let finished = Finished()

    // From the start of a session to its end, with the sound chosen.
    func hold(_ holds: Bool, tone: RestAlertSettings.Tone, volume: Double) {
        self.volume = Float(volume)
        if holds, !observers.isEmpty, tone != self.tone {
            self.tone = tone
            prepare()
            resume()
        }
        guard holds == observers.isEmpty else { return }
        guard holds else {
            RestSoundLog.add("Let go")
            player?.stop()
            tickPlayers.forEach { $0.stop() }
            silence?.stop()
            player = nil
            tickPlayers = []
            silence = nil
            alarm = nil
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                RestSoundLog.add("Cannot let go: \(Self.describe(error))")
            }
            return
        }
        RestSoundLog.add("Held, \(tone.fileName) at \(Int(volume * 100)) %")
        self.tone = tone
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        // A call stops the sounds waiting to be played: they wait again once the call is over.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { notification in
            let info = notification.userInfo ?? [:]
            let ended = (info[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
            let reason = (info[AVAudioSessionInterruptionReasonKey] as? UInt).map { " reason \($0)" } ?? ""
            let resumes = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map { " options \($0)" } ?? ""
            MainActor.assumeIsolated {
                RestSoundLog.add("Interruption \(ended ? "ended" : "began")\(reason)\(resumes)")
                if ended {
                    self.resume()
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map(String.init) ?? "?"
            MainActor.assumeIsolated {
                RestSoundLog.add("Output changed, reason \(reason)")
            }
        })
        // The audio of the whole system restarted: everything made before is gone.
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
            MainActor.assumeIsolated {
                RestSoundLog.add("Audio of the system restarted")
                self.prepare()
                self.resume()
            }
        })
        prepare()
    }

    // The rest that started, or none.
    func schedule(_ alarm: Alarm?) {
        guard alarm != self.alarm || refused else { return }
        let over = self.alarm.map { $0.end <= .now } ?? false
        self.alarm = alarm
        RestSoundLog.add(alarm.map { "Waits \(Int($0.end.timeIntervalSinceNow.rounded())) s, \($0.ticks.count) beeps" } ?? "Waits for nothing")
        // Over on its own: its sound, just started, plays to its end, even when something new waits already (the rest or
        // the pause that follows a timer stopped by itself) or comes a moment later.
        if over, let player, player.isPlaying {
            ringing = player
            self.player = makePlayer(tone?.fileName)
        }
        resume()
    }

    private func prepare() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            Self.logger.error("Cannot make the end of the rest ready: \(String(describing: error))")
            RestSoundLog.add("Cannot make the audio ready: \(Self.describe(error))")
        }
        player = makePlayer(tone?.fileName)
        tickPlayers = (0..<Self.tickCount).compactMap { _ in makePlayer("RestTick") }
        silence?.stop()
        silence = makePlayer("Silence")
        silence?.numberOfLoops = -1
        keepSilence()
    }

    // Played again after a call or a restart of the system's audio, which stop it.
    private func keepSilence() {
        guard let silence, !silence.isPlaying else { return }
        if !silence.play() {
            RestSoundLog.add("Refused to keep the silence")
        }
    }

    private func makePlayer(_ name: String?) -> AVAudioPlayer? {
        guard let name, let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = finished
            player.prepareToPlay()
            return player
        } catch {
            Self.logger.error("Cannot make the end of the rest ready: \(String(describing: error))")
            RestSoundLog.add("Cannot make \(name) ready: \(Self.describe(error))")
            return nil
        }
    }

    private func resume() {
        refused = false
        keepSilence()
        for player in tickPlayers + (player.map { [$0] } ?? []) {
            player.stop()
            player.currentTime = 0
        }
        guard let alarm, alarm.end > .now else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.logger.error("Cannot wait for the end of the rest: \(String(describing: error))")
            RestSoundLog.add("Cannot start the audio: \(Self.describe(error))")
            refused = true
        }
        var times = Array(zip(tickPlayers, alarm.ticks.filter { $0 > .now }))
        if let player {
            times.append((player, alarm.end))
        } else {
            RestSoundLog.add("No sound to play")
        }
        for (player, time) in times {
            player.volume = volume
            if !player.play(atTime: player.deviceCurrentTime + time.timeIntervalSinceNow) {
                Self.logger.error("Cannot wait for the end of the rest")
                RestSoundLog.add("Refused to wait for a sound")
                refused = true
            }
        }
    }

    private static func describe(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}

// Each sound played to its end, or stopped by the system: in the log.
private nonisolated final class Finished: NSObject, AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let name = player.url?.deletingPathExtension().lastPathComponent ?? "?"
        Task { @MainActor in
            RestSoundLog.add("Played \(name)\(flag ? "" : ", not to its end")")
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let code = error.map { error in
            let error = error as NSError
            return "\(error.domain) \(error.code)"
        } ?? "?"
        Task { @MainActor in
            RestSoundLog.add("Cannot read a sound: \(code)")
        }
    }
}

extension RestAlertSettings.Tone {
    // Its sound in the app.
    var fileName: String {
        switch self {
        case .halko: "RestOver"
        case .gong: "RestGong"
        case .whistle: "RestWhistle"
        case .beep: "RestBeep"
        }
    }
}
