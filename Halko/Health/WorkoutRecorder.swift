import HalkoCore
import HealthKit
import Observation
import os
#if os(iOS)
import WatchConnectivity
#endif

// What the other device of the session hears from the workout.
@MainActor
protocol WorkoutPeer: AnyObject {
    // The workout started or stopped running on this device.
    func recordingChanged()
    // The channel of the workout with the other device has just opened.
    func channelOpened()
    func received(_ data: Data)
    func measured(heartRate: Double?, kilocalories: Double?)
    // The last moment to say something by the workout's channel.
    func workoutEnding()
    func saved(_ result: HealthResult)
}

// The workout of Health that goes with the session: on the device doing it, started with it, measuring what the device
// and its sensors can (on the iPhone, the heart rate only with a sensor), saved or discarded with it. With a watch, the
// workout runs on the watch and is mirrored on the iPhone, which is told what it measures. Without access to Health, it
// records nothing and the session is the same.
@MainActor
@Observable
final class WorkoutRecorder {
    // The Halko session a workout of Health belongs to, in its metadata.
    static let sessionIDKey = "HalkoSessionID"
    private nonisolated static let logger = Logger(subsystem: "com.zsr.halko", category: "health")
    // How long the iPhone leaves the watch to start the workout before doing it itself, from the start of the session:
    // without an answer, or once the watch said it opened (it has the session to hear of first).
    private static let watchDelay = Duration.seconds(10)
    private static let openedWatchDelay = Duration.seconds(60)
    // How long a workout started for a session not heard of yet waits for it.
    private static let unnamedDelay = Duration.seconds(30)

    // The last heart rate measured, in beats per minute.
    private(set) var heartRate: Double?
    // The active calories measured since the start.
    private(set) var activeKilocalories: Double?
    // What Health measured during the last session saved, on both devices when it was on both.
    private(set) var saved: HealthResult?
    // The workout of the session runs on the other device, which also tells the end of a rest.
    private(set) var otherDeviceRecords = false

    let health: HKHealthStore?
    @ObservationIgnored weak var peer: (any WorkoutPeer)?
    // The workout running on this device.
    @ObservationIgnored private var session: HKWorkoutSession?
    // Nil for a workout started before its session was heard of.
    @ObservationIgnored private var sessionID: String?
    // The delegate of the session and of its builder, which they do not keep.
    @ObservationIgnored private var relay: Relay?
    // This device's workout is mirrored on the other one.
    @ObservationIgnored private var isMirroring = false
    // The other device has said something by the workout: it listens to it. Until then, what is sent by it may go
    // nowhere (the mirrored workout is not set up over there yet), and goes by WatchConnectivity too.
    @ObservationIgnored private var heardBack = false
    // The other device's workout, mirrored here.
    @ObservationIgnored private var mirrored: HKWorkoutSession?
    @ObservationIgnored private var mirroredRelay: Relay?
    // The session whose workout the watch was asked to start, and what the iPhone does if it does not.
    @ObservationIgnored private var waitingForWatch: String?
    @ObservationIgnored private var watchFallback: Task<Void, Never>?
    // The workout left running by the app when it stopped may come back: none is started meanwhile.
    @ObservationIgnored private var isRecovering = false

    init(health: HKHealthStore?) {
        self.health = health
    }

    #if DEBUG
    // For the interface tests: without Health, and with a heart rate as a watch measures it, to show where it goes.
    static func demo() -> WorkoutRecorder {
        let recorder = WorkoutRecorder(health: nil)
        recorder.heartRate = 128
        return recorder
    }
    #endif

    // A workout of Health in progress keeps the app running in the background, where it can tell the end of a rest
    // itself. A mirrored one does not.
    var isRecording: Bool {
        session != nil
    }

    private static var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }

    // `sessionID` nil: asked by the iPhone, which tells the session a moment later; the workout starts at once all the
    // same, as watchOS expects, and goes if no session comes.
    func start(sessionID: String?, at date: Date) {
        guard let health, session == nil, !isRecovering,
              health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
        let configuration = Self.configuration
        do {
            let session = try HKWorkoutSession(healthStore: health, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: configuration)
            attach(session, sessionID: sessionID)
            mirror(session)
            session.startActivity(with: date)
            builder.beginCollection(withStart: date) { @Sendable _, error in
                if let error {
                    Self.logger.error("Cannot start the workout: \(String(describing: error))")
                }
            }
            if let sessionID {
                name(builder, sessionID)
            } else {
                dropIfUnnamed(session)
            }
        } catch {
            Self.logger.error("Cannot start the workout: \(String(describing: error))")
        }
    }

    // The session of a workout started before it was heard of.
    func belongs(to sessionID: String) {
        guard let session, self.sessionID == nil else { return }
        self.sessionID = sessionID
        name(session.associatedWorkoutBuilder(), sessionID)
    }

    private func name(_ builder: HKLiveWorkoutBuilder, _ sessionID: String) {
        builder.addMetadata([Self.sessionIDKey: sessionID]) { @Sendable _, error in
            if let error {
                Self.logger.error("Cannot name the workout: \(String(describing: error))")
            }
        }
    }

    private func dropIfUnnamed(_ session: HKWorkoutSession) {
        let started = ObjectIdentifier(session)
        Task { [weak self] in
            try? await Task.sleep(for: Self.unnamedDelay)
            guard let self, let own = self.session, ObjectIdentifier(own) == started, self.sessionID == nil else { return }
            Self.logger.error("No session for the workout started: discarded")
            self.discard()
        }
    }

    // After the app was stopped during a session: the workout of Health goes on with it.
    func recover(sessionID: String?) {
        guard let health, let sessionID, session == nil else { return }
        isRecovering = true
        health.recoverActiveWorkoutSession { @Sendable session, error in
            if let error {
                Self.logger.error("Cannot recover the workout: \(String(describing: error))")
            }
            let found = Handoff(value: session)
            Task { @MainActor [weak self] in
                self?.isRecovering = false
                if let session = found.value {
                    self?.recovered(session, sessionID: sessionID)
                }
            }
        }
    }

    // Saved in Health at the end of the session, with what was measured; on the device where it runs.
    func finish(at date: Date) {
        waitingForWatch = nil
        peer?.workoutEnding()
        saveOwnWorkout(at: date)
        stopFollowingOtherDevice()
    }

    // The session discarded: nothing saved in Health.
    func discard() {
        waitingForWatch = nil
        peer?.workoutEnding()
        if let session {
            let builder = session.associatedWorkoutBuilder()
            detach()
            session.end()
            builder.discardWorkout()
        }
        stopFollowingOtherDevice()
    }

    // MARK: The other device

    // What the other device says of the session being done here. On the iPhone, a workout on the watch takes over: the
    // part done here is saved, and the watch's workout carries on from now.
    func otherDevice(records: Bool) {
        guard records != otherDeviceRecords else { return }
        otherDeviceRecords = records
        #if os(iOS)
        if records {
            waitingForWatch = nil
            saveOwnWorkout(at: .now)
        }
        #endif
    }

    // What the other device's workout measures.
    func otherDeviceMeasured(heartRate: Double?, kilocalories: Double?) {
        guard otherDeviceRecords else { return }
        self.heartRate = heartRate ?? self.heartRate
        activeKilocalories = kilocalories ?? activeKilocalories
    }

    // The other device's workout saved.
    func otherDeviceSaved(_ result: HealthResult) {
        keep(result)
    }

    // Sent by the workout's channel, if it has one open; false otherwise. `failed`: it could not reach the other device.
    func sendToOtherDevice(_ data: Data, failed: @escaping @MainActor @Sendable () -> Void) -> Bool {
        guard let channel = mirrored ?? (isMirroring ? session : nil) else { return false }
        channel.sendToRemoteWorkoutSession(data: data) { @Sendable success, error in
            guard !success else { return }
            Self.logger.debug("Not sent by the workout: \(String(describing: error))")
            Task { @MainActor in
                failed()
            }
        }
        if !heardBack {
            failed()
        }
        return true
    }

    #if os(iOS)
    // To be called at launch: a workout started on the watch launches the app in the background. Once for each
    // connection, which is lost and found again during a session.
    func listenForWatch() {
        let events = relayEvents
        health?.workoutSessionMirroringStartHandler = { @Sendable session in
            let relay = Relay(events: events)
            session.delegate = relay
            let found = Handoff(value: (session, relay))
            Task { @MainActor [weak self] in
                self?.mirrored = found.value.0
                self?.mirroredRelay = found.value.1
                self?.heardBack = false
                self?.peer?.channelOpened()
            }
        }
    }

    // A session started on the iPhone: the workout is for the watch, which starts it in the background; without an
    // answer, here, with nothing asked and the same start.
    func startWithWatch(sessionID: String, at date: Date) {
        let watch = WCSession.isSupported() ? WCSession.default : nil
        guard let health, let watch, watch.activationState == .activated, watch.isPaired, watch.isWatchAppInstalled else {
            start(sessionID: sessionID, at: date)
            return
        }
        waitingForWatch = sessionID
        health.startWatchApp(with: Self.configuration) { @Sendable started, error in
            if let error {
                Self.logger.debug("The watch did not start: \(String(describing: error))")
            }
            Task { @MainActor [weak self] in
                if started {
                    // Its workout runs already: two at once for one session would measure badly. Here only if the
                    // watch never says it records.
                    self?.waitForWatch(sessionID: sessionID, startedAt: date, for: Self.openedWatchDelay)
                } else {
                    self?.watchDidNotAnswer(sessionID: sessionID, startedAt: date)
                }
            }
        }
        // Whatever becomes of that request, which may not answer with the watch out of reach.
        waitForWatch(sessionID: sessionID, startedAt: date, for: Self.watchDelay)
    }

    private func waitForWatch(sessionID: String, startedAt date: Date, for delay: Duration) {
        watchFallback?.cancel()
        watchFallback = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.watchDidNotAnswer(sessionID: sessionID, startedAt: date)
        }
    }

    private func watchDidNotAnswer(sessionID: String, startedAt date: Date) {
        guard waitingForWatch == sessionID else { return }
        waitingForWatch = nil
        watchFallback?.cancel()
        watchFallback = nil
        start(sessionID: sessionID, at: date)
    }
    #endif

    // MARK: This device's workout

    private func mirror(_ session: HKWorkoutSession) {
        #if os(watchOS)
        session.startMirroringToCompanionDevice { @Sendable success, error in
            if let error {
                Self.logger.debug("Not mirrored on the iPhone: \(String(describing: error))")
            }
            guard success else { return }
            Task { @MainActor [weak self] in
                self?.isMirroring = true
                self?.heardBack = false
                self?.peer?.channelOpened()
            }
        }
        #endif
    }

    private func saveOwnWorkout(at date: Date) {
        guard let session else { return }
        let sessionID = self.sessionID
        let builder = Handoff(value: session.associatedWorkoutBuilder())
        detach()
        session.end()
        // Its session never came, or the sessions stay out of Health.
        guard let sessionID, HealthSaving.isOn(in: .standard) else {
            builder.value.discardWorkout()
            return
        }
        builder.value.endCollection(withEnd: date) { @Sendable _, error in
            if let error {
                Self.logger.error("Cannot end the workout: \(String(describing: error))")
                return
            }
            builder.value.finishWorkout { @Sendable workout, error in
                if let error {
                    Self.logger.error("Cannot save the workout: \(String(describing: error))")
                }
                // Nil without an error: saved, but not readable with the iPhone locked.
                guard let workout else { return }
                let result = HealthResult(sessionID: sessionID, workout: workout)
                Task { @MainActor [weak self] in
                    self?.keep(result)
                    self?.peer?.saved(result)
                }
            }
        }
    }

    private func keep(_ result: HealthResult) {
        if let saved, saved.sessionID == result.sessionID {
            self.saved = saved.adding(result)
        } else {
            saved = result
        }
    }

    private func stopFollowingOtherDevice() {
        otherDeviceRecords = false
        mirrored = nil
        mirroredRelay = nil
        heardBack = false
        heartRate = nil
        activeKilocalories = nil
    }

    private func recovered(_ session: HKWorkoutSession, sessionID: String) {
        guard let health, self.session == nil else { return }
        let builder = session.associatedWorkoutBuilder()
        // Another session's workout, left running: not this one's to save.
        let owner = builder.metadata[Self.sessionIDKey] as? String
        if let owner, owner != sessionID {
            session.end()
            builder.discardWorkout()
            return
        }
        // Started before its session was heard of.
        if owner == nil {
            name(builder, sessionID)
        }
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: session.workoutConfiguration)
        attach(session, sessionID: sessionID)
        mirror(session)
    }

    private func attach(_ session: HKWorkoutSession, sessionID: String?) {
        let relay = Relay(events: relayEvents)
        session.delegate = relay
        session.associatedWorkoutBuilder().delegate = relay
        self.session = session
        self.sessionID = sessionID
        self.relay = relay
        heartRate = nil
        activeKilocalories = nil
        peer?.recordingChanged()
    }

    private func detach() {
        session = nil
        sessionID = nil
        relay = nil
        isMirroring = false
        heardBack = false
        heartRate = nil
        activeKilocalories = nil
        peer?.recordingChanged()
    }

    private var relayEvents: Relay.Events {
        Relay.Events { [weak self] heartRate, kilocalories in
            self?.heartRate = heartRate ?? self?.heartRate
            self?.activeKilocalories = kilocalories ?? self?.activeKilocalories
            self?.peer?.measured(heartRate: heartRate, kilocalories: kilocalories)
        } received: { [weak self] data in
            self?.heardBack = true
            for message in data {
                self?.peer?.received(message)
            }
        } disconnected: { [weak self] session in
            // Found again if the workout still runs: a new mirrored session then.
            if let mirrored = self?.mirrored, ObjectIdentifier(mirrored) == session {
                self?.mirrored = nil
                self?.mirroredRelay = nil
                self?.heardBack = false
            }
        } failed: { [weak self] session in
            // It could not start (from the background, without having been asked by the iPhone): tried again later.
            if let own = self?.session, ObjectIdentifier(own) == session, own.state == .notStarted {
                self?.detach()
            }
        }
    }
}

extension HealthResult {
    nonisolated init(sessionID: String, workout: HKWorkout) {
        let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
        self.init(
            sessionID: sessionID,
            activeKilocalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: HealthTypes.beatsPerMinute),
            maximumHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: HealthTypes.beatsPerMinute)
        )
    }
}

// Called on HealthKit's queues: what happens goes to the main actor.
private nonisolated final class Relay: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    struct Events: Sendable {
        let measured: @MainActor @Sendable (_ heartRate: Double?, _ kilocalories: Double?) -> Void
        let received: @MainActor @Sendable ([Data]) -> Void
        let disconnected: @MainActor @Sendable (ObjectIdentifier) -> Void
        let failed: @MainActor @Sendable (ObjectIdentifier) -> Void
    }

    private static let logger = Logger(subsystem: "com.zsr.halko", category: "health")
    private let events: Events

    init(events: Events) {
        self.events = events
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Self.logger.debug("Workout state \(fromState.rawValue) → \(toState.rawValue)")
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Self.logger.error("The workout failed: \(String(describing: error))")
        let session = ObjectIdentifier(workoutSession)
        let failed = events.failed
        Task { @MainActor in
            failed(session)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let received = events.received
        Task { @MainActor in
            received(data)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        if let error {
            Self.logger.debug("The other device of the workout is gone: \(String(describing: error))")
        }
        let session = ObjectIdentifier(workoutSession)
        let disconnected = events.disconnected
        Task { @MainActor in
            disconnected(session)
        }
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let heartRate = collectedTypes.contains(heartRateType)
            ? workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()?.doubleValue(for: HealthTypes.beatsPerMinute)
            : nil
        let kilocalories = collectedTypes.contains(energyType)
            ? workoutBuilder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            : nil
        guard heartRate != nil || kilocalories != nil else { return }
        let measured = events.measured
        Task { @MainActor in
            measured(heartRate, kilocalories)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
