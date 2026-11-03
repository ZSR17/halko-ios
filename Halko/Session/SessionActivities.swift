import ActivityKit
import Foundation
import HalkoCore
import os
import SwiftData

// The session in progress outside the app: its Live Activity, started with it and ended with it, and the end of rest
// notification. Kept up to date from the session's state, whether the session is on screen or not; the rest's
// buttons of the Dynamic Island come here too.
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

    init(container: ModelContainer, store: LiveSessionStore, recorder: WorkoutRecorder, showsActivity: Bool) {
        self.container = container
        self.store = store
        self.recorder = recorder
        self.showsActivity = showsActivity
    }

    // A button of the rest, from outside the app.
    func apply(_ action: RestAction) async {
        store.change { state in
            switch action {
            case .shorten: state.shortenRest()
            case .skip: state.endRest()
            case .lengthen: state.lengthenRest()
            }
        }
        await refresh()
    }

    // Shows the session as it is now; once it is over, nothing.
    func refresh() async {
        let found = store.state.flatMap(content(of:))
        let alert = found.flatMap { found in found.content.restEndsAt.map { RestAlert.Request(end: $0, body: Self.alertBody(found.content)) } }
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

    private func content(of state: LiveState) -> (content: SessionActivityAttributes.ContentState, startedAt: Date)? {
        let heartRate = recorder.heartRate.map { Int($0.rounded()) }
        if let last, last.state == state {
            var content = last.content
            content.heartRate = heartRate
            return (content, last.startedAt)
        }
        let context = container.mainContext
        let id = state.sessionID
        do {
            guard let session = try context.fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })).first,
                  !session.removed, session.endedAt == nil else { return nil }
            let locale = Locale.current
            var content = SessionActivityAttributes.ContentState(restEndsAt: state.restEndsAt, restTotalS: state.restTotalS, heartRate: heartRate)
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
