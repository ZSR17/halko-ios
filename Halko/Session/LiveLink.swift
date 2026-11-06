import Foundation
import HalkoCore
import os
import SwiftData
import WatchConnectivity

// The session in progress on both devices, either one able to act on it: every action is written here first, then the
// session as it is now goes to the other device, by the channel of the workout of Health or else by WatchConnectivity.
// Nothing waits on it, and the other device may never be there.
@MainActor
final class LiveLink {
    nonisolated private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")

    private let context: ModelContext
    private let store: LiveSessionStore
    private let recorder: WorkoutRecorder
    // After a change that came from the other device, with the app possibly in the background.
    var onReceived: (@MainActor () async -> Void)?
    // The session the other device has to hear about, until it was told its end.
    private var current: String?
    // What the other device holds as far as this one knows: only news are sent.
    private var shared: LiveSnapshot?
    private var saidRecording: Bool?
    private var pending: Task<Void, Never>?

    init(container: ModelContainer, store: LiveSessionStore, recorder: WorkoutRecorder) {
        context = container.mainContext
        self.store = store
        self.recorder = recorder
        current = store.state?.sessionID
        recorder.peer = self
        store.onChange = { [weak self] in
            self?.changed()
        }
        // A set written, among other changes.
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.changed()
            }
        }
    }

    // The session is told once the changes of an action are over.
    private func changed() {
        if let id = store.state?.sessionID {
            current = id
        }
        guard current != nil else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            look()
        }
    }

    private func look() {
        guard let current else { return }
        do {
            // Ended while this device held it, by the sessions the two apps give each other.
            if let state = store.state, state.sessionID == current,
               let session = try context.fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == current })).first, session.isOver {
                close(session)
                return
            }
        } catch {
            Self.logger.error("Cannot read the session in progress: \(String(describing: error))")
        }
        tell()
    }

    // The session as it is now, if it is news.
    private func tell() {
        guard let current else { return }
        do {
            guard let snapshot = try context.liveSnapshot(of: current, state: store.state, recordsHealth: recorder.isRecording) else { return }
            if let shared, snapshot.says(sameAs: shared), saidRecording == snapshot.recordsHealth { return }
            shared = snapshot
            saidRecording = snapshot.recordsHealth
            let data = try LiveMessage.snapshot(snapshot).encoded()
            send(data)
            keepForLater(data)
            if snapshot.state == nil {
                forget()
            }
        } catch {
            Self.logger.error("Cannot tell the other device about the session: \(String(describing: error))")
        }
    }

    private func forget() {
        current = nil
        shared = nil
        saidRecording = nil
    }

    // MARK: From the other device

    func received(_ data: Data) {
        do {
            switch try LiveMessage(decoding: data) {
            case let .snapshot(snapshot):
                try apply(snapshot)
            case let .measures(heartRate, kilocalories):
                recorder.otherDeviceMeasured(heartRate: heartRate, kilocalories: kilocalories)
            case let .saved(result):
                recorder.otherDeviceSaved(result)
            }
        } catch {
            Self.logger.error("Cannot read what the other device says: \(String(describing: error))")
        }
    }

    private func apply(_ snapshot: LiveSnapshot) throws {
        let held = store.state
        switch try context.apply(snapshot, held: held) {
        case .unrelated:
            return
        case let .over(session):
            // A late message of a session already let go here changes nothing.
            guard held?.sessionID == session.id else { return }
            close(session)
        case let .going(state):
            current = state.sessionID
            shared = snapshot
            recorder.otherDevice(records: snapshot.recordsHealth)
            store.set(state)
            #if os(watchOS)
            if held == nil {
                startWorkout()
            }
            #endif
            // What this device knows and the other does not goes back to it.
            changed()
        }
        if let onReceived {
            Task {
                await onReceived()
            }
        }
    }

    // Saved or discarded on the other device: its workout, when it runs here, goes the same way. Its summary is shown
    // here too only if this device hears of it at once: later, the summary was seen over there long ago.
    private func close(_ session: Session) {
        forget()
        if session.removed {
            recorder.discard()
        } else {
            recorder.finish(at: session.endedAt ?? .now)
        }
        #if os(watchOS)
        let shows = !session.removed && session.justEnded()
        Task {
            await RestAlert.schedule(nil)
        }
        #else
        let shows = !session.removed && session.justEnded() && store.isPresented
        store.isPresented = shows
        #endif
        store.finishedElsewhere = shows ? session : nil
        store.set(nil)
    }

    #if os(watchOS)
    // The workout of the session goes on the watch, which measures it best: from the start of the session when the
    // iPhone has just started it and was waiting, or from now, taking over from the iPhone's.
    func startWorkout() {
        guard let state = store.state, !recorder.isRecording else { return }
        let id = state.sessionID
        let startedAt = (try? context.fetch(FetchDescriptor(predicate: #Predicate<Session> { $0.id == id })).first)?.startedAt
        let now = Date.now
        let fromStart = !recorder.otherDeviceRecords && startedAt.map { now.timeIntervalSince($0) < 30 } == true
        recorder.start(sessionID: id, at: fromStart ? startedAt ?? now : now)
    }
    #endif

    // MARK: Transport

    private var linked: WCSession? {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return nil }
        #if os(iOS)
        return WCSession.default.isPaired && WCSession.default.isWatchAppInstalled ? WCSession.default : nil
        #else
        return WCSession.default.isCompanionAppInstalled ? WCSession.default : nil
        #endif
    }

    private func send(_ data: Data) {
        let sent = recorder.sendToOtherDevice(data) { [weak self] in
            self?.sendByMessage(data)
        }
        if !sent {
            sendByMessage(data)
        }
    }

    private func sendByMessage(_ data: Data) {
        guard let linked, linked.isReachable else { return }
        linked.sendMessageData(data, replyHandler: nil) { @Sendable error in
            Self.logger.debug("Not sent by message: \(String(describing: error))")
        }
    }

    // Only the last state is worth delivering when the other app comes back.
    private func keepForLater(_ data: Data) {
        do {
            try linked?.updateApplicationContext([CompanionMessage.liveKey: data])
        } catch {
            Self.logger.error("Cannot leave the session for the other device: \(String(describing: error))")
        }
    }
}

extension LiveLink: WorkoutPeer {
    func recordingChanged() {
        changed()
    }

    // Said again: what was sent before it opened may have gone nowhere.
    func channelOpened() {
        shared = nil
        changed()
    }

    func measured(heartRate: Double?, kilocalories: Double?) {
        do {
            let data = try LiveMessage.measures(heartRate: heartRate, kilocalories: kilocalories).encoded()
            _ = recorder.sendToOtherDevice(data) {}
        } catch {
            Self.logger.error("Cannot tell the other device what is measured: \(String(describing: error))")
        }
    }

    func workoutEnding() {
        pending?.cancel()
        tell()
    }

    func saved(_ result: HealthResult) {
        do {
            linked?.transferUserInfo([CompanionMessage.liveKey: try LiveMessage.saved(result).encoded()])
        } catch {
            Self.logger.error("Cannot tell the other device what Health measured: \(String(describing: error))")
        }
    }
}
