import Foundation
import SwiftData

// The timer of a set held for a time (a plank): the time to get in position, then the time held, one side then the
// other when the exercise is done by sides. Absolute times like the rest: it goes on with the app stopped, the same on
// both devices, and what it shows is worked out from the date.
public struct SetTimer: Codable, Equatable, Sendable {
    public let stepKey: String
    // What the set is recorded with, besides the time held, and what it was offered with.
    public let values: SetValues
    public let startedFrom: SetValues
    // When holding starts. Until then, the time to get in position or to change sides.
    public internal(set) var startsAt: Date
    // How long that wait lasts from its start.
    public internal(set) var waitS: Int
    // The time to reach; nil: as long as possible.
    public let targetS: Int?
    // The pause to change sides; nil for an exercise not done by sides.
    public let sidesPauseS: Int?
    // The time held on the first side, once it is done.
    public internal(set) var firstSideS: Int?
    public let stopsAtTarget: Bool

    public var isFirstSide: Bool {
        sidesPauseS != nil && firstSideS == nil
    }

    public var targetEnd: Date? {
        targetS.map { startsAt + Double($0) }
    }

    public func isWaiting(at date: Date) -> Bool {
        date < startsAt
    }

    public func isOver(at date: Date) -> Bool {
        targetEnd.map { date >= $0 } ?? false
    }

    // Stopped on its own at the target, the time held is the target.
    public func heldS(at date: Date) -> Int {
        let held = max(0, Int(date.timeIntervalSince(startsAt)))
        guard stopsAtTarget, let targetS else { return held }
        return min(held, targetS)
    }

    // The next moment something happens: holding starts, or the target is reached.
    public func nextChange(after date: Date) -> Date? {
        if date < startsAt {
            return startsAt
        }
        return targetEnd.flatMap { date < $0 ? $0 : nil }
    }

    // It has to stop on its own now.
    public func isDue(at date: Date) -> Bool {
        stopsAtTarget && isOver(at: date)
    }
}

// How the timer of a set works, the same for every exercise. Chosen on the iPhone; the watch keeps a copy.
public struct SetTimerSettings: Codable, Equatable, Sendable {
    public static let stopsAtTargetKey = "setTimer.stopsAtTarget"
    public static let getsInPositionKey = "setTimer.getsInPosition"
    public static let positionKey = "setTimer.positionS"
    public static let defaultPositionS = 5

    public var stopsAtTarget: Bool
    public var getsInPosition: Bool
    public var positionS: Int

    public init(stopsAtTarget: Bool = false, getsInPosition: Bool = true, positionS: Int = defaultPositionS) {
        self.stopsAtTarget = stopsAtTarget
        self.getsInPosition = getsInPosition
        self.positionS = positionS
    }

    public init(defaults: UserDefaults) {
        self.init(
            stopsAtTarget: defaults.bool(forKey: Self.stopsAtTargetKey),
            getsInPosition: defaults.object(forKey: Self.getsInPositionKey) as? Bool ?? true,
            positionS: defaults.object(forKey: Self.positionKey) as? Int ?? Self.defaultPositionS
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(stopsAtTarget, forKey: Self.stopsAtTargetKey)
        defaults.set(getsInPosition, forKey: Self.getsInPositionKey)
        defaults.set(positionS, forKey: Self.positionKey)
    }
}

extension LiveState {
    public mutating func startTimer(stepKey: String, values: SetValues, startedFrom: SetValues, sidesPauseS: Int?, settings: SetTimerSettings, now: Date = .now) {
        let targetS = values.durationS.map { Int($0.rounded()) }.flatMap { $0 > 0 ? $0 : nil }
        let waitS = settings.getsInPosition ? max(0, settings.positionS) : 0
        restEndsAt = nil
        setTimer = SetTimer(
            stepKey: stepKey,
            values: values,
            startedFrom: startedFrom,
            startsAt: now + Double(waitS),
            waitS: waitS,
            targetS: targetS,
            sidesPauseS: sidesPauseS,
            firstSideS: nil,
            stopsAtTarget: settings.stopsAtTarget && targetS != nil
        )
    }

    // No more waiting.
    public mutating func beginHolding(now: Date = .now) {
        setTimer?.startsAt = now
    }
}

extension ModelContext {
    // Stops holding: after the first side, the pause to change sides; else the set is recorded with the time held (the
    // shorter side, for the two sides), which the following sets do not have to reach.
    public func stopTimer(_ state: inout LiveState, now: Date = .now) throws {
        guard var timer = state.setTimer, !timer.isWaiting(at: now) else { return }
        let held = timer.heldS(at: now)
        if timer.isFirstSide, let pause = timer.sidesPauseS {
            timer.firstSideS = held
            timer.startsAt = now + Double(pause)
            timer.waitS = pause
            state.setTimer = timer
            return
        }
        let plan = state.livePlan
        guard let index = plan.steps.firstIndex(where: { plan.key($0) == timer.stepKey }) else {
            state.setTimer = nil
            return
        }
        let seconds = Double(min(timer.firstSideS ?? held, held))
        var values = timer.values
        values.durationS = seconds
        var startedFrom = timer.startedFrom
        startedFrom.durationS = max(seconds, startedFrom.durationS ?? 0)
        try logSet(&state, step: index, values: values, startedFrom: startedFrom, now: now)
    }
}
