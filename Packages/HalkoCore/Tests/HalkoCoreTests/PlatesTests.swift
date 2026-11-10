import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct PlatesTests {
    let plates = [
        Plate(weightG: 25_000, count: 2),
        Plate(weightG: 20_000, count: 2),
        Plate(weightG: 15_000, count: 2),
        Plate(weightG: 10_000, count: 4),
        Plate(weightG: 5_000, count: 4),
        Plate(weightG: 2_500, count: 2),
    ]

    private func load(_ targetG: Int, plates: [Plate]? = nil) -> PlateResult {
        PlateCalculator.load(barG: 20_000, targetG: targetG, plates: plates ?? self.plates, unit: .kg)
    }

    @Test("Finds the fewest plates for each side, the heaviest first")
    func exact() {
        #expect(load(100_000) == .exact(PlateLoad(totalG: 100_000, perSideG: 40_000, perSide: [
            .init(weightG: 25_000, count: 1),
            .init(weightG: 15_000, count: 1),
        ])))
    }

    @Test("Asks for nothing but the bar")
    func barOnly() {
        #expect(load(20_000) == .exact(PlateLoad(totalG: 20_000, perSideG: 0, perSide: [])))
    }

    @Test("Offers the closest loads when the weight cannot be made")
    func closest() {
        guard case .closest(let below, let above) = load(21_000) else {
            Issue.record("Should not be exact")
            return
        }
        #expect(below.totalG == 20_000)
        #expect(above?.totalG == 25_000)
    }

    @Test("Has nothing above what the plates reach")
    func nothingAbove() {
        guard case .closest(let below, let above) = load(100_000, plates: [Plate(weightG: 20_000, count: 2)]) else {
            Issue.record("Should not be exact")
            return
        }
        #expect(below.totalG == 60_000)
        #expect(above == nil)
    }

    @Test("Uses plates in pairs only")
    func pairs() {
        #expect(load(30_000, plates: [Plate(weightG: 5_000, count: 1)]) == .closest(below: PlateLoad(totalG: 20_000, perSideG: 0, perSide: []), above: nil))
    }

    @Test("Adds plates two by two, onto their weight when it is there")
    func adding() {
        var settings = PlateSettings()
        settings.add(weightG: 20_000)
        settings.add(weightG: 20_000)
        settings.add(weightG: 0)
        #expect(settings.plates.map(\.weightG) == [20_000])
        #expect(settings.plates.map(\.count) == [4])
    }

    @Test("Corrects the weight of a plate, joining it to the plates of that weight")
    func correcting() {
        var settings = PlateSettings(plates: [Plate(id: "a", weightG: 20_000, count: 2), Plate(id: "b", weightG: 25_000, count: 4)])
        settings.correct(id: "a", weightG: 15_000)
        #expect(settings.plates == [Plate(id: "a", weightG: 15_000, count: 2), Plate(id: "b", weightG: 25_000, count: 4)])
        settings.correct(id: "a", weightG: 25_000)
        #expect(settings.plates == [Plate(id: "b", weightG: 25_000, count: 6)])
        settings.correct(id: "b", weightG: 0)
        #expect(settings.plates == [Plate(id: "b", weightG: 25_000, count: 6)])
    }

    @Test("Adds up pounds exactly")
    func pounds() {
        let unit = WeightUnit.lb
        let pound = { (count: Double) in Int((count * unit.grams).rounded()) }
        let result = PlateCalculator.load(barG: pound(45), targetG: pound(135), plates: [Plate(weightG: pound(45), count: 2)], unit: unit)
        guard case .exact(let load) = result else {
            Issue.record("Should be exact")
            return
        }
        #expect(load.perSide == [.init(weightG: pound(45), count: 1)])
    }

    @Test("Starts the 1RM from the best set of the finished sessions, for the formula chosen")
    func lifted() throws {
        let container = try HalkoStore.container(inMemory: true)
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        context.insert(Exercise(id: "bench", name: "Bench", exerciseType: .weightReps))
        context.insert(Exercise(id: "plank", name: "Plank", exerciseType: .duration))
        let done = Session(name: "Done", startedAt: now, endedAt: now + 60)
        let running = Session(name: "Running", startedAt: now)
        context.insert(done)
        context.insert(running)
        let log = { (session: Session, exercise: String, kind: SetKind, reps: Int, weightG: Int) in
            context.insert(SetLog(sessionID: session.id, exerciseID: exercise, position: 0, setIndex: 0, kind: kind, reps: reps, weightG: weightG, completedAt: now))
        }
        log(done, "bench", .warmup, 3, 200_000)
        log(done, "bench", .normal, 5, 100_000)
        log(done, "bench", .normal, 10, 80_000)
        log(running, "bench", .normal, 5, 150_000)
        log(done, "plank", .normal, 5, 100_000)
        try context.save()

        let lifted = try context.liftedExercises()
        #expect(lifted.map(\.exercise.id) == ["bench"])
        // Brzycki: 112.5 kg and 106.7 kg.
        #expect(lifted[0].best(formula: .brzycki) == .init(weightG: 100_000, reps: 5))
    }
}
