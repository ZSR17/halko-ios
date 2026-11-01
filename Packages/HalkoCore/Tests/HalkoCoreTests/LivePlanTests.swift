import Testing
@testable import HalkoCore

struct LivePlanTests {
    let set = SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 150)

    func item(_ id: String, superset: String? = nil, targets: [SetTarget]? = nil, type: ExerciseType = .weightReps) -> PlanItem {
        PlanItem(itemID: id, exerciseID: "ex-\(id)", exerciseType: type, supersetGroup: superset, targets: targets ?? [set, set, set])
    }

    @Test("A superset is done round by round; an exercise with more sets finishes them alone")
    func supersetOrder() {
        let plan = LivePlan(items: [item("a"), item("b", superset: "s"), item("c", superset: "s", targets: [set, set])])
        let order = plan.steps.map { "\(plan.items[$0.item].itemID)\($0.set + 1)" }
        #expect(order == ["a1", "a2", "a3", "b1", "c1", "b2", "c2", "b3"])
    }

    @Test("No rest between the exercises of one superset round; the planned rest otherwise, 90 s without one")
    func rests() {
        var unplanned = set
        unplanned.restS = nil
        let plan = LivePlan(items: [item("a", targets: [unplanned]), item("b", superset: "s"), item("c", superset: "s")])
        #expect(plan.rest(after: 0) == 90)
        // b1 → c1, then c1 → b2.
        #expect(plan.rest(after: 1) == 0)
        #expect(plan.rest(after: 2) == 150)
        // Nothing after the last set.
        #expect(plan.rest(after: plan.steps.count - 1) == 0)
    }

    @Test("Set numbers leave out warm-ups")
    func numbers() {
        let warmup = SetTarget(kind: .warmup, restS: 60)
        let plan = LivePlan(items: [item("a", targets: [warmup, warmup, set, set])])
        #expect(plan.items[0].workingNumber(1) == 0)
        #expect(plan.items[0].workingNumber(2) == 1)
        #expect(plan.items[0].workingNumber(3) == 2)
    }

    @Test("The next set not done goes round; the first one is the set to do")
    func openSets() {
        let plan = LivePlan(items: [item("a")])
        #expect(plan.nextOpen(after: 0, done: ["a:0"]) == 1)
        #expect(plan.nextOpen(after: 2, done: ["a:2"]) == 0)
        #expect(plan.nextOpen(after: 0, done: ["a:0", "a:1", "a:2"]) == nil)
        #expect(plan.firstOpen(done: ["a:0", "a:2"]) == 1)
        #expect(plan.firstOpen(done: ["a:0", "a:1", "a:2"]) == 2)
    }

    @Test("Values: the plan, else last time, raised to what earlier sets reached")
    func proposedValues() {
        let open = SetTarget(kind: .normal, restS: 90)
        let plan = LivePlan(items: [item("a", targets: [open, set])])
        let previous = [0: SetValues(reps: 10, weightG: 70_000)]
        #expect(plan.proposed(0, set: 0, previous: previous, bumps: [:], unit: .kg) == SetValues(reps: 10, weightG: 70_000))
        #expect(plan.proposed(0, set: 1, previous: previous, bumps: ["a:1": SetValues(reps: 10)], unit: .kg)
            == SetValues(reps: 10, weightG: 80_000))
    }

    @Test("Warm-ups are worked out from today's working weight when it is above last time's")
    func warmupsFromToday() {
        let warmup = SetTarget(kind: .warmup, restS: 60)
        let plan = LivePlan(items: [item("a", targets: [warmup, set])])
        // Last time: 60 kg working, warm-up 30 × 5. Today 80 kg: worked out again (60 %, 5 reps).
        let previous = [0: SetValues(reps: 5, weightG: 30_000), 1: SetValues(reps: 8, weightG: 60_000)]
        #expect(plan.proposed(0, set: 0, previous: previous, bumps: [:], unit: .kg) == SetValues(reps: 5, weightG: 48_000))
        // Same weight as last time: last time's warm-up.
        let same = [0: SetValues(reps: 5, weightG: 30_000), 1: SetValues(reps: 8, weightG: 80_000)]
        #expect(plan.proposed(0, set: 0, previous: same, bumps: [:], unit: .kg) == SetValues(reps: 5, weightG: 30_000))
    }

    @Test("Increases are carried, decreases are not; undone they are taken back")
    func bumps() {
        let done = SetValues(reps: 12, weightG: 75_000)
        let offered = SetValues(reps: 8, weightG: 80_000)
        let added = done.increase(over: offered)
        #expect(added == SetValues(reps: 12))
        #expect(offered.raised(to: added) == SetValues(reps: 12, weightG: 80_000))
        #expect(SetValues(reps: 12).lowered(by: added) == nil)
        #expect(SetValues(reps: 12, weightG: 90_000).lowered(by: added) == SetValues(weightG: 90_000))
    }

    @Test("Volume counts the loaded exercises, both sides of a set done one side at a time")
    func volume() {
        let values = SetValues(reps: 10, weightG: 20_000)
        #expect(setVolumeG(type: .weightReps, values: values, unilateral: false) == 200_000)
        #expect(setVolumeG(type: .weightReps, values: values, unilateral: true) == 400_000)
        #expect(setVolumeG(type: .assistedBodyweight, values: values, unilateral: false) == 0)
    }
}
