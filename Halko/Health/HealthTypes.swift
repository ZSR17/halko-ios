import HealthKit

// The only types of Health that Halko uses: the workout it writes with what is measured during it (the calories at
// rest too, for its total), and what it shows (the heart rate and the calories of the session; on the iPhone, today's
// rings).
enum HealthTypes {
    static var share: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned), HKQuantityType(.heartRate)]
    }

    static var read: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
        #if os(iOS)
        types.insert(HKObjectType.activitySummaryType())
        #endif
        return types
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
