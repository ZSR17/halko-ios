import Foundation

// How the list of exercises is narrowed down: by muscle group or by muscles picked on the body, by the equipment
// at hand, then by a search of their names. Same rules as the exercises page of the website.

// The groups of the filter (`MUSCLE_GROUPS` of the server): an exercise is in a group when one of its primary
// muscles is.
public enum MuscleGroup: String, Sendable, CaseIterable {
    case legs, chest, back, core, arms, shoulders

    public var muscles: [Muscle] {
        switch self {
        case .legs: [.quads, .hamstrings, .glutes, .calves, .adductors, .abductors]
        case .chest: [.chest]
        case .back: [.lats, .middleback, .lowerback, .traps]
        case .core: [.abs]
        case .arms: [.biceps, .triceps, .forearms]
        case .shoulders: [.shoulders, .neck]
        }
    }
}

// Equipment as free-exercise-db names it, in the order of the filter (`EQUIPMENT_IDS` of the server).
public enum Equipment: String, Sendable, CaseIterable {
    case bodyOnly = "body only"
    case barbell, dumbbell, kettlebells, cable, machine, bands
    case medicineBall = "medicine ball"
    case exerciseBall = "exercise ball"
    case ezCurlBar = "e-z curl bar"
    case foamRoll = "foam roll"
    case other
}

// Muscles picked on the body, to find exercises or to say what one works: a first tap on an area picks it as a
// primary muscle, a second as a secondary one, a third lets it go. An area may stand for several muscles (upper
// back: lats and middle back).
public struct MusclePick: Equatable, Sendable {
    public private(set) var primary: [Muscle] = []
    public private(set) var secondary: [Muscle] = []

    public init() {}

    // The muscles of an exercise; one among both stays primary.
    public init(primary: [Muscle], secondary: [Muscle]) {
        self.primary = primary
        self.secondary = secondary.filter { !primary.contains($0) }
    }

    public var isEmpty: Bool {
        primary.isEmpty && secondary.isEmpty
    }

    public func role(of area: [Muscle]) -> MuscleRole? {
        if area.contains(where: primary.contains) {
            return .primary
        }
        if area.contains(where: secondary.contains) {
            return .secondary
        }
        return nil
    }

    public mutating func cycle(_ area: [Muscle]) {
        let role = role(of: area)
        primary.removeAll(where: area.contains)
        secondary.removeAll(where: area.contains)
        switch role {
        case nil: primary += area
        case .primary: secondary += area
        case .secondary: break
        }
    }

    // Whether an exercise works the areas picked in the roles picked; it may work others too. An area among its
    // primary muscles is not one of its secondary ones.
    public func isWorked(primary exercisePrimary: [Muscle], secondary exerciseSecondary: [Muscle]) -> Bool {
        let areas = { (muscles: [Muscle]) in Set(muscles.map(BodyMap.area(of:))) }
        let worked = areas(exercisePrimary)
        let assisting = areas(exerciseSecondary).subtracting(worked)
        return areas(primary).isSubset(of: worked) && areas(secondary).isSubset(of: assisting)
    }
}

public struct ExerciseFilter: Equatable, Sendable {
    public var query = ""
    // Either a group or muscles picked on the body, never both; neither is every exercise.
    public private(set) var group: MuscleGroup?
    public private(set) var pick = MusclePick()
    // The equipment at hand: the exercises it is all there for, those needing none when `bodyOnly` is among it.
    public var equipment: Set<Equipment> = []

    public init() {}

    // Every exercise, whatever the muscles.
    public var isAllMuscles: Bool {
        group == nil && pick.isEmpty
    }

    public mutating func choose(_ group: MuscleGroup?) {
        self.group = group
        pick = MusclePick()
    }

    public mutating func cycle(_ area: [Muscle]) {
        group = nil
        pick.cycle(area)
    }

    public mutating func clearPick() {
        pick = MusclePick()
    }

    // The muscles and equipment chosen: what the search looks among.
    public func chooses(_ exercise: Exercise) -> Bool {
        if let group, !exercise.primaryMuscles.contains(where: group.muscles.contains) {
            return false
        }
        if !pick.isWorked(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles) {
            return false
        }
        guard !equipment.isEmpty else { return true }
        let needed = exercise.equipment.filter { $0 != Equipment.bodyOnly.rawValue }
        guard !needed.isEmpty else { return equipment.contains(.bodyOnly) }
        return needed.allSatisfy { Equipment(rawValue: $0).map(equipment.contains) ?? false }
    }

    // The words of the search as names are compared to them: a name is found when it holds them all, in any order.
    public var queryWords: [String] {
        Self.searchKey(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    // A name as the search compares it: case and accents left out ("Écarté" is found by "ecarte").
    public static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
