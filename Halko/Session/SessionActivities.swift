// Activity is not marked Sendable: updated from the main actor, it only goes to ActivityKit itself.
@preconcurrency import ActivityKit
import AudioToolbox
import Foundation
import HalkoCore
import os
import SwiftData
import UIKit

// The session in progress outside the app: its Live Activity, started with it and ended with it, its buttons, and
// the end of the rest. Kept up to date from the session's state, whether the session is on screen or not.
//
// The end of a rest is told by the app itself while a workout of Health keeps it running: the activity alerts (the
// screen lights up, with the system's sound, which keeps to silent mode) and the iPhone vibrates; no notification,
// which Siri would read in headphones. Without that workout the app is not running then: a notification tells it.
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
    // The set whose rest ended on its own, until it is done.
    private var restOver: (sessionID: String, cursor: Int)?

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
                    guard let glance = try context.glance(of: state, unit: .preferred(for: .current)) else { return }
                    try context.logSet(&state, step: state.cursor, values: glance.values, startedFrom: glance.values)
                }
            }
        } catch {
            Self.logger.error("Cannot change the session: \(String(describing: error))")
        }
        await refresh()
    }

    // Shows the session as it is now; once it is over, nothing. `alerting`: its rest just ended.
    func refresh(alerting: Bool = false) async {
        watchRest()
        let found = store.state.flatMap(content(of:))
        let alert = recorder.isRecording ? nil : found.flatMap { found in
            found.content.restEndsAt.map { RestAlert.Request(end: $0, body: Self.alertBody(found.content)) }
        }
        if alert != lastAlert {
            // A rest over on its own: its notification, just shown, stays.
            let ended = alert == nil && (lastAlert.map { $0.end <= .now } ?? true)
            lastAlert = alert
            if !ended {
                await RestAlert.schedule(alert)
            }
        }
        guard showsActivity else { return }
        let running = Activity<SessionActivityAttributes>.activities
        let sessionID = store.state?.sessionID
        let others = running.filter { $0.attributes.sessionID != sessionID }
        if let found, let sessionID {
            let content = ActivityContent(state: found.content, staleDate: found.content.restEndsAt)
            if let activity = running.first(where: { $0.attributes.sessionID == sessionID }) {
                let configuration = alerting
                    ? AlertConfiguration(title: "Rest over", body: LocalizedStringResource(stringLiteral: Self.alertBody(found.content)), sound: .default)
                    : nil
                await activity.update(content, alertConfiguration: configuration)
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
        guard end != restWatch?.end else { return }
        restWatch?.task.cancel()
        restWatch = nil
        guard let end else { return }
        guard end > .now else {
            store.change { $0.endRest() }
            return
        }
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            await self?.restEnded(at: end)
        }
        restWatch = (end, task)
    }

    private func restEnded(at end: Date) async {
        restWatch = nil
        guard let state = store.state, state.restEndsAt == end else { return }
        store.change { $0.endRest() }
        restOver = (state.sessionID, state.cursor)
        // In the app, the session gives its own feedback.
        if UIApplication.shared.applicationState != .active {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        await refresh(alerting: true)
    }

    private func content(of state: LiveState) -> (content: SessionActivityAttributes.ContentState, startedAt: Date)? {
        let heartRate = recorder.heartRate.map { Int($0.rounded()) }
        let isRestOver = state.restEndsAt == nil && restOver.map { $0.sessionID == state.sessionID && $0.cursor == state.cursor } == true
        if let last, last.state == state {
            var content = last.content
            content.heartRate = heartRate
            content.restOver = isRestOver
            return (content, last.startedAt)
        }
        let context = container.mainContext
        let id = state.sessionID
        do {
            guard let session = try context.fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })).first,
                  !session.removed, session.endedAt == nil else { return nil }
            let locale = Locale.current
            var content = SessionActivityAttributes.ContentState(
                restEndsAt: state.restEndsAt,
                restTotalS: state.restTotalS,
                restOver: isRestOver,
                heartRate: heartRate
            )
            if let glance = try context.glance(of: state, unit: .preferred(for: locale)) {
                let exerciseID = glance.exerciseID
                let exercise = try context.fetch(FetchDescriptor(predicate: #Predicate<Exercise> { $0.id == exerciseID })).first
                content.exercise = exercise?.localizedName ?? String(localized: "Exercise")
                content.set = glance.isWarmup ? String(localized: "Warm-up") : String(localized: "Set \(glance.workingNumber)")
                let target = SetTarget(kind: .normal, reps: glance.values.reps, weightG: glance.values.weightG, durationS: glance.values.durationS, distanceM: glance.values.distanceM)
                content.values = SetsText(locale: locale).set(target, type: glance.exerciseType, unit: true)
            }
            last = (state, content, session.startedAt)
            return (content, session.startedAt)
        } catch {
            Self.logger.error("Cannot read the session in progress: \(String(describing: error))")
            return nil
        }
    }

    // "Set 3 · Bench press · 80 kg × 8".
    private static func alertBody(_ content: SessionActivityAttributes.ContentState) -> String {
        let parts = [content.set, content.exercise, content.values].compactMap { $0 }
        return parts.isEmpty ? String(localized: "Time for the next set.") : parts.joined(separator: " · ")
    }
}
