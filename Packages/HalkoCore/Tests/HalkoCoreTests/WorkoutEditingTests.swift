import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct WorkoutEditingTests {
    let container: ModelContainer
    let context: ModelContext
    let workout: Workout
    let items: [WorkoutItem]

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
        let workout = Workout(name: "Push A", position: 0)
        self.workout = workout
        context.insert(workout)
        let set = SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 150)
        let items = ["a", "b", "c", "d"].enumerated().map { position, exercise in
            WorkoutItem(workoutID: workout.id, exerciseID: exercise, position: position, targets: [set, set, set])
        }
        self.items = items
        for item in items {
            context.insert(item)
        }
        try context.save()
    }

    var draft: WorkoutDraft {
        WorkoutDraft(workout, items: items)
    }

    func groups(_ draft: WorkoutDraft) -> [String?] {
        // The same letter for the items of one superset.
        var letters: [String: String] = [:]
        return draft.items.map { item in
            item.supersetGroup.map { group in
                if letters[group] == nil {
                    letters[group] = String(UnicodeScalar(UInt8(65 + letters.count)))
                }
                return letters[group]!
            }
        }
    }

    func liveItems() throws -> [WorkoutItem] {
        let id = workout.id
        return try context.fetch(FetchDescriptor(
            predicate: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id },
            sortBy: [SortDescriptor(\.position)]
        ))
    }

    @Test("Links an exercise with the next one, joins supersets and splits them")
    func supersets() {
        var draft = draft
        draft.toggleSuperset(after: 0)
        #expect(groups(draft) == ["A", "A", nil, nil])
        #expect(draft.isLinked(after: 0))
        draft.toggleSuperset(after: 2)
        #expect(groups(draft) == ["A", "A", "B", "B"])
        #expect(draft.supersetCount == 2)
        // Between the two: one superset of four.
        draft.toggleSuperset(after: 1)
        #expect(groups(draft) == ["A", "A", "A", "A"])
        // Split in the middle: two supersets again.
        draft.toggleSuperset(after: 1)
        #expect(groups(draft) == ["A", "A", "B", "B"])
        // Unlinked, an item left alone is no longer in a superset.
        draft.toggleSuperset(after: 0)
        #expect(groups(draft) == [nil, nil, "A", "A"])
    }

    @Test("Moves an exercise out of a superset, or into one, and a superset as a block")
    func moves() {
        var draft = draft
        draft.toggleSuperset(after: 1)
        #expect(groups(draft) == [nil, "A", "A", nil])
        let ids = draft.items.map(\.id)

        // Out of a superset of two: none left.
        var out = draft
        out.move(ids[2], before: ids[0])
        #expect(out.items.map(\.exerciseID) == ["c", "a", "b", "d"])
        #expect(groups(out) == [nil, nil, nil, nil])

        // Between the two of a superset: joins it.
        var into = draft
        into.move(ids[3], before: ids[2])
        #expect(into.items.map(\.exerciseID) == ["a", "b", "d", "c"])
        #expect(groups(into) == [nil, "A", "A", "A"])

        // At the edge of a superset: an item of it stays in it, any other is done alone.
        var within = draft
        within.move(ids[2], before: ids[1])
        #expect(within.items.map(\.exerciseID) == ["a", "c", "b", "d"])
        #expect(groups(within) == [nil, "A", "A", nil])
        var edge = draft
        edge.move(ids[0], before: ids[3])
        #expect(edge.items.map(\.exerciseID) == ["b", "c", "a", "d"])
        #expect(groups(edge) == ["A", "A", nil, nil])

        // The superset as a block, to the end.
        var block = draft
        block.moveBlock([ids[1], ids[2]], before: nil)
        #expect(block.items.map(\.exerciseID) == ["a", "d", "b", "c"])
        #expect(groups(block) == [nil, nil, "A", "A"])

        // Removed, the other one is alone.
        var removed = draft
        removed.remove(ids[1])
        #expect(groups(removed) == [nil, nil, nil])
    }

    @Test("Counts as a change only what saving keeps")
    func differs() {
        let original = draft
        var draft = original
        draft.name += " "
        draft.items[0].note = "  "
        #expect(!draft.differs(from: original))
        draft.items[0].note = "Seat 4"
        #expect(draft.differs(from: original))
        draft = original
        draft.name = " "
        #expect(!draft.canSave)
    }

    @Test("Writes only what changed, deletes the exercises taken out and adds the new ones")
    func save() throws {
        var draft = draft
        let untouched = items[0].updatedAt
        draft.items[1].note = " Seat 4 "
        draft.remove(items[3].id)
        let added = ItemDraft(exerciseID: "e", mode: .simple, targets: [SetTarget(kind: .normal, reps: 10)])
        draft.items.append(added)
        draft.name = " Push B "
        try context.saveWorkout(workout, with: draft)

        let live = try liveItems()
        #expect(live.map(\.exerciseID) == ["a", "b", "c", "e"])
        #expect(live[0].updatedAt == untouched)
        #expect(live[1].note == "Seat 4")
        #expect(live[3].id == added.id)
        #expect(live[3].position == 3)
        #expect(items[3].removed)
        #expect(workout.name == "Push B")
    }

    @Test("Leaving set by set keeps the first working set as the model")
    func simpleMode() {
        var item = ItemDraft(exerciseID: "a", mode: .perSet, targets: [
            SetTarget(kind: .warmup, restS: 60),
            SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 150),
            SetTarget(kind: .drop, reps: 10, weightG: 60_000, restS: 0),
        ])
        item.setMode(.simple)
        #expect(item.targets == Array(repeating: SetTarget(kind: .normal, reps: 8, weightG: 80_000, restS: 150), count: 2))
        #expect(PlannedSetEdits.withCount(item.targets, 4).count == 4)
        #expect(PlannedSetEdits.settingAll(item.targets, .rest, to: 90).allSatisfy { $0.restS == 90 })
    }

    @Test("A value going up brings the next sets up to it; going down stays on its set")
    func setting() {
        let targets = [80_000, 80_000, 82_500, 85_000].map { SetTarget(kind: .normal, reps: 8, weightG: $0) }
        let up = PlannedSetEdits.setting(targets, .weight, to: 84_000, at: 1, from: 80_000)
        #expect(up.map(\.weightG) == [80_000, 84_000, 84_000, 85_000])
        let down = PlannedSetEdits.setting(targets, .weight, to: 70_000, at: 1, from: 80_000)
        #expect(down.map(\.weightG) == [80_000, 70_000, 82_500, 85_000])
    }

    @Test("A set made a warm-up has its values worked out; back to working, it keeps those shown")
    func kinds() {
        let targets = [SetTarget(kind: .normal, reps: 5, weightG: 50_000), SetTarget(kind: .normal, reps: 8, weightG: 80_000)]
        let warmup = PlannedSetEdits.switchingKind(targets, shown: targets, at: 0, type: .weightReps)
        #expect(warmup[0] == SetTarget(kind: .warmup))
        #expect(PlannedSetEdits.isWorkedOut(warmup[0], .weight, type: .weightReps))
        #expect(!PlannedSetEdits.isWorkedOut(warmup[0], .weight, type: .bodyweightReps))
        let shown = Warmups.filledIn(warmup, type: .weightReps, equipment: [], unit: .kg)
        let working = PlannedSetEdits.switchingKind(warmup, shown: shown, at: 0, type: .weightReps)
        #expect(working[0].kind == .normal)
        #expect(working[0].weightG == shown[0].weightG)
        #expect(PlannedSetEdits.addingSet(working, shown: working, type: .weightReps, unit: .kg).last == targets[1])
    }

    @Test("Keeps the identity of each set, and one set at least")
    func setIdentities() {
        var item = ItemDraft(exerciseID: "a", mode: .perSet, targets: (1...3).map { SetTarget(kind: .normal, reps: $0) })
        let ids = item.setIDs
        item.removeSet(ids[1])
        #expect(item.setIDs == [ids[0], ids[2]])
        #expect(item.targets.map(\.reps) == [1, 3])
        item.targets.append(SetTarget(kind: .normal, reps: 4))
        #expect(item.setIDs.count == 3)
        #expect(Array(item.setIDs.prefix(2)) == [ids[0], ids[2]])
        item.targets = Array(item.targets.prefix(1))
        item.removeSet(item.setIDs[0])
        #expect(item.targets.count == 1)
    }

    @Test("Reads and writes the boxes in the units and the language chosen")
    func fieldText() {
        let french = FieldText(weightUnit: .kg, distanceUnit: .km, locale: Locale(identifier: "fr_FR"))
        #expect(french.text(82_500, of: .weight) == "82,5")
        #expect(french.value("82,5", of: .weight) == 82_500)
        #expect(french.value("82.5", of: .weight) == 82_500)
        #expect(french.value("-3", of: .weight) == nil)
        #expect(french.text(150, of: .rest) == "2:30")
        #expect(french.value("230", of: .rest) == 150)
        #expect(french.value("90", of: .rest) == 90)
        #expect(french.value("1:02:05", of: .duration) == 3725)
        #expect(french.value("1:x", of: .duration) == nil)
        #expect(french.text(5000, of: .distance) == "5")
        #expect(french.value("8", of: .reps) == 8)
        #expect(french.value("8,5", of: .reps) == nil)
        let pounds = FieldText(weightUnit: .lb, distanceUnit: .mi, locale: Locale(identifier: "en_US"))
        #expect(pounds.value("45", of: .weight) == 20_412)
        #expect(pounds.text(20_412, of: .weight) == "45")
    }

    @Test("An exercise added starts from another workout's plan with the values done last time")
    func startingItem() throws {
        let bench = Exercise(id: "a", name: "Bench press", exerciseType: .weightReps)
        let curl = Exercise(id: "f", name: "Curl", exerciseType: .weightReps)
        context.insert(bench)
        context.insert(curl)
        let session = Session(name: "Push A", startedAt: .now - 3600, endedAt: .now)
        context.insert(session)
        for (index, weightG) in [82_500, 82_500, 82_500].enumerated() {
            context.insert(SetLog(sessionID: session.id, exerciseID: "a", position: 0, setIndex: index, reps: 8, weightG: weightG, completedAt: .now - Double(600 - index * 60)))
        }
        try context.save()

        let item = try context.startingItem(for: bench, unit: .kg)
        #expect(item.mode == .simple)
        #expect(item.targets == Array(repeating: SetTarget(kind: .normal, reps: 8, weightG: 82_500, restS: 150), count: 3))

        let fresh = try context.startingItem(for: curl, unit: .kg)
        #expect(fresh.targets == PlannedSetEdits.defaultTargets(.weightReps, unit: .kg))
        #expect(PlannedSetEdits.defaultTargets(.weightReps, unit: .lb)[0].weightG == WeightUnit.lb.nice(20_000))
    }
}
