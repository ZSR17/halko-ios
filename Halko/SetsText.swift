import Foundation
import HalkoCore

// How the pages of a workout and of an exercise write sets: "4 × 8 · 80 kg · rest 2:30".
struct SetsText {
    let weightUnit: WeightUnit
    let distanceUnit: DistanceUnit

    init(locale: Locale) {
        weightUnit = .preferred(for: locale)
        distanceUnit = .preferred(for: locale)
    }

    // The working sets: their number and values when alike, else the values of each.
    func working(_ sets: PlannedSets, type: ExerciseType, perSide: Bool, sidesPauseS: Int?) -> String {
        var parts: [String] = []
        if sets.alike, let set = sets.working.first {
            parts.append("\(sets.working.count) × \(sided(measure(set, type: type), perSide))")
            if let load = load(set, type: type, unit: true) {
                parts.append(load)
            }
            if type == .distanceDuration, let durationS = set.durationS {
                parts.append(duration(durationS))
            }
        } else {
            parts.append(sets.working.map { sided(values($0, type: type, unit: true), perSide) }.joined(separator: ", "))
        }
        if let sidesPauseS {
            parts.append(String(localized: "\(duration(Double(sidesPauseS))) pause to change sides"))
        }
        if let rest = sets.rest {
            parts.append(String(localized: "rest \(clock(rest))"))
        }
        return parts.joined(separator: " · ")
    }

    // The warm-ups, their weight without its unit (the working sets give it): "Auto warm-up: 20 × 10 · 50 × 3".
    func warmups(_ sets: PlannedSets, type: ExerciseType) -> String {
        var parts = sets.warmups.map { values($0, type: type, unit: false) }
        if let rest = sets.warmups.first?.restS, rest > 0, sets.warmups.allSatisfy({ $0.restS == rest }) {
            parts.append(String(localized: "rest \(clock(rest))"))
        }
        let list = parts.joined(separator: " · ")
        return sets.workedOut ? String(localized: "Auto warm-up: \(list)") : String(localized: "Warm-up: \(list)")
    }

    // A record of the page of an exercise: "85 kg", "101.3 kg", "12 reps", "1:30".
    func record(_ record: ExerciseRecord) -> String {
        switch record.kind {
        case .maxWeight, .maxAddedWeight, .minAssistance: weight(Int(record.value))
        // An estimate: a tenth is enough.
        case .oneRepMax: weight(Int(record.value), digits: 0...1)
        case .maxReps: String(localized: "\(Int(record.value)) reps")
        case .bestTime: duration(record.value)
        case .maxDistance: distance(record.value)
        }
    }

    // A set done, its weight without its unit as on the page of a workout: "80 × 8".
    func set(_ set: SetTarget, type: ExerciseType) -> String {
        values(set, type: type, unit: false)
    }

    // What each set is counted in: reps, time or distance.
    private func measure(_ set: SetTarget, type: ExerciseType) -> String {
        switch type {
        case .weightReps, .bodyweightReps, .weightedBodyweight, .assistedBodyweight: set.reps.map { $0.formatted() } ?? String(localized: "max")
        case .duration, .durationWeight: set.durationS.map(duration) ?? "–"
        case .distanceDuration, .weightDistance: set.distanceM.map(distance) ?? "–"
        }
    }

    // The weight lifted, added (+) or taken off by an assistance (−); the body weight alone.
    private func load(_ set: SetTarget, type: ExerciseType, unit: Bool) -> String? {
        let weight = set.weightG.map { unit ? self.weight($0) : number($0) }
        return switch type {
        case .weightReps, .durationWeight, .weightDistance: weight
        case .weightedBodyweight: weight.map { "+\($0)" }
        case .assistedBodyweight: weight.map { "−\($0)" }
        case .bodyweightReps: unit ? String(localized: "bodyweight") : nil
        case .duration, .distanceDuration: nil
        }
    }

    // One set: "80 kg × 8", "12 reps", "40 s".
    private func values(_ set: SetTarget, type: ExerciseType, unit: Bool) -> String {
        let measure = measure(set, type: type)
        if type == .bodyweightReps {
            return set.reps.map { String(localized: "\($0) reps") } ?? measure
        }
        if type == .distanceDuration {
            return [measure, set.durationS.map(duration)].compactMap { $0 }.joined(separator: " / ")
        }
        guard let load = load(set, type: type, unit: unit) else { return measure }
        return "\(load) × \(measure)"
    }

    private func sided(_ text: String, _ perSide: Bool) -> String {
        perSide ? String(localized: "\(text) per side") : text
    }

    private func weight(_ grams: Int, digits: ClosedRange<Int> = 0...2) -> String {
        Measurement(value: Double(grams) / weightUnit.grams, unit: weightUnit == .kg ? UnitMass.kilograms : .pounds)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(digits))))
    }

    private func number(_ grams: Int) -> String {
        (Double(grams) / weightUnit.grams).formatted(.number.precision(.fractionLength(0...2)))
    }

    // "40 s" under a minute, "1:30" above. The symbol in every language: "40 secs" is the abbreviated English.
    private func duration(_ seconds: Double) -> String {
        guard seconds < 60 else { return clock(Int(seconds.rounded())) }
        return "\(seconds.formatted(.number.precision(.fractionLength(0...1)))) \(UnitDuration.seconds.symbol)"
    }

    private func clock(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    // Short distances (carries, sled) in metres, or yards.
    private func distance(_ metres: Double) -> String {
        let length = Measurement(value: metres, unit: UnitLength.meters)
        let shown = switch distanceUnit {
        case .km: metres < 1000 ? length : length.converted(to: .kilometers)
        case .mi: length.value < 1609.344 ? length.converted(to: .yards) : length.converted(to: .miles)
        }
        let digits = shown.unit == .meters || shown.unit == .yards ? 0...0 : 0...2
        return shown.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(digits))))
    }
}
