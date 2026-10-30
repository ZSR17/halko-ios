import Foundation

// One-rep max estimates from a set of `reps` at `weight` (any unit). Most of them assume a set taken close to failure.
public enum OneRepMaxFormula: Sendable, CaseIterable {
    case brzycki, epley, mcglothin, lombardi, mayhew, oconner, wathen

    func estimate(_ weight: Double, reps: Double) -> Double {
        switch self {
        case .brzycki: weight * 36 / (37 - reps)
        case .epley: weight * (1 + reps / 30)
        case .mcglothin: 100 * weight / (101.3 - 2.67123 * reps)
        case .lombardi: weight * pow(reps, 0.1)
        case .mayhew: 100 * weight / (52.2 + 41.9 * exp(-0.055 * reps))
        case .oconner: weight * (1 + 0.025 * reps)
        case .wathen: 100 * weight / (48.8 + 53.8 * exp(-0.075 * reps))
        }
    }
}

public enum OneRepMax {
    // Brzycki divides by (37 - reps): past this, its estimate is meaningless.
    public static let maxReps = 30

    // A single rep is the max itself, whatever the formula.
    public static func estimate(weightG: Int, reps: Int, formula: OneRepMaxFormula) -> Int {
        guard reps > 1 else { return weightG }
        return Int(formula.estimate(Double(weightG), reps: Double(min(reps, maxReps))).rounded())
    }

    // The estimate of the records, as on the website: Epley, the reps counted up to 12, past which it grows too fast.
    public static func recordEstimate(weightG: Int, reps: Int) -> Int {
        estimate(weightG: weightG, reps: min(reps, 12), formula: .epley)
    }

    // Reps the formula expects at `percent` of the max, rounded down (those can be done), or nil past `maxReps`.
    public static func reps(atPercent percent: Int, formula: OneRepMaxFormula) -> Int? {
        guard percent < 100 else { return 1 }
        let ratio = 100 / Double(percent)
        guard formula.estimate(1, reps: Double(maxReps)) >= ratio else { return nil }
        var low = 1.0
        var high = Double(maxReps)
        while high - low > 0.001 {
            let mid = (low + high) / 2
            if formula.estimate(1, reps: mid) < ratio {
                low = mid
            } else {
                high = mid
            }
        }
        return max(1, Int((high + 1e-6).rounded(.down)))
    }
}
