import HealthKit
import Observation
import os

// The workout of Health that goes with the session done on this device: started with it, measuring what the device
// and its sensors can (on the iPhone, the heart rate only with a sensor), saved or discarded with it. Without access to
// Health, it records nothing and the session is the same.
@MainActor
@Observable
final class WorkoutRecorder {
    // The Halko session a workout of Health belongs to, in its metadata.
    static let sessionIDKey = "HalkoSessionID"
    private nonisolated static let logger = Logger(subsystem: "com.zsr.halko", category: "health")

    // The last heart rate measured, in beats per minute.
    private(set) var heartRate: Double?
    // The active calories measured since the start.
    private(set) var activeKilocalories: Double?
    // What Health measured during the last session saved.
    private(set) var saved: HealthResult?

    let health: HKHealthStore?
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var sessionID: String?
    // The delegate of the session and of its builder, which they do not keep.
    @ObservationIgnored private var relay: Relay?

    init(health: HKHealthStore?) {
        self.health = health
    }

    // A workout of Health in progress keeps the app running in the background, where it can tell the end of a rest
    // itself.
    var isRecording: Bool {
        session != nil
    }

    func start(sessionID: String, at date: Date) {
        guard let health, session == nil,
              health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: health, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: configuration)
            attach(session, sessionID: sessionID)
            session.startActivity(with: date)
            builder.beginCollection(withStart: date) { @Sendable _, error in
                if let error {
                    Self.logger.error("Cannot start the workout: \(String(describing: error))")
                }
            }
            builder.addMetadata([Self.sessionIDKey: sessionID]) { @Sendable _, error in
                if let error {
                    Self.logger.error("Cannot name the workout: \(String(describing: error))")
                }
            }
        } catch {
            Self.logger.error("Cannot start the workout: \(String(describing: error))")
        }
    }

    // After the app was stopped during a session: the workout of Health goes on with it.
    func recover(sessionID: String?) {
        guard let health, let sessionID, session == nil else { return }
        health.recoverActiveWorkoutSession { @Sendable session, error in
            if let error {
                Self.logger.error("Cannot recover the workout: \(String(describing: error))")
            }
            guard let session else { return }
            let found = Handoff(value: session)
            Task { @MainActor [weak self] in
                self?.recovered(found.value, sessionID: sessionID)
            }
        }
    }

    // Saved in Health at the end of the session, with what was measured.
    func finish(at date: Date) {
        guard let session, let sessionID else { return }
        let builder = Handoff(value: session.associatedWorkoutBuilder())
        detach()
        session.end()
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
                    self?.saved = result
                }
            }
        }
    }

    // The session discarded, or done elsewhere: nothing saved in Health.
    func discard() {
        guard let session else { return }
        let builder = session.associatedWorkoutBuilder()
        detach()
        session.end()
        builder.discardWorkout()
    }

    private func recovered(_ session: HKWorkoutSession, sessionID: String) {
        guard let health, self.session == nil else { return }
        let builder = session.associatedWorkoutBuilder()
        // Another session's workout, left running: not this one's to save.
        if let owner = builder.metadata[Self.sessionIDKey] as? String, owner != sessionID {
            session.end()
            builder.discardWorkout()
            return
        }
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: session.workoutConfiguration)
        attach(session, sessionID: sessionID)
    }

    private func attach(_ session: HKWorkoutSession, sessionID: String) {
        let relay = Relay { [weak self] heartRate, kilocalories in
            self?.heartRate = heartRate ?? self?.heartRate
            self?.activeKilocalories = kilocalories ?? self?.activeKilocalories
        }
        session.delegate = relay
        session.associatedWorkoutBuilder().delegate = relay
        self.session = session
        self.sessionID = sessionID
        self.relay = relay
        heartRate = nil
        activeKilocalories = nil
    }

    private func detach() {
        session = nil
        sessionID = nil
        relay = nil
        heartRate = nil
        activeKilocalories = nil
    }
}

// What Health measured during a session, from its saved workout: absent when nothing measured it.
nonisolated struct HealthResult: Sendable {
    let sessionID: String
    let activeKilocalories: Double?
    let averageHeartRate: Double?
    let maximumHeartRate: Double?

    init(sessionID: String, workout: HKWorkout) {
        self.sessionID = sessionID
        activeKilocalories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
        averageHeartRate = heartRate?.averageQuantity()?.doubleValue(for: HealthTypes.beatsPerMinute)
        maximumHeartRate = heartRate?.maximumQuantity()?.doubleValue(for: HealthTypes.beatsPerMinute)
    }
}

// Called on HealthKit's queues: what is measured goes to the main actor.
private nonisolated final class Relay: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "health")
    private let measured: @MainActor @Sendable (_ heartRate: Double?, _ kilocalories: Double?) -> Void

    init(measured: @escaping @MainActor @Sendable (_ heartRate: Double?, _ kilocalories: Double?) -> Void) {
        self.measured = measured
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Self.logger.debug("Workout state \(fromState.rawValue) → \(toState.rawValue)")
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Self.logger.error("The workout failed: \(String(describing: error))")
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
        let measured = self.measured
        Task { @MainActor in
            measured(heartRate, kilocalories)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
