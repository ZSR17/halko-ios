import Foundation

// How the end of a rest is told, the same for every exercise. Chosen on the iPhone; the watch keeps a copy.
public struct RestAlertSettings: Equatable, Sendable {
    public enum Place: String, CaseIterable, Sendable {
        // The watch when its workout runs, so on the wrist; else the iPhone.
        case watch
        case iPhone
        case both
    }

    public enum Tone: String, CaseIterable, Sendable {
        case halko, gong, whistle, beep, chime
    }

    // The ones watchOS lets an app play.
    public enum WatchHaptic: String, CaseIterable, Sendable {
        case notification, strong, rising, light
    }

    public enum Countdown: String, CaseIterable, Sendable {
        case none
        // A beep each of the last three seconds.
        case threeTwoOne
        // One beep ten seconds before the end.
        case ten
    }

    public static let placeKey = "restAlert.place"
    public static let soundKey = "restAlert.sound"
    public static let toneKey = "restAlert.tone"
    public static let volumeKey = "restAlert.volume"
    public static let vibrationKey = "restAlert.vibration"
    public static let watchHapticKey = "restAlert.watchHaptic"
    public static let countdownKey = "restAlert.countdown"
    public static let keys = [placeKey, soundKey, toneKey, volumeKey, vibrationKey, watchHapticKey, countdownKey]

    public var place = Place.watch
    public var sound = true
    public var tone = Tone.halko
    // Of the media volume, from 0 to 1.
    public var volume = 1.0
    public var vibration = true
    public var watchHaptic = WatchHaptic.notification
    public var countdown = Countdown.threeTwoOne

    public init() {}

    public init(defaults: UserDefaults) {
        place = defaults.string(forKey: Self.placeKey).flatMap(Place.init(rawValue:)) ?? place
        sound = defaults.object(forKey: Self.soundKey) as? Bool ?? sound
        tone = defaults.string(forKey: Self.toneKey).flatMap(Tone.init(rawValue:)) ?? tone
        volume = defaults.object(forKey: Self.volumeKey) as? Double ?? volume
        vibration = defaults.object(forKey: Self.vibrationKey) as? Bool ?? vibration
        watchHaptic = defaults.string(forKey: Self.watchHapticKey).flatMap(WatchHaptic.init(rawValue:)) ?? watchHaptic
        countdown = defaults.string(forKey: Self.countdownKey).flatMap(Countdown.init(rawValue:)) ?? countdown
    }

    // The watch tells it when its workout runs (it is on the wrist), unless the iPhone alone was chosen.
    public func alertsOnWatch(watchRecords: Bool) -> Bool {
        watchRecords && place != .iPhone
    }

    // The iPhone tells it when the watch does not run the workout, or when it was chosen too.
    public func alertsOnPhone(watchRecords: Bool) -> Bool {
        !watchRecords || place != .watch
    }

    // The beeps or taps before the end of a rest, those still to come.
    public func countdown(before end: Date, now: Date = .now) -> [Date] {
        let seconds: [Double] = switch countdown {
        case .none: []
        case .threeTwoOne: [3, 2, 1]
        case .ten: [10]
        }
        return seconds.map { end - $0 }.filter { $0 > now }
    }
}
