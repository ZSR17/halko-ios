import Foundation

// Units weights and distances are shown and typed in, chosen apart from the language. Whatever they are, weights
// are stored in grams and distances in metres.

public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case kg, lb

    // Grams in one unit.
    public var grams: Double {
        switch self {
        case .kg: 1000
        case .lb: 453.59237
        }
    }

    // Pounds where the region weighs in them, kilograms elsewhere.
    public static func preferred(for locale: Locale) -> WeightUnit {
        locale.measurementSystem == .us ? .lb : .kg
    }

    // `grams` rounded to `step` of this unit (2.5 kg, 5 lb…).
    public func rounded(_ grams: Double, step: Double) -> Int {
        Int(((grams / self.grams / step).rounded() * step * self.grams).rounded())
    }

    // A default load that reads well in this unit: 20 kg stays 20 kg, but becomes 45 lb rather than 44.09.
    public func nice(_ grams: Int) -> Int {
        switch self {
        case .kg: grams
        case .lb: rounded(Double(grams), step: 5)
        }
    }

    // An empty barbell, until the plates tool lets one choose it.
    public var barG: Int {
        nice(20_000)
    }
}

public enum DistanceUnit: String, Codable, Sendable, CaseIterable {
    case km, mi

    public static func preferred(for locale: Locale) -> DistanceUnit {
        locale.measurementSystem == .metric ? .km : .mi
    }
}
