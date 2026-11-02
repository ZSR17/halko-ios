import HealthKit

// The only types of Health that Halko uses: the workout it writes with what is measured during it, and what it shows
// (the heart rate and the calories of the session, today's rings).
enum HealthTypes {
    static var share: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
    }

    static var read: Set<HKObjectType> {
        [HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate), HKObjectType.activitySummaryType()]
    }

    nonisolated static var beatsPerMinute: HKUnit {
        HKUnit.count().unitDivided(by: .minute())
    }
}

// HealthKit calls back on its own queues: a HealthKit object crosses to the main actor in this box, without the
// compiler's checks.
nonisolated struct Handoff<Value>: @unchecked Sendable {
    let value: Value
}
