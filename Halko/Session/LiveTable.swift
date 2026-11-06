import Foundation
import HalkoCore
import SwiftUI

// Everything the views of the session read, worked out once for each change.
struct LiveTable {
    let state: LiveState
    let plan: LivePlan
    // Sets done, by step key.
    let logged: [String: SetLog]
    let previous: [String: [Int: SetValues]]
    let edits: [String: SetValues]
    let exercises: [String: Exercise]
    let fields: FieldText
    let text: SetsText

    var step: LiveStep? {
        plan.steps.indices.contains(state.cursor) ? plan.steps[state.cursor] : nil
    }

    var allDone: Bool {
        !plan.steps.isEmpty && plan.steps.allSatisfy { logged[plan.key($0)] != nil }
    }

    func exercise(_ item: Int) -> Exercise? {
        exercises[plan.items[item].exerciseID]
    }

    func name(_ item: Int) -> String {
        exercise(item)?.localizedName ?? String(localized: "Exercise")
    }

    // Every set of the exercise is done (it has one at least).
    func isFinished(_ item: Int) -> Bool {
        let count = plan.setCount(item)
        return count > 0 && (0..<count).allSatisfy { logged[LivePlan.key(plan.items[item].itemID, $0)] != nil }
    }

    // What a set not done is offered with: last time's values or the plan, raised to what earlier sets reached.
    func proposed(_ item: Int, set: Int) -> SetValues {
        plan.proposed(item, set: set, previous: previous[plan.items[item].exerciseID] ?? [:], bumps: state.bumps, unit: fields.weightUnit)
    }

    // What the current set started with: its values when done, else what it is offered with.
    func startedFrom(_ step: LiveStep) -> SetValues {
        logged[plan.key(step)].map(SetValues.init) ?? proposed(step.item, set: step.set)
    }

    func draft(_ step: LiveStep) -> SetValues {
        edits[plan.key(step)] ?? startedFrom(step)
    }

    // The values a set shows: done, typed, or offered (an increase typed on the current set shows on the next sets of
    // the exercise straight away).
    func values(_ item: Int, set: Int) -> SetValues {
        let key = LivePlan.key(plan.items[item].itemID, set)
        if let log = logged[key] {
            return SetValues(log)
        }
        if let edited = edits[key] {
            return edited
        }
        let offered = proposed(item, set: set)
        guard let step, step.item == item, set > step.set else { return offered }
        return offered.raised(to: draft(step).increase(over: startedFrom(step)))
    }

    // "2" for the second working set, "W" for a warm-up.
    func number(_ item: Int, set: Int) -> Text {
        plan.target(item, set: set).kind == .warmup ? Text("W") : Text(verbatim: plan.items[item].workingNumber(set).formatted())
    }

    // As VoiceOver reads it: "Set 2", "Warm-up 1".
    func spokenNumber(_ item: Int, set: Int) -> String {
        if plan.target(item, set: set).kind == .warmup {
            let warmup = (0...set).count(where: { plan.target(item, set: $0).kind == .warmup })
            return String(localized: "Warm-up \(warmup)")
        }
        return String(localized: "Set \(plan.items[item].workingNumber(set))")
    }

    // The sets of an exercise, by index (warm-ups included).
    func setNumbers(_ item: Int) -> [Int] {
        Array(0..<plan.setCount(item))
    }

    func workingCount(_ item: Int) -> Int {
        (0..<plan.setCount(item)).count(where: { plan.target(item, set: $0).kind != .warmup })
    }

    // A set as on the page of a workout: "80 × 8"; with its unit, alone: "80 kg × 8".
    func setText(_ item: Int, values: SetValues, unit: Bool = false) -> String {
        let target = SetTarget(kind: .normal, reps: values.reps, weightG: values.weightG, durationS: values.durationS, distanceM: values.distanceM)
        return text.set(target, type: plan.items[item].exerciseType, unit: unit)
    }

    // What comes after the rest: "Set 3 · 80 × 8", or the next exercise.
    var nextText: String? {
        guard let step else { return nil }
        let values = setText(step.item, values: draft(step))
        if plan.target(step.item, set: step.set).kind == .warmup {
            return String(localized: "\(name(step.item)) · warm-up · \(values)")
        }
        return String(localized: "\(name(step.item)) · set \(plan.items[step.item].workingNumber(step.set)) · \(values)")
    }

    // A set held for a time, not done yet, can use the timer; running or walking keeps its time by hand.
    func canUseTimer(_ step: LiveStep) -> Bool {
        let metrics = plan.items[step.item].exerciseType.metrics
        return metrics.contains(.duration) && !metrics.contains(.distance) && logged[plan.key(step)] == nil
    }

    // The timer of the set to do.
    var timer: SetTimer? {
        guard let step, let timer = state.setTimer, timer.stepKey == plan.key(step), logged[timer.stepKey] == nil else { return nil }
        return timer
    }

    func metrics(_ item: Int) -> [SetField] {
        plan.items[item].exerciseType.metrics.map(SetField.init)
    }

    func columnTitle(_ field: SetField, item: Int, long: Bool) -> String {
        fields.columnTitle(field, type: plan.items[item].exerciseType, perSide: plan.items[item].unilateral, long: long)
    }
}

// What the timer of a set shows at a date.
struct SetTimerDisplay {
    let timer: SetTimer
    let date: Date

    var isWaiting: Bool {
        timer.isWaiting(at: date)
    }

    // Waiting between the two sides.
    var isPause: Bool {
        isWaiting && timer.firstSideS != nil
    }

    var isOver: Bool {
        !isWaiting && timer.isOver(at: date)
    }

    var waitTitle: String {
        timer.firstSideS == nil ? String(localized: "Get in position") : String(localized: "Change sides")
    }

    var holdTitle: String {
        if timer.sidesPauseS != nil {
            return timer.isFirstSide ? String(localized: "Left side") : String(localized: "Right side")
        }
        return timer.targetS == nil ? String(localized: "Held") : String(localized: "Time left")
    }

    var overTitle: String {
        timer.sidesPauseS == nil ? String(localized: "Target reached · held") : holdTitle
    }

    var stopTitle: String {
        timer.isFirstSide ? String(localized: "Next side") : String(localized: "Stop and validate")
    }

    var title: String {
        isWaiting ? waitTitle : isOver ? overTitle : holdTitle
    }

    // The time shown, in seconds: what is left of the wait or to the target, or what is held once past it.
    var seconds: Int {
        if isWaiting {
            return Int(timer.startsAt.timeIntervalSince(date).rounded(.up))
        }
        if let end = timer.targetEnd, date < end {
            return Int(end.timeIntervalSince(date).rounded(.up))
        }
        return timer.heldS(at: date)
    }

    // How much of the bar or ring is filled, from 0 to 1: the wait empties it, holding fills it.
    var part: Double {
        if isWaiting {
            return timer.waitS > 0 ? min(1, timer.startsAt.timeIntervalSince(date) / Double(timer.waitS)) : 0
        }
        guard let targetS = timer.targetS else { return 1 }
        return min(1, date.timeIntervalSince(timer.startsAt) / Double(targetS))
    }

    // Past the target: "+0:08".
    var extra: String? {
        guard isOver, let targetS = timer.targetS else { return nil }
        return "+\(FieldText.clock(timer.heldS(at: date) - targetS))"
    }

    // After the first side: "Left side: 0:40".
    var firstSide: String? {
        timer.firstSideS.map { String(localized: "Left side: \(FieldText.clock($0))") }
    }
}
