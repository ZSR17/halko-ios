import Foundation

// How the boxes of the workout editor show a value and read what is typed in them: weights and distances in the
// units chosen, times as on a timer ("1:30"). Same as the website (`client/src/lib/format.ts`).
public struct FieldText: Sendable {
    public let weightUnit: WeightUnit
    public let distanceUnit: DistanceUnit
    public let locale: Locale

    public init(weightUnit: WeightUnit, distanceUnit: DistanceUnit, locale: Locale) {
        self.weightUnit = weightUnit
        self.distanceUnit = distanceUnit
        self.locale = locale
    }

    // Metres in one distance unit.
    static func metres(_ unit: DistanceUnit) -> Double {
        switch unit {
        case .km: 1000
        case .mi: 1609.344
        }
    }

    // `value` in stored units (reps, grams, seconds, metres); empty without one.
    public func text(_ value: Double?, of field: SetField) -> String {
        guard let value else { return "" }
        return switch field {
        case .reps: Int(value.rounded()).formatted(.number.grouping(.never).locale(locale))
        case .weight: decimal(value / weightUnit.grams)
        case .distance: decimal(value / Self.metres(distanceUnit))
        case .duration, .rest: Self.clock(Int(value.rounded()))
        }
    }

    // What is typed, in stored units; nil when it is not a value of the field.
    public func value(_ text: String, of field: SetField) -> Double? {
        switch field {
        case .reps: Self.count(text).map(Double.init)
        case .weight: decimal(text).map { ($0 * weightUnit.grams).rounded() }
        case .distance: decimal(text).map { ($0 * Self.metres(distanceUnit)).rounded() }
        case .duration, .rest: Self.seconds(text).map(Double.init)
        }
    }

    // 75 -> "1:15", 3725 -> "1:02:05".
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let minutes = (s % 3600) / 60
        let rest = String(format: "%02d", s % 60)
        return s >= 3600 ? "\(s / 3600):\(String(format: "%02d", minutes)):\(rest)" : "\(minutes):\(rest)"
    }

    // "1:30" or, typed like a timer keypad without the colon: up to 2 digits are seconds ("25", "90"), beyond that
    // the last two digits are the seconds ("130" = 1:30, "1000" = 10:00, "13000" = 1:30:00).
    public static func seconds(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts: [Substring]
        if (3...6).contains(trimmed.count), trimmed.allSatisfy(\.isASCIIDigit) {
            let padded = String(repeating: "0", count: 6 - trimmed.count) + trimmed
            parts = stride(from: 0, to: 6, by: 2).map { padded.dropFirst($0).prefix(2) }
        } else {
            parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        }
        guard parts.count <= 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        return parts.reduce(0) { $0 * 60 + Int($1)! }
    }

    public static func count(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 6, trimmed.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(trimmed)
    }

    // Up to two decimals, with the separator of the language ("82,5").
    private func decimal(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }

    // A comma or a point as the separator, whatever the language; never below zero.
    private func decimal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCIIDigit || $0 == "." }), let number = Double(trimmed) else { return nil }
        return number
    }
}

extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
