// Activity is not marked Sendable: updated from the main actor, it only goes to ActivityKit itself.
@preconcurrency import ActivityKit
import AudioToolbox
import Foundation
import HalkoCore
import os
import SwiftData

// The session in progress outside the app: its Live Activity, started with it and ended with it, its buttons, and
// the end of the rest. Kept up to date from the session's state, whether the session is on screen or not.
//
// The end of a rest is told by the app itself while a workout of Health keeps it running: Halko's sound plays over
// the music, even in silent mode, and the iPhone vibrates; no notification, which Siri would read in
// headphones (and no alert of the activity: it did not light the screen up, only played the system's sound). Without
// that workout the app is not running then: a notification tells it. With the workout on the watch, the watch tells it.
@MainActor
final class SessionActivities {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")

    private let container: ModelContainer
    private let store: LiveSessionStore
    private let recorder: WorkoutRecorder
    // Off with the interface tests' sample data: the device's lock screen is never touched.
    private let showsActivity: Bool
    // What was last worked out, to work it out again only when the session changed.
    private var last: (state: LiveState, content: SessionActivityAttributes.ContentState, startedAt: Date)?
    private var lastAlert: RestAlert.Request?
    // Waits for the end of the rest going on.
    private var restWatch: (end: Date, task: Task<Void, Never>)?
    // Waits for the next change of the timer of a set.
    private var timerWatch: (date: Date, task: Task<Void, Never>)?
    private let sound = RestSound()

    init(container: ModelContainer, store: LiveSessionStore, recorder: WorkoutRecorder, showsActivity: Bool) {
        self.container = container
        self.store = store
        self.recorder = recorder
        self.showsActivity = showsActivity
    }

    // A button of the session, from outside the app.
    func apply(_ action: SessionAction) async {
        let context = container.mainContext
        do {
            try store.change { state in
                switch action {
                case .shortenRest: state.shortenRest()
                case .skipRest: state.endRest()
                case .lengthenRest: state.lengthenRest()
                case .validateSet:
                    guard let glance = try context.glance(of: state, unit: Units(defaults: .standard, locale: .current).weight) else { return }
                    try context.logSet(&state, step: state.cursor, values: glance.values, startedFrom: glance.startedFrom)
                case .startTimer:
                    guard let glance = try context.glance(of: state, unit: Units(defaults: .standard, locale: .current).weight) else { return }
                    state.startTimer(
                        stepKey: LivePlan.key(state.plan[glance.item].itemID, glance.set),
                        values: glance.values,
                        startedFrom: glance.startedFrom,
                        sidesPauseS: state.livePlan.items[glance.item].sidesPauseS,
                        settings: SetTimerSettings(defaults: .standard)
                    )
                case .beginTimer:
                    state.beginHolding()
                case .cancelTimer:
                    state.setTimer = nil
                case .stopTimer:
                    try context.stopTimer(&state)
                }
            }
        } catch {
            Self.logger.error("Cannot change the session: \(String(describing: error))")
        }
        await refresh()
    }

    // Shows the session as it is now; once it is over, nothing.
    func refresh() async {
        sound.hold(store.state != nil && !recorder.otherDeviceRecords)
        watchRest()
        watchTimer()
        let found = store.state.flatMap(content(of:))
        // The activity first: a button pressed on it waits for it.
        if showsActivity {
            await show(found)
        }
        let targetEnd = store.state?.setTimer?.targetEnd
        let alert = recorder.isRecording || recorder.otherDeviceRecords ? nil : found.flatMap { found -> RestAlert.Request? in
            if let targetEnd {
                return RestAlert.Request(end: targetEnd, body: Self.alertBody(found.content), title: String(localized: "Target reached"))
            }
            return found.content.restEndsAt.map { RestAlert.Request(end: $0, body: Self.alertBody(found.content)) }
        }
        if alert != lastAlert {
            // A rest over on its own: its notification, just shown, stays.
            let ended = alert == nil && (lastAlert.map { $0.end <= .now } ?? true)
            lastAlert = alert
            if !ended {
                await RestAlert.schedule(alert)
            }
        }
    }

    private func show(_ found: (content: SessionActivityAttributes.ContentState, startedAt: Date)?) async {
        let running = Activity<SessionActivityAttributes>.activities
        let sessionID = store.state?.sessionID
        let others = running.filter { $0.attributes.sessionID != sessionID }
        if let found, let sessionID {
            let content = ActivityContent(state: found.content, staleDate: store.state?.setTimer?.nextChange(after: .now) ?? found.content.restEndsAt)
            if let activity = running.first(where: { $0.attributes.sessionID == sessionID }) {
                await activity.update(content)
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                do {
                    _ = try Activity.request(attributes: SessionActivityAttributes(sessionID: sessionID, startedAt: found.startedAt), content: content)
                } catch {
                    Self.logger.error("Cannot show the session outside the app: \(String(describing: error))")
                }
            }
        }
        for activity in others {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // The rest ends here, on screen or not: at its end, or at once when it ended while the app was stopped.
    private func watchRest() {
        let end = store.state?.restEndsAt
        sound.schedule(at: recorder.otherDeviceRecords ? nil : store.state?.setTimer?.nextChange(after: .now) ?? end)
        guard end != restWatch?.end else { return }
        restWatch?.task.cancel()
        restWatch = nil
        guard let end else { return }
        guard end > .now else {
            store.restOver()
            return
        }
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            await self?.restEnded(at: end)
        }
        restWatch = (end, task)
    }

    // The timer of a set, on screen or not: holding starts, the target is reached, it stops on its own. The workout on
    // the watch makes the watch tell it and stop it.
    private func watchTimer() {
        let next = store.state?.setTimer?.nextChange(after: .now)
        if next == nil, !recorder.otherDeviceRecords, store.state?.setTimer?.isDue(at: .now) == true {
            Task {
                // Still due: several refreshes may have come here.
                if store.state?.setTimer?.isDue(at: .now) == true {
                    await apply(.stopTimer)
                }
            }
        }
        guard next != timerWatch?.date else { return }
        timerWatch?.task.cancel()
        timerWatch = nil
        guard let next else { return }
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            await self?.timerChanged()
        }
        timerWatch = (next, task)
    }

    private func timerChanged() async {
        timerWatch = nil
        if !recorder.otherDeviceRecords {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        await refresh()
    }

    private func restEnded(at end: Date) async {
        restWatch = nil
        guard let state = store.state, state.restEndsAt == end else { return }
        store.restOver()
        // Its sound was handed to the audio output when the rest started; the vibration, on screen or not.
        if !recorder.otherDeviceRecords {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        await refresh()
    }

    private func content(of state: LiveState) -> (content: SessionActivityAttributes.ContentState, startedAt: Date)? {
        let heartRate = recorder.heartRate.map { Int($0.rounded()) }
        // Only its rest changed (−15 s, +15 s, Skip): the set shown stays, without reading the session again.
        if let last, Self.sameSet(last.state, state) {
            var content = last.content
            content.restEndsAt = state.restEndsAt
            content.restTotalS = state.restTotalS
            content.heartRate = heartRate
            return (content, last.startedAt)
        }
        let context = container.mainContext
        let id = state.sessionID
        do {
            guard let session = try context.fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })).first,
                  !session.removed, session.endedAt == nil else { return nil }
            let units = Units(defaults: .standard, locale: .current)
            var content = SessionActivityAttributes.ContentState(
                restEndsAt: state.restEndsAt,
                restTotalS: state.restTotalS,
                heartRate: heartRate
            )
            if let glance = try context.glance(of: state, unit: units.weight) {
                let exerciseID = glance.exerciseID
                let exercise = try context.fetch(FetchDescriptor(predicate: #Predicate<Exercise> { $0.id == exerciseID })).first
                content.exercise = exercise?.localizedName ?? String(localized: "Exercise")
                content.set = glance.isWarmup ? String(localized: "Warm-up") : String(localized: "Set \(glance.workingNumber)")
                let target = SetTarget(kind: .normal, reps: glance.values.reps, weightG: glance.values.weightG, durationS: glance.values.durationS, distanceM: glance.values.distanceM)
                content.values = SetsText(units: units).set(target, type: glance.exerciseType, unit: true)
                let metrics = glance.exerciseType.metrics
                content.usesTimer = metrics.contains(.duration) && !metrics.contains(.distance)
            }
            content.timer = state.setTimer.map(Self.timerContent)
            last = (state, content, session.startedAt)
            return (content, session.startedAt)
        } catch {
            Self.logger.error("Cannot read the session in progress: \(String(describing: error))")
            return nil
        }
    }

    private static func sameSet(_ a: LiveState, _ b: LiveState) -> Bool {
        var a = a
        a.restEndsAt = b.restEndsAt
        a.restTotalS = b.restTotalS
        a.changedAt = b.changedAt
        return a == b
    }

    private static func timerContent(_ timer: SetTimer) -> SessionActivityAttributes.ContentState.Timer {
        let display = SetTimerDisplay(timer: timer, date: .now)
        return .init(
            startsAt: timer.startsAt,
            targetEnd: timer.targetEnd,
            isPause: timer.firstSideS != nil,
            waitTitle: display.waitTitle,
            holdTitle: display.holdTitle,
            overTitle: display.overTitle,
            stopTitle: display.stopTitle
        )
    }

    // "Set 3 · Bench press · 80 kg × 8".
    private static func alertBody(_ content: SessionActivityAttributes.ContentState) -> String {
        let parts = [content.set, content.exercise, content.values].compactMap { $0 }
        return parts.isEmpty ? String(localized: "Time for the next set.") : parts.joined(separator: " · ")
    }
}
