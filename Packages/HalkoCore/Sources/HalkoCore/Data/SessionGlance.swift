import Foundation
import SwiftData

// Where the session in progress is, as shown outside the app (lock screen, Dynamic Island, end of rest notification):
// the set to do, or the one after the rest, with the values it is offered with. Values typed in the app and not
// validated yet stay in the app.
public struct SessionGlance: Equatable, Sendable {
    public let item: Int
    public let set: Int
    public let exerciseID: String
    public let exerciseType: ExerciseType
    public let isWarmup: Bool
    // The set number shown: warm-ups are not counted.
    public let workingNumber: Int
    public let values: SetValues
}

extension ModelContext {
    // Nil once every set is done (or without any set).
    public func glance(of state: LiveState, unit: WeightUnit) throws -> SessionGlance? {
        let plan = state.livePlan
        let logged = Dictionary(
            try sets(of: state.sessionID).compactMap { set in set.workoutItemID.map { (LivePlan.key($0, set.setIndex), set) } },
            uniquingKeysWith: { first, _ in first }
        )
        guard plan.steps.indices.contains(state.cursor), !plan.steps.allSatisfy({ logged[plan.key($0)] != nil }) else { return nil }
        let step = plan.steps[state.cursor]
        let item = plan.items[step.item]
        let values = logged[plan.key(step)].map(SetValues.init) ?? plan.proposed(
            step.item,
            set: step.set,
            previous: try previousPerformance(of: item.exerciseID, excluding: state.sessionID),
            bumps: state.bumps,
            unit: unit
        )
        return SessionGlance(
            item: step.item,
            set: step.set,
            exerciseID: item.exerciseID,
            exerciseType: item.exerciseType,
            isWarmup: step.target.kind == .warmup,
            workingNumber: item.workingNumber(step.set),
            values: values
        )
    }
}
