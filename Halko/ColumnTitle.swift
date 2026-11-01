import Foundation
import HalkoCore

extension FieldText {
    // The title of a column of sets: "kg", "Reps", "Time/side", "Rest"… `long`: as VoiceOver reads it, the units in
    // words.
    func columnTitle(_ field: SetField, type: ExerciseType, perSide: Bool, long: Bool) -> String {
        let side = { (text: String) in perSide ? String(localized: "\(text)/side") : text }
        switch field {
        case .weight:
            let unit = long
                ? (weightUnit == .kg ? String(localized: "kilograms") : String(localized: "pounds"))
                : (weightUnit == .kg ? UnitMass.kilograms : UnitMass.pounds).symbol
            return switch type {
            case .weightedBodyweight: long ? String(localized: "\(unit) added") : "+\(unit)"
            case .assistedBodyweight: long ? String(localized: "\(unit) of assistance") : "−\(unit)"
            default: unit
            }
        case .reps:
            return side(String(localized: "Reps"))
        case .duration:
            return side(String(localized: "Time"))
        case .distance:
            let unit = distanceUnit == .km ? UnitLength.kilometers : UnitLength.miles
            return side(long ? (distanceUnit == .km ? String(localized: "kilometres") : String(localized: "miles")) : unit.symbol)
        case .rest:
            return String(localized: "Rest")
        }
    }
}
