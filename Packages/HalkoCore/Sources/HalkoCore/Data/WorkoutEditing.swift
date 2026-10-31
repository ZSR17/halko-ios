import Foundation
import SwiftData

// What the workout editor changes, before it is saved: the name of the workout and its exercises in order. Same as
// the editor of the website (`client/src/pages/WorkoutEditor.tsx`, `lib/workoutDraft.ts`).

// An exercise of the workout being edited.
public struct ItemDraft: Identifiable, Equatable, Sendable {
    public let id: String
    public let exerciseID: String
    public var mode: ItemMode
    // Items sharing it are done as a superset: a run of two consecutive items at least.
    public var supersetGroup: String?
    public var targets: [SetTarget] {
        didSet {
            // Sets added or taken off at the end; `removeSet` takes off one elsewhere.
            if targets.count > setIDs.count {
                setIDs += (setIDs.count..<targets.count).map { _ in UUID() }
            } else {
                setIDs.removeLast(setIDs.count - targets.count)
            }
        }
    }
    // An identity for each set while it is edited, in the order of `targets`.
    public private(set) var setIDs: [UUID]
    // nil: one side then the other, for an exercise working one side at a time; false: as a plain set.
    public var bySide: Bool?
    // Seconds to change sides; nil: the default.
    public var switchS: Int?
    // Empty: none.
    public var note: String

    public init(_ item: WorkoutItem) {
        id = item.id
        exerciseID = item.exerciseID
        mode = item.mode
        supersetGroup = item.supersetGroup
        targets = item.targets
        setIDs = item.targets.map { _ in UUID() }
        bySide = item.bySide
        switchS = item.switchS
        note = item.note ?? ""
    }

    // An exercise added to the workout.
    public init(exerciseID: String, mode: ItemMode, targets: [SetTarget]) {
        id = newRowID()
        self.exerciseID = exerciseID
        self.mode = mode
        supersetGroup = nil
        self.targets = targets
        setIDs = targets.map { _ in UUID() }
        bySide = nil
        switchS = nil
        note = ""
    }

    // Leaving set by set keeps the first working set as the model of all of them.
    public mutating func setMode(_ mode: ItemMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        if mode == .simple {
            targets = PlannedSetEdits.simple(targets)
        }
    }

    // The last set stays: an exercise plans one at least.
    public mutating func removeSet(_ id: UUID) {
        guard targets.count > 1, let index = setIDs.firstIndex(of: id) else { return }
        setIDs.remove(at: index)
        targets.remove(at: index)
    }

    // The identities of the sets do not count.
    public static func == (lhs: ItemDraft, rhs: ItemDraft) -> Bool {
        lhs.id == rhs.id && lhs.exerciseID == rhs.exerciseID && lhs.mode == rhs.mode && lhs.supersetGroup == rhs.supersetGroup
            && lhs.targets == rhs.targets && lhs.bySide == rhs.bySide && lhs.switchS == rhs.switchS && lhs.note == rhs.note
    }

    var savedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func write(to item: WorkoutItem) {
        item.mode = mode
        item.supersetGroup = supersetGroup
        item.targets = targets
        item.bySide = bySide
        item.switchS = switchS
        item.note = savedNote
    }

    func same(as item: WorkoutItem) -> Bool {
        item.mode == mode && item.supersetGroup == supersetGroup && item.targets == targets && item.bySide == bySide
            && item.switchS == switchS && item.note == savedNote
    }
}

public struct WorkoutDraft: Equatable, Sendable {
    public var name: String
    public var items: [ItemDraft]

    // `items`: the exercises of the workout, in order.
    public init(_ workout: Workout, items: [WorkoutItem]) {
        name = workout.name
        self.items = items.map(ItemDraft.init)
    }

    // A workout needs a name.
    public var canSave: Bool {
        !savedName.isEmpty
    }

    // Whether saving would change something: blanks around the name and the notes are not kept.
    public func differs(from other: WorkoutDraft) -> Bool {
        savedName != other.savedName || items.map(\.saved) != other.items.map(\.saved)
    }

    public var supersetCount: Int {
        Set(items.compactMap(\.supersetGroup)).count
    }

    // Whether the item at `index` and the next one are done as a superset.
    public func isLinked(after index: Int) -> Bool {
        guard items.indices.contains(index + 1), let group = items[index].supersetGroup else { return false }
        return items[index + 1].supersetGroup == group
    }

    // Links the item at `index` with the next one into a superset (joining the supersets they are in), or splits the
    // superset between them.
    public mutating func toggleSuperset(after index: Int) {
        guard items.indices.contains(index + 1) else { return }
        let current = items[index].supersetGroup
        let next = items[index + 1].supersetGroup
        if isLinked(after: index) {
            let fresh = newRowID()
            var k = index + 1
            while k < items.count, items[k].supersetGroup == current {
                items[k].supersetGroup = fresh
                k += 1
            }
        } else {
            let group = current ?? next ?? newRowID()
            items[index].supersetGroup = group
            items[index + 1].supersetGroup = group
            var k = index + 2
            while next != nil, k < items.count, items[k].supersetGroup == next {
                items[k].supersetGroup = group
                k += 1
            }
        }
        normalizeSupersets()
    }

    public mutating func remove(_ id: ItemDraft.ID) {
        items.removeAll { $0.id == id }
        normalizeSupersets()
    }

    // Moves an item before the item `before` (nil: to the end). Put between two items of a superset, it joins it; at
    // the edge of its own superset, it stays in it; anywhere else it is done alone.
    public mutating func move(_ id: ItemDraft.ID, before: ItemDraft.ID?) {
        guard var moved = items.first(where: { $0.id == id }) else { return }
        var others = items.filter { $0.id != id }
        let index = before.flatMap { before in others.firstIndex { $0.id == before } } ?? others.count
        let previous = index > 0 ? others[index - 1].supersetGroup : nil
        let next = index < others.count ? others[index].supersetGroup : nil
        moved.supersetGroup = if let previous, previous == next {
            previous
        } else if let own = moved.supersetGroup, own == previous || own == next {
            own
        } else {
            nil
        }
        others.insert(moved, at: index)
        items = others
        normalizeSupersets()
    }

    // Moves the items `ids` of a superset together, in their order, before the item `before` (nil: to the end).
    public mutating func moveBlock(_ ids: [ItemDraft.ID], before: ItemDraft.ID?) {
        let moved = items.filter { ids.contains($0.id) }
        var others = items.filter { !ids.contains($0.id) }
        let index = before.flatMap { before in others.firstIndex { $0.id == before } } ?? others.count
        others.insert(contentsOf: moved, at: index)
        items = others
        normalizeSupersets()
    }

    // A superset is a run of two consecutive items at least: a group left alone is dropped, and a second run of
    // the same group (after a move) gets one of its own.
    mutating func normalizeSupersets() {
        var seen: Set<String> = []
        var start = 0
        while start < items.count {
            var end = start
            guard let group = items[start].supersetGroup else {
                start += 1
                continue
            }
            while end + 1 < items.count, items[end + 1].supersetGroup == group {
                end += 1
            }
            let replacement = end == start ? nil : seen.contains(group) ? newRowID() : group
            for k in start...end {
                items[k].supersetGroup = replacement
            }
            seen.insert(group)
            start = end + 1
        }
    }

    var savedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ItemDraft {
    // As saving keeps it.
    var saved: ItemDraft {
        var copy = self
        copy.note = savedNote ?? ""
        return copy
    }
}

// The workouts changed on the device, written to the local database only: the sync sends them later. Same as the
// website (`client/src/db/workouts.ts`).
extension ModelContext {
    // The workout's name and its exercises in the draft's order, at once. Exercises no longer there are deleted;
    // only the rows that change are written (and synced).
    public func saveWorkout(_ workout: Workout, with draft: WorkoutDraft) throws {
        let now = Date.now
        let id = workout.id
        let saved = try fetch(FetchDescriptor(predicate: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id }))
        let kept = Set(draft.items.map(\.id))
        var changed = false
        for item in saved where !kept.contains(item.id) {
            item.removed = true
            item.updatedAt = now
            changed = true
        }
        let byID = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (position, edited) in draft.items.enumerated() {
            if let item = byID[edited.id] {
                guard item.position != position || !edited.same(as: item) else { continue }
                edited.write(to: item)
                item.position = position
                item.updatedAt = now
            } else {
                let item = WorkoutItem(id: edited.id, workoutID: id, exerciseID: edited.exerciseID, position: position, targets: [])
                edited.write(to: item)
                insert(item)
            }
            changed = true
        }
        if changed || draft.savedName != workout.name {
            workout.name = draft.savedName
            workout.updatedAt = now
        }
        try save()
    }

    // An exercise added to a workout starts from what is known of it: the plan of another workout using it (sets,
    // warm-ups, rests) with the values of the last time it was done; else the sets done last time; else the
    // defaults of its type.
    public func startingItem(for exercise: Exercise, unit: WeightUnit) throws -> ItemDraft {
        let id = exercise.id
        let others = try fetch(FetchDescriptor(
            predicate: #Predicate<WorkoutItem> { !$0.removed && $0.exerciseID == id },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
        let workoutIDs = Array(Set(others.map(\.workoutID)))
        let liveWorkouts = Set(try fetch(FetchDescriptor(predicate: #Predicate<Workout> { !$0.removed && workoutIDs.contains($0.id) })).map(\.id))
        let base = others.first { liveWorkouts.contains($0.workoutID) }
        let last = try lastSets(of: id)
        if let base {
            let plan = DonePlan.applying(DoneSets(last), to: base.targets, mode: base.mode)
            return ItemDraft(exerciseID: id, mode: plan.mode, targets: plan.targets)
        }
        if !last.isEmpty {
            let restS = PlannedSetEdits.defaultTargets(exercise.exerciseType, unit: unit)[0].restS
            let targets = last.map { set in
                SetTarget(kind: set.kind, reps: set.reps, weightG: set.weightG, durationS: set.durationS, distanceM: set.distanceM, restS: restS)
            }
            let identical = targets.allSatisfy { $0.kind == .normal && $0 == targets[0] }
            return ItemDraft(exerciseID: id, mode: identical ? .simple : .perSet, targets: targets)
        }
        return ItemDraft(exerciseID: id, mode: .simple, targets: PlannedSetEdits.defaultTargets(exercise.exerciseType, unit: unit))
    }

    // The sets of the last session the exercise was done in, in order.
    func lastSets(of exerciseID: String) throws -> [SetLog] {
        var latest = FetchDescriptor(
            predicate: #Predicate<SetLog> { !$0.removed && $0.exerciseID == exerciseID },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        latest.fetchLimit = 1
        guard let session = try fetch(latest).first?.sessionID else { return [] }
        return try fetch(FetchDescriptor(
            predicate: #Predicate<SetLog> { !$0.removed && $0.exerciseID == exerciseID && $0.sessionID == session },
            sortBy: [SortDescriptor(\.position), SortDescriptor(\.setIndex)]
        ))
    }
}

// The values of a set done, without the empty ones.
struct DoneValues: Equatable {
    var reps: Int?
    var weightG: Int?
    var durationS: Double?
    var distanceM: Double?
}

// What was done of an exercise: the values of each set by its rank among warm-ups or among working sets ("2nd
// working set"), since two workouts may plan a different number of warm-ups; and the values of the working sets
// when they were all done the same way.
struct DoneSets {
    let values: [String: DoneValues]
    let model: DoneValues?

    // `sets` in order.
    init(_ sets: [SetLog]) {
        let kinds = sets.map { SetTarget(kind: $0.kind) }
        var values: [String: DoneValues] = [:]
        for (index, set) in sets.enumerated() {
            values[DonePlan.rank(kinds, index)] = DoneValues(reps: set.reps, weightG: set.weightG, durationS: set.durationS, distanceM: set.distanceM)
        }
        self.values = values
        let working = sets.filter { $0.kind != .warmup }
            .map { DoneValues(reps: $0.reps, weightG: $0.weightG, durationS: $0.durationS, distanceM: $0.distanceM) }
        model = working.first.flatMap { first in working.allSatisfy { $0 == first } ? first : nil }
    }
}

enum DonePlan {
    static func rank(_ sets: [SetTarget], _ index: Int) -> String {
        let warmup = sets[index].kind == .warmup
        return "\(warmup):\(sets[..<index].count(where: { ($0.kind == .warmup) == warmup }))"
    }

    // A plan with the values done; only planned sets change. Identical sets (simple mode) stay so when every
    // working set was done the same way; otherwise they become set by set, so that each keeps what was done.
    static func applying(_ done: DoneSets, to targets: [SetTarget], mode: ItemMode) -> (mode: ItemMode, targets: [SetTarget]) {
        if mode == .simple, let model = done.model {
            return (mode, targets.map { $0.with(model) })
        }
        if mode == .simple && done.values.isEmpty {
            return (mode, targets)
        }
        return (.perSet, targets.enumerated().map { index, target in
            guard let values = done.values[rank(targets, index)] else { return target }
            guard target.kind == .warmup else { return target.with(values) }
            // A warm-up worked out from the working sets stays so.
            var kept = values
            if target.weightG == nil {
                kept.weightG = nil
            }
            if target.reps == nil {
                kept.reps = nil
            }
            return target.with(kept)
        })
    }
}

extension SetTarget {
    // With the values done that are there.
    func with(_ values: DoneValues) -> SetTarget {
        var changed = self
        changed.reps = values.reps ?? reps
        changed.weightG = values.weightG ?? weightG
        changed.durationS = values.durationS ?? durationS
        changed.distanceM = values.distanceM ?? distanceM
        return changed
    }
}
