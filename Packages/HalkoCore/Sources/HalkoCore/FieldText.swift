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
    public static func metres(_ unit: DistanceUnit) -> Double {
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

    // A value that changes under the eyes: a weight in kg keeps a decimal ("80,0"), so that its digits stay in place
    // between steps of 0.5 kg.
    public func steadyText(_ value: Double, of field: SetField) -> String {
        guard field == .weight, weightUnit == .kg else { return text(value, of: field) }
        return (value / weightUnit.grams).formatted(.number.precision(.fractionLength(1...2)).grouping(.never).locale(locale))
    }

    // `value` in a box typed into: a time held always with its minutes ("01:00"), as it is typed; the rest as `text`.
    public func boxText(_ value: Double?, of field: SetField) -> String {
        guard field == .duration, let value else { return text(value, of: field) }
        return Self.timerText(Int(value.rounded()))
    }

    // 75 -> "01:15", 3725 -> "1:02:05".
    public static func timerText(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? clock(s) : String(format: "%02d:%02d", s / 60, s % 60)
    }

    // A time as it is typed, like a timer keypad: the digits come in from the right ("1" -> "00:01", "12" -> "00:12",
    // "123" -> "01:23"), up to hours ("12345" -> "1:23:45"); a digit taken away goes out on the right. Empty without
    // any digit.
    public static func keypadText(_ text: String) -> String {
        let digits = String(text.filter(\.isASCIIDigit).drop(while: { $0 == "0" }).suffix(6))
        guard !digits.isEmpty || text.contains(where: \.isASCIIDigit) else { return "" }
        let padded = String(repeating: "0", count: max(0, 4 - digits.count)) + digits
        let seconds = padded.suffix(2)
        let minutes = padded.dropLast(2).suffix(2)
        let hours = padded.dropLast(4)
        return hours.isEmpty ? "\(minutes):\(seconds)" : "\(hours):\(minutes):\(seconds)"
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

    // What one step changes a value by, in stored units: the smallest plate sold, 0.5 kg or 1 lb; a rep, 5 s, a
    // hundredth of a km or mile.
    public func increment(of field: SetField) -> Double {
        switch field {
        case .weight: weightUnit == .kg ? 500 : weightUnit.grams
        case .reps: 1
        case .duration, .rest: 1
        case .distance: distanceUnit == .km ? 10 : 16.09344
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
