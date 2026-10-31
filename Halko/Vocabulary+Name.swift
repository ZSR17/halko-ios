import Foundation
import HalkoCore

// The words of the shared vocabulary, in the language of the app.

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

extension MuscleGroup {
    var name: LocalizedStringResource {
        switch self {
        case .legs: "Legs"
        case .chest: "Chest"
        case .back: "Back"
        case .core: "Core"
        case .arms: "Arms"
        case .shoulders: "Shoulders"
        }
    }
}

extension Equipment {
    var name: LocalizedStringResource {
        switch self {
        case .bodyOnly: "Body weight"
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbells"
        case .kettlebells: "Kettlebell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .bands: "Bands"
        case .medicineBall: "Medicine ball"
        case .exerciseBall: "Exercise ball"
        case .ezCurlBar: "EZ bar"
        case .foamRoll: "Foam roller"
        case .other: "Other"
        }
    }

    // The equipment of an exercise as stored: a value outside the known list (custom) as it is.
    static func name(of id: String) -> String {
        Equipment(rawValue: id).map { String(localized: $0.name) } ?? id
    }
}

extension ExerciseType {
    var name: LocalizedStringResource {
        switch self {
        case .weightReps: "Weight and reps"
        case .bodyweightReps: "Bodyweight reps"
        case .weightedBodyweight: "Weighted bodyweight"
        case .assistedBodyweight: "Assisted bodyweight"
        case .duration: "Duration"
        case .durationWeight: "Duration and weight"
        case .distanceDuration: "Distance and duration"
        case .weightDistance: "Weight and distance"
        }
    }
}

extension RecordKind {
    var name: LocalizedStringResource {
        switch self {
        case .maxWeight: "Max weight"
        case .oneRepMax: "Estimated 1RM"
        case .maxReps: "Max reps"
        case .maxAddedWeight: "Max added weight"
        case .minAssistance: "Min assistance"
        case .bestTime: "Best time"
        case .maxDistance: "Max distance"
        }
    }
}

extension Exercise {
    // The language the exercises of the library are read in: the app's, English or French.
    static var appLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    var localizedName: String {
        name(in: Self.appLanguage)
    }

    var localizedInstructions: [String] {
        instructions(in: Self.appLanguage)
    }
}
