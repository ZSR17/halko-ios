import Foundation
import SwiftData

// The state of the session being done on this device, besides its session row and its sets: the plan taken when it
// started (with the sets and exercises added or deleted since), the set to do, the rest. Kept on the device only (like the website's): only the
// session row and its sets are shared. The end of a rest is an absolute time, so it survives the app being stopped.
public struct LiveState: Codable, Equatable, Sendable {
    public let sessionID: String
    public let workoutID: String?
    public internal(set) var plan: [PlanItem]
    // Index of the set to do in the steps.
    public var cursor: Int
    public var restEndsAt: Date?
    public var restTotalS: Int
    // Values reached above the plan on a set, that the following sets of the exercise must reach, by step key.
    public var bumps: [String: SetValues]

    public init(
        sessionID: String,
        workoutID: String?,
        plan: [PlanItem],
        cursor: Int = 0,
        restEndsAt: Date? = nil,
        restTotalS: Int = 0,
        bumps: [String: SetValues] = [:]
    ) {
        self.sessionID = sessionID
        self.workoutID = workoutID
        self.plan = plan
        self.cursor = cursor
        self.restEndsAt = restEndsAt
        self.restTotalS = restTotalS
        self.bumps = bumps
    }

    public var livePlan: LivePlan {
        LivePlan(items: plan)
    }

    // Resting at `date`.
    public func isResting(at date: Date) -> Bool {
        restEndsAt.map { $0 > date } ?? false
    }

    // 15 s off the rest, never to less than a second from now.
    public mutating func shortenRest(now: Date = .now) {
        guard let end = restEndsAt else { return }
        restEndsAt = max(now + 1, end - 15)
    }

    public mutating func lengthenRest() {
        guard let end = restEndsAt else { return }
        restEndsAt = end + 15
        restTotalS += 15
    }

    public mutating func endRest() {
        restEndsAt = nil
    }

    // As in the workout editor, an exercise keeps one set at least; the session keeps one exercise.
    public func canDeleteSet(of item: Int) -> Bool {
        plan[item].targets.count > 1
    }

    public var canDeleteExercise: Bool {
        plan.count > 1
    }
}

// The sets done in the session, by step key.
public func doneKeys(_ sets: [SetLog]) -> Set<String> {
    Set(sets.compactMap { set in set.workoutItemID.map { LivePlan.key($0, set.setIndex) } })
}

extension ModelContext {
    // Starts a session of the workout: its row, and its live state.
    public func startSession(of workout: Workout, now: Date = .now) throws -> LiveState {
        let session = Session(createdAt: now, updatedAt: now, workoutID: workout.id, sport: workout.sport, name: workout.name, startedAt: now)
        insert(session)
        let state = LiveState(sessionID: session.id, workoutID: workout.id, plan: try plan(of: workout.id))
        try save()
        return state
    }

    // The live state of a session started without one on this device (on another device, or before the app was
    // reinstalled): the plan of its workout as it is now, at the first set not done.
    public func resumedState(of session: Session) throws -> LiveState {
        let plan = try session.workoutID.map(plan(of:)) ?? []
        var state = LiveState(sessionID: session.id, workoutID: session.workoutID, plan: plan)
        state.cursor = state.livePlan.firstOpen(done: doneKeys(try sets(of: session.id)))
        return state
    }

    private func plan(of workoutID: String) throws -> [PlanItem] {
        let items = try fetch(FetchDescriptor(
            predicate: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == workoutID },
            sortBy: [SortDescriptor(\.position)]
        ))
        let ids = items.map(\.exerciseID)
        let exercises = try fetch(FetchDescriptor(predicate: Exercise.withIDs(ids)))
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return items.map { PlanItem($0, exercise: byID[$0.exerciseID]) }
    }

    // The sets done in a session, in the order they were done.
    public func sets(of sessionID: String) throws -> [SetLog] {
        try fetch(FetchDescriptor(
            predicate: #Predicate<SetLog> { !$0.removed && $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.completedAt)]
        ))
    }

    // What was done of each set (by index) the last time the exercise was done, in a finished session other than
    // `sessionID`.
    public func previousPerformance(of exerciseID: String, excluding sessionID: String) throws -> [Int: SetValues] {
        let finished = Set(try fetch(FetchDescriptor(predicate: #Predicate<Session> { !$0.removed && $0.endedAt != nil })).map(\.id))
        let sets = try fetch(FetchDescriptor(
            predicate: #Predicate<SetLog> { !$0.removed && $0.exerciseID == exerciseID && $0.sessionID != sessionID },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )).filter { finished.contains($0.sessionID) }
        guard let last = sets.first?.sessionID else { return [:] }
        return Dictionary(sets.filter { $0.sessionID == last }.map { ($0.setIndex, SetValues($0)) }, uniquingKeysWith: { first, _ in first })
    }

    // Records a set done, then goes to the next set not done and starts the rest. A set already done is corrected:
    // the rest going on, if any, carries on. `startedFrom`: the values the set was offered with; what was added to
    // them is added to the following sets of the exercise too.
    public func logSet(_ state: inout LiveState, step index: Int, values: SetValues, startedFrom: SetValues? = nil, now: Date = .now) throws {
        let plan = state.livePlan
        guard plan.steps.indices.contains(index) else { return }
        let step = plan.steps[index]
        let item = plan.items[step.item]
        let done = try sets(of: state.sessionID)
        let already = done.first { $0.workoutItemID == item.itemID && $0.setIndex == step.set }
        let set = already ?? SetLog(
            createdAt: now,
            sessionID: state.sessionID,
            exerciseID: item.exerciseID,
            workoutItemID: item.itemID,
            position: step.item,
            setIndex: step.set,
            completedAt: now
        )
        if already == nil {
            insert(set)
        }
        set.kind = step.target.kind
        set.reps = values.reps
        set.weightG = values.weightG
        set.durationS = values.durationS
        set.distanceM = values.distanceM
        set.unilateral = item.unilateral ? true : nil
        set.completedAt = already?.completedAt ?? now
        set.updatedAt = now

        let added = startedFrom.map { values.increase(over: $0) } ?? SetValues()
        if !added.isEmpty {
            for next in (step.set + 1)..<max(step.set + 1, plan.setCount(step.item)) {
                let key = LivePlan.key(item.itemID, next)
                state.bumps[key] = (state.bumps[key] ?? SetValues()).raised(to: added)
            }
        }
        let doneNow = doneKeys(done).union([plan.key(step)])
        let next = plan.nextOpen(after: index, done: doneNow)
        state.cursor = next ?? index
        if already == nil {
            let rest = plan.rest(after: index)
            state.restEndsAt = rest > 0 && next != nil ? now + Double(rest) : nil
            state.restTotalS = rest
        }
        try save()
    }

    // Undoes a set validated by mistake: it is the set to do again. What it added to the next sets is taken back (it
    // comes back if the set is validated again).
    public func unlogSet(_ state: inout LiveState, item: Int, set: Int, unit: WeightUnit, now: Date = .now) throws {
        let plan = state.livePlan
        let planItem = plan.items[item]
        let done = try sets(of: state.sessionID)
        guard let log = done.first(where: { $0.workoutItemID == planItem.itemID && $0.setIndex == set }) else { return }
        log.removed = true
        log.updatedAt = now
        let previous = try previousPerformance(of: planItem.exerciseID, excluding: state.sessionID)
        let startedFrom = plan.proposed(item, set: set, previous: previous, bumps: state.bumps, unit: unit)
        let added = SetValues(log).increase(over: startedFrom)
        for next in (set + 1)..<max(set + 1, plan.setCount(item)) {
            let key = LivePlan.key(planItem.itemID, next)
            state.bumps[key] = state.bumps[key]?.lowered(by: added)
        }
        state.cursor = plan.firstOpen(done: doneKeys(done.filter { $0 !== log }))
        try save()
    }

    // One more set of an exercise for this session, like its last one, as a working set.
    public func addSet(_ state: inout LiveState, item: Int, unit: WeightUnit) throws {
        let planItem = state.plan[item]
        state.plan[item].targets = PlannedSetEdits.addingSet(planItem.targets, shown: planItem.targets, type: planItem.exerciseType, unit: unit)
        state.cursor = state.livePlan.firstOpen(done: doneKeys(try sets(of: state.sessionID)))
    }

    // A set deleted for this session, done or not (its record goes with it); the sets after it move up.
    public func deleteSet(_ state: inout LiveState, item: Int, set: Int, now: Date = .now) throws {
        guard state.canDeleteSet(of: item), state.plan[item].targets.indices.contains(set) else { return }
        let itemID = state.plan[item].itemID
        state.plan[item].targets.remove(at: set)
        let logs = try sets(of: state.sessionID)
        for log in logs where log.workoutItemID == itemID && log.setIndex >= set {
            if log.setIndex == set {
                log.removed = true
            } else {
                log.setIndex -= 1
            }
            log.updatedAt = now
        }
        var bumps: [String: SetValues] = [:]
        for (key, bump) in state.bumps {
            guard let index = Self.setIndex(key, of: itemID) else {
                bumps[key] = bump
                continue
            }
            if index != set {
                bumps[LivePlan.key(itemID, index > set ? index - 1 : index)] = bump
            }
        }
        state.bumps = bumps
        state.cursor = state.livePlan.firstOpen(done: doneKeys(logs.filter { !$0.removed }))
        try save()
    }

    // An exercise deleted for this session, with the sets done of it.
    public func deleteExercise(_ state: inout LiveState, item: Int, now: Date = .now) throws {
        guard state.canDeleteExercise else { return }
        let itemID = state.plan[item].itemID
        state.plan.remove(at: item)
        let positions = Dictionary(state.plan.enumerated().map { ($1.itemID, $0) }, uniquingKeysWith: { first, _ in first })
        let logs = try sets(of: state.sessionID)
        for log in logs {
            if log.workoutItemID == itemID {
                log.removed = true
                log.updatedAt = now
            } else if let position = log.workoutItemID.flatMap({ positions[$0] }), position != log.position {
                log.position = position
                log.updatedAt = now
            }
        }
        state.bumps = state.bumps.filter { Self.setIndex($0.key, of: itemID) == nil }
        state.cursor = state.livePlan.firstOpen(done: doneKeys(logs.filter { !$0.removed }))
        try save()
    }

    // The set of a step key of the item; nil for another item's.
    private static func setIndex(_ key: String, of itemID: String) -> Int? {
        let prefix = "\(itemID):"
        return key.hasPrefix(prefix) ? Int(key.dropFirst(prefix.count)) : nil
    }

    // Ends the session. Without any set done, nothing is kept: the session is removed and nil returned. Every workout
    // using an exercise just done takes the values done, so that the next session starts from them.
    public func finishSession(_ state: LiveState, now: Date = .now) throws -> Session? {
        let id = state.sessionID
        guard let session = try fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })).first else { return nil }
        let done = try sets(of: id)
        if done.isEmpty {
            try discardSession(state, now: now)
            return nil
        }
        session.endedAt = now
        session.updatedAt = now
        try updatePlans(state.plan, with: done, now: now)
        try save()
        return session
    }

    // Removes the session and its sets.
    public func discardSession(_ state: LiveState, now: Date = .now) throws {
        let id = state.sessionID
        for session in try fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })) {
            session.removed = true
            session.updatedAt = now
        }
        for set in try sets(of: id) {
            set.removed = true
            set.updatedAt = now
        }
        try save()
    }

    // An exercise planned twice in the session: its own items take their own sets, other workouts the first one.
    private func updatePlans(_ plan: [PlanItem], with sets: [SetLog], now: Date) throws {
        var done: [String: DoneSets] = [:]
        for item in plan {
            let own = sets.filter { $0.workoutItemID == item.itemID && $0.setIndex < item.targets.count }.sorted { $0.setIndex < $1.setIndex }
            if !own.isEmpty {
                done[item.itemID] = DoneSets(own)
            }
        }
        var byExercise: [String: String] = [:]
        for item in plan where done[item.itemID] != nil && byExercise[item.exerciseID] == nil {
            byExercise[item.exerciseID] = item.itemID
        }
        let exerciseIDs = Array(byExercise.keys)
        let items = try fetch(FetchDescriptor(predicate: #Predicate<WorkoutItem> { !$0.removed && exerciseIDs.contains($0.exerciseID) }))
        let workoutIDs = Array(Set(items.map(\.workoutID)))
        let live = Set(try fetch(FetchDescriptor(predicate: #Predicate<Workout> { !$0.removed && workoutIDs.contains($0.id) })).map(\.id))
        for item in items where live.contains(item.workoutID) {
            guard let source = done[item.id] ?? byExercise[item.exerciseID].flatMap({ done[$0] }) else { continue }
            let updated = DonePlan.applying(source, to: item.targets, mode: item.mode)
            if updated.mode != item.mode || updated.targets != item.targets {
                item.mode = updated.mode
                item.targets = updated.targets
                item.updatedAt = now
            }
        }
    }
}
