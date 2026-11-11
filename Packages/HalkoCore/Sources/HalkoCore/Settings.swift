import Foundation

// The language of the app, chosen in it rather than in the system's settings, so that the watch takes it too. The
// system reads it when the app starts: a new one shows at the next start.
public enum AppLanguage: String, CaseIterable, Sendable {
    // That of the device, when the app speaks it.
    case system
    case fr
    case en

    public static let key = "appLanguage"
    // Where the system looks for the languages of an app, before those of the device.
    static let systemKey = "AppleLanguages"

    public init(defaults: UserDefaults) {
        self = defaults.string(forKey: Self.key).flatMap(Self.init(rawValue:)) ?? .system
    }

    public func save(to defaults: UserDefaults) {
        if self == .system {
            defaults.removeObject(forKey: Self.key)
            defaults.removeObject(forKey: Self.systemKey)
        } else {
            defaults.set(rawValue, forKey: Self.key)
            defaults.set([rawValue], forKey: Self.systemKey)
        }
    }
}

// The settings chosen on the iPhone that the watch keeps a copy of: their keys in the defaults, with their values.
public enum SharedSettings {
    public static let keys = [
        AppLanguage.key,
        Units.weightKey,
        Units.distanceKey,
        SetTimerSettings.stopsAtTargetKey,
        SetTimerSettings.getsInPositionKey,
        SetTimerSettings.positionKey,
    ] + RestAlertSettings.keys

    // The values set; a key left out is at its default.
    public static func values(in defaults: UserDefaults) -> [String: Any] {
        var values: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        return values
    }

    // On the watch: the copy replaced, a key left out going back to its default. The language goes where the system
    // reads it.
    public static func save(_ values: [String: Any], to defaults: UserDefaults) {
        for key in keys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        AppLanguage(defaults: defaults).save(to: defaults)
    }
}
