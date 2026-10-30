import Foundation
import Testing
@testable import HalkoCore

// Same cases as the website (`client/test/lib.test.ts`, "warm-ups").
struct WarmupsTests {
    let warmup = SetTarget(kind: .warmup, restS: 60)
    let work = SetTarget(kind: .normal, reps: 5, weightG: 100_000, restS: 180)

    func kg(_ plan: [Warmups.Step]) -> String {
        plan.map { "\(Double($0.weightG) / 1000)×\($0.reps)" }.joined(separator: " · ")
    }

    @Test("Ramps from the empty bar, or 40 %, to 85 % of the working weight, reps going down")
    func plan() {
        #expect(kg(Warmups.plan(count: 2, workingG: 100_000, barG: 20_000, unit: .kg)) == "20.0×10 · 85.0×2")
        #expect(kg(Warmups.plan(count: 3, workingG: 100_000, barG: 20_000, unit: .kg)) == "20.0×10 · 52.5×5 · 85.0×2")
        #expect(kg(Warmups.plan(count: 4, workingG: 100_000, barG: 20_000, unit: .kg)) == "20.0×10 · 42.5×5 · 62.5×3 · 85.0×2")
        #expect(kg(Warmups.plan(count: 1, workingG: 100_000, barG: 20_000, unit: .kg)) == "60.0×5")
        // Dumbbells: to the kilo.
        #expect(kg(Warmups.plan(count: 3, workingG: 30_000, barG: nil, unit: .kg)) == "12.0×10 · 19.0×3 · 26.0×2")
        // Never lighter than the bar, nor heavier than the working weight.
        #expect(kg(Warmups.plan(count: 2, workingG: 25_000, barG: 20_000, unit: .kg)) == "20.0×10 · 22.5×2")
        #expect(kg(Warmups.plan(count: 2, workingG: 15_000, barG: 20_000, unit: .kg)) == "15.0×10 · 15.0×2")

        let lb = { (pounds: Double) in Int((pounds * WeightUnit.lb.grams).rounded()) }
        let plan = Warmups.plan(count: 3, workingG: lb(225), barG: lb(45), unit: .lb)
        #expect(plan.map { Int((Double($0.weightG) / WeightUnit.lb.grams).rounded()) } == [45, 120, 190])
        #expect(plan.map(\.reps) == [10, 5, 2])
    }

    @Test("Works out the warm-ups left to work out, keeps those typed in")
    func filledIn() {
        var typedIn = warmup
        typedIn.weightG = 30_000
        let shown = Warmups.filledIn([warmup, typedIn, warmup, work], type: .weightReps, equipment: ["barbell"], unit: .kg)
        #expect(shown.map(\.weightG) == [20_000, 30_000, 85_000, 100_000])
        #expect(shown.map(\.reps) == [10, 5, 2, 5])
        // Reps follow a weight typed in: 70 % calls for 3.
        typedIn.weightG = 70_000
        #expect(Warmups.filledIn([warmup, typedIn, work], type: .weightReps, equipment: ["barbell"], unit: .kg)[1].reps == 3)
        // Not for body weight exercises, nor without a loaded working set.
        let bodyweight = [warmup, SetTarget(kind: .normal, reps: 10)]
        #expect(Warmups.filledIn(bodyweight, type: .bodyweightReps, equipment: [], unit: .kg) == bodyweight)
        let unloaded = [warmup, SetTarget(kind: .normal, reps: 5)]
        #expect(Warmups.filledIn(unloaded, type: .weightReps, equipment: ["barbell"], unit: .kg) == unloaded)
    }

    @Test("Starts a barbell from 45 lb in pounds")
    func bar() {
        #expect(WeightUnit.kg.barG == 20_000)
        #expect(WeightUnit.lb.barG == 20_412)
        #expect(WeightUnit.preferred(for: Locale(identifier: "en_US")) == .lb)
        #expect(WeightUnit.preferred(for: Locale(identifier: "fr_FR")) == .kg)
        #expect(DistanceUnit.preferred(for: Locale(identifier: "en_GB")) == .mi)
        #expect(DistanceUnit.preferred(for: Locale(identifier: "fr_FR")) == .km)
    }
}
