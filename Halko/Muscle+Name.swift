import HalkoCore
import SwiftUI

extension Muscle {
    var name: LocalizedStringResource {
        switch self {
        case .abs: "Abs"
        case .abductors: "Abductors"
        case .adductors: "Adductors"
        case .biceps: "Biceps"
        case .calves: "Calves"
        case .chest: "Chest"
        case .forearms: "Forearms"
        case .glutes: "Glutes"
        case .hamstrings: "Hamstrings"
        case .lats: "Lats"
        case .lowerback: "Lower back"
        case .middleback: "Middle back"
        case .neck: "Neck"
        case .quads: "Quads"
        case .shoulders: "Shoulders"
        case .traps: "Traps"
        case .triceps: "Triceps"
        }
    }
}
