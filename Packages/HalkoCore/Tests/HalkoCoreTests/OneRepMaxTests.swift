import Testing
@testable import HalkoCore

struct OneRepMaxTests {
    @Test("Estimates 100 kg × 5 with each formula", arguments: [
        (OneRepMaxFormula.brzycki, 112.5),
        (.epley, 116.67),
        (.mcglothin, 113.71),
        (.lombardi, 117.46),
        (.mayhew, 119.01),
        (.oconner, 112.5),
        (.wathen, 116.58),
    ])
    func estimate(formula: OneRepMaxFormula, kilograms: Double) {
        let estimate = Double(OneRepMax.estimate(weightG: 100_000, reps: 5, formula: formula)) / 1000
        #expect(abs(estimate - kilograms) < 0.05)
    }

    @Test("Keeps a single rep as is", arguments: OneRepMaxFormula.allCases)
    func singleRep(formula: OneRepMaxFormula) {
        #expect(OneRepMax.estimate(weightG: 100_000, reps: 1, formula: formula) == 100_000)
    }

    @Test("Finds the reps a percentage of the max allows")
    func repsAtPercent() {
        #expect(OneRepMax.reps(atPercent: 100, formula: .brzycki) == 1)
        #expect(OneRepMax.reps(atPercent: 95, formula: .brzycki) == 2)
        #expect(OneRepMax.reps(atPercent: 90, formula: .brzycki) == 4)
        #expect(OneRepMax.reps(atPercent: 95, formula: .epley) == 1)
        #expect(OneRepMax.reps(atPercent: 50, formula: .epley) == 30)
        #expect(OneRepMax.reps(atPercent: 50, formula: .lombardi) == nil)
    }
}
