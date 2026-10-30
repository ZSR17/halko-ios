// Warm-ups follow the working sets: a warm-up without weight (or reps) has it worked out from the first working
// set; one typed in is kept. Ramp from the empty bar (barbell exercises) or 40 %, in even steps up to 85 % of the
// working weight, reps going down (10 first, then 5 up to 60 %, 3 up to 75 %, 2 above): a last warm-up near
// 80-90 % helps the working sets, few reps keep it from tiring (Ribeiro et al. 2020 and 2021; Starting Strength,
// Barbell Medicine). Same as the website (`client/src/lib/targets.ts`).
public enum Warmups {
    public struct Step: Equatable, Sendable {
        public let weightG: Int
        public let reps: Int
    }

    // The types whose warm-ups have their weight worked out.
    static let weighted: Set<ExerciseType> = [.weightReps, .durationWeight, .weightDistance]

    // `count` warm-ups before `workingG`; `barG`: the empty bar of a barbell exercise.
    public static func plan(count: Int, workingG: Int, barG: Int?, unit: WeightUnit) -> [Step] {
        // To the smallest pair of plates on a bar, else to the dumbbell or machine step.
        let step: Double = switch (barG, unit) {
        case (.some, .kg): 2.5
        case (.some, .lb): 5
        case (nil, .kg): 1
        case (nil, .lb): 2.5
        }
        let working = Double(workingG)
        let top = 0.85 * working
        let bottom = barG.map(Double.init) ?? 0.4 * working
        let raw = count == 1
            ? [0.6 * working]
            : (0..<count).map { bottom + (top - bottom) * Double($0) / Double(count - 1) }
        return raw.enumerated().map { index, grams in
            let weightG = min(workingG, max(barG ?? 0, unit.rounded(grams, step: step)))
            return Step(weightG: weightG, reps: reps(index: index, count: count, weightG: weightG, workingG: workingG))
        }
    }

    // Reps of warm-up `index` of `count` with `weightG`: 10 for the first, then fewer as it gets heavier.
    static func reps(index: Int, count: Int, weightG: Int, workingG: Int) -> Int {
        let share = Double(weightG) / Double(workingG)
        return if index == 0 && count > 1 { 10 } else if share <= 0.6 { 5 } else if share <= 0.75 { 3 } else { 2 }
    }

    // `targets` with the warm-up values left to work out filled in from the first working set.
    public static func filledIn(_ targets: [SetTarget], type: ExerciseType, equipment: [String], unit: WeightUnit) -> [SetTarget] {
        let count = targets.count(where: { $0.kind == .warmup })
        guard count > 0, weighted.contains(type),
              let workingG = targets.first(where: { $0.kind != .warmup })?.weightG, workingG > 0 else {
            return targets
        }
        let steps = plan(count: count, workingG: workingG, barG: equipment.contains("barbell") ? unit.barG : nil, unit: unit)
        var index = 0
        return targets.map { target in
            guard target.kind == .warmup else { return target }
            defer { index += 1 }
            var filled = target
            let weightG = target.weightG ?? steps[index].weightG
            filled.weightG = weightG
            // Reps go with the weight lifted, typed in or not.
            if type == .weightReps {
                filled.reps = target.reps ?? reps(index: index, count: count, weightG: weightG, workingG: workingG)
            }
            return filled
        }
    }
}
