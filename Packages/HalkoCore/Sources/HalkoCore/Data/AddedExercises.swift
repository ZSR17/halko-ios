import Foundation
import SwiftData

// Exercises added to a session while it is done, and kept in its workout afterwards if wanted.
extension ModelContext {
    // Exercises added for this session after the item `after` (after its superset, if it is in one), or at the end:
    // each planned as it would be added to a workout. The set to do stays the same.
    public func addExercises(_ state: inout LiveState, _ exercises: [Exercise], after item: Int? = nil, unit: WeightUnit) throws {
        guard !exercises.isEmpty else { return }
        var at = state.plan.count
        if let item, state.plan.indices.contains(item) {
            at = item + 1
            if let group = state.plan[item].supersetGroup {
                while at < state.plan.count, state.plan[at].supersetGroup == group {
                    at += 1
                }
            }
        }
        let step = state.livePlan.steps.indices.contains(state.cursor) ? state.livePlan.steps[state.cursor] : nil
        let current = step.map { (state.plan[$0.item].itemID, $0.set) }
        for exercise in exercises {
            let draft = try startingItem(for: exercise, unit: unit)
            let bySide = exercise.unilateral
            state.plan.insert(PlanItem(
                itemID: draft.id,
                exerciseID: exercise.id,
                exerciseType: exercise.exerciseType,
                equipment: exercise.equipment,
                targets: draft.targets,
                unilateral: bySide,
                switchS: nil
            ), at: at)
            state.added = (state.added ?? []) + [draft.id]
            at += 1
        }
        // The sets done keep their exercise: their place in the session follows it.
        let positions = Dictionary(state.plan.enumerated().map { ($1.itemID, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Date.now
        let logs = try sets(of: state.sessionID)
        for log in logs {
            if let position = log.workoutItemID.flatMap({ positions[$0] }), position != log.position {
                log.position = position
                log.updatedAt = now
            }
        }
        // The set to do where it went; every set done before: the first of the exercises added.
        let plan = state.livePlan
        let done = doneKeys(logs)
        if let current, !done.contains(LivePlan.key(current.0, current.1)), let item = positions[current.0],
           let index = plan.stepIndex(item: item, set: current.1) {
            state.cursor = index
        } else {
            state.cursor = plan.firstOpen(done: done)
        }
        try save()
    }

    // The exercises done in a session that its workout does not have, in the order of the session: added during it.
    // None when the workout is gone.
    public func addedExercises(of session: Session) throws -> [String] {
        guard let workoutID = session.workoutID,
              try fetch(FetchDescriptor(predicate: #Predicate<Workout> { !$0.removed && $0.id == workoutID })).first != nil else {
            return []
        }
        let known = Set(try fetch(FetchDescriptor(predicate: #Predicate<WorkoutItem> { $0.workoutID == workoutID })).map(\.id))
        var seen: Set<String> = []
        var added: [String] = []
        for set in try sets(of: session.id).sorted(by: { ($0.position, $0.setIndex) < ($1.position, $1.setIndex) }) {
            guard let itemID = set.workoutItemID, !known.contains(itemID), seen.insert(itemID).inserted else { continue }
            added.append(set.exerciseID)
        }
        return added
    }

    // The exercises added during the session put in its workout, where they were done among its exercises, planned
    // with the sets done.
    public func keepAddedExercises(of session: Session, now: Date = .now) throws {
        guard let workoutID = session.workoutID,
              let workout = try fetch(FetchDescriptor(predicate: #Predicate<Workout> { !$0.removed && $0.id == workoutID })).first else {
            return
        }
        var order = try fetch(FetchDescriptor(
            predicate: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == workoutID },
            sortBy: [SortDescriptor(\.position)]
        ))
        let known = Set(try fetch(FetchDescriptor(predicate: #Predicate<WorkoutItem> { $0.workoutID == workoutID })).map(\.id))
        let done = try sets(of: session.id)
        // Where each exercise was in the session.
        var place: [String: Int] = [:]
        for set in done {
            if let itemID = set.workoutItemID {
                place[itemID] = min(place[itemID] ?? .max, set.position)
            }
        }
        let added = Dictionary(grouping: done.filter { $0.workoutItemID.map { !known.contains($0) } ?? false }) { $0.workoutItemID ?? "" }
        let exerciseIDs = added.values.compactMap(\.first?.exerciseID)
        let exercises = Dictionary(try fetch(FetchDescriptor(predicate: Exercise.withIDs(exerciseIDs))).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (itemID, sets) in added.sorted(by: { (place[$0.key] ?? 0) < (place[$1.key] ?? 0) }) {
            let sets = sets.sorted { $0.setIndex < $1.setIndex }
            let type = exercises[sets[0].exerciseID]?.exerciseType ?? .weightReps
            let restS = PlannedSetEdits.defaultTargets(type, unit: .kg)[0].restS
            let targets = sets.map { set in
                SetTarget(kind: set.kind, reps: set.reps, weightG: set.weightG, durationS: set.durationS, distanceM: set.distanceM, restS: restS)
            }
            let identical = targets.allSatisfy { $0.kind == .normal && $0 == targets[0] }
            let item = WorkoutItem(id: itemID, createdAt: now, updatedAt: now, workoutID: workoutID, exerciseID: sets[0].exerciseID,
                                   position: 0, mode: identical ? .simple : .perSet, targets: targets)
            insert(item)
            // After the last exercise of the workout done before it in the session; first if none was.
            let mine = place[itemID] ?? .max
            let anchor = order.lastIndex { (place[$0.id] ?? .max) < mine }
            order.insert(item, at: anchor.map { $0 + 1 } ?? 0)
        }
        for (position, item) in order.enumerated() where item.position != position || added[item.id] != nil {
            item.position = position
            item.updatedAt = now
        }
        workout.updatedAt = now
        try save()
    }
}
