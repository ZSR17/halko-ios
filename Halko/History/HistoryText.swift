import Foundation
import HalkoCore

// How the History tab writes what it shows.
struct HistoryText {
    let sets: SetsText

    // The load of a session or a month: "6.8 t", "840 kg", "15,078 lb"; a dash without any.
    func tonnage(_ grams: Int) -> String {
        guard grams > 0 else { return "—" }
        guard sets.weightUnit == .kg, grams >= 1_000_000 else { return sets.volume(grams) }
        return Measurement(value: Double(grams) / 1_000_000, unit: UnitMass.metricTons)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    // "54 min", "1 h 02".
    func minutes(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        guard minutes >= 60 else { return String(localized: "\(minutes) min") }
        let rest = String(format: "%02d", minutes % 60)
        return String(localized: "\(minutes / 60) h \(rest)")
    }

    // "54 min · 17 sets · 6.8 t".
    func details(of session: HistorySession) -> String {
        var parts = [minutes(session.duration), String(localized: "\(session.setCount) sets")]
        if session.volumeG > 0 {
            parts.append(tonnage(session.volumeG))
        }
        return parts.joined(separator: " · ")
    }

    // A value of a measure, in stored units.
    func value(_ value: Double, of measure: ProgressMeasure) -> String {
        switch measure {
        case .sessionVolume, .bestSetVolume: sets.volume(Int(value))
        case .maxWeight: sets.record(ExerciseRecord(kind: .maxWeight, value: value))
        case .oneRepMax: sets.record(ExerciseRecord(kind: .oneRepMax, value: value))
        case .totalReps, .maxReps: sets.record(ExerciseRecord(kind: .maxReps, value: value))
        case .maxAddedWeight: sets.record(ExerciseRecord(kind: .maxAddedWeight, value: value))
        case .minAssistance: sets.record(ExerciseRecord(kind: .minAssistance, value: value))
        case .bestTime: sets.record(ExerciseRecord(kind: .bestTime, value: value))
        case .maxDistance: sets.record(ExerciseRecord(kind: .maxDistance, value: value))
        }
    }

    // A stored value as the chart plots it: in the units shown, so that the steps of its axis are round.
    func plotted(_ value: Double, of measure: ProgressMeasure) -> Double {
        switch measure {
        case .maxWeight, .sessionVolume, .bestSetVolume, .oneRepMax, .maxAddedWeight, .minAssistance: value / sets.weightUnit.grams
        case .maxDistance: value / FieldText.metres(sets.distanceUnit)
        case .totalReps, .maxReps, .bestTime: value
        }
    }

    // A value plotted, on the axis of the chart.
    func axis(_ value: Double, of measure: ProgressMeasure) -> String {
        measure == .bestTime ? FieldText.clock(Int(value)) : value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension ProgressMeasure {
    var name: LocalizedStringResource {
        switch self {
        case .maxWeight: "Max weight"
        case .sessionVolume: "Session volume"
        case .bestSetVolume: "Best set"
        case .totalReps: "Total reps"
        case .oneRepMax: "Estimated 1RM"
        case .maxReps: "Max reps"
        case .maxAddedWeight: "Max added weight"
        case .minAssistance: "Min assistance"
        case .bestTime: "Best time"
        case .maxDistance: "Max distance"
        }
    }
}

extension ProgressPeriod {
    var name: LocalizedStringResource {
        switch self {
        case .oneMonth: "1 month"
        case .threeMonths: "3 months"
        case .oneYear: "1 year"
        case .all: "All time"
        }
    }
}
