import Foundation
import Testing
@testable import HalkoCore

struct ExerciseRecordsTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func set(_ session: String, minute: Double, kind: SetKind = .normal, reps: Int? = nil, weightG: Int? = nil, durationS: Double? = nil) -> SetLog {
        SetLog(sessionID: session, exerciseID: "bench", position: 0, setIndex: 0, kind: kind, reps: reps, weightG: weightG, durationS: durationS, completedAt: start + minute * 60)
    }

    @Test("Finds the max weight, the estimated 1RM and the best set of the last session")
    func weightReps() {
        let sets = [
            set("old", minute: 0, kind: .warmup, reps: 3, weightG: 120_000),
            set("old", minute: 1, reps: 3, weightG: 85_000),
            set("new", minute: 100, reps: 8, weightG: 80_000),
            set("new", minute: 103, reps: 10, weightG: 70_000),
            set("new", minute: 106, reps: 6, weightG: 80_000),
        ]
        let records = ExerciseRecords(sets: sets, type: .weightReps)
        #expect(records.records == [
            ExerciseRecord(kind: .maxWeight, value: 85_000),
            // 80 kg × 8, Epley.
            ExerciseRecord(kind: .oneRepMax, value: 101_333),
        ])
        #expect(records.lastSet == SetTarget(kind: .normal, reps: 8, weightG: 80_000))
    }

    @Test("Counts the reps up to 12 in the 1RM")
    func oneRepMaxCap() {
        #expect(OneRepMax.recordEstimate(weightG: 60_000, reps: 20) == OneRepMax.recordEstimate(weightG: 60_000, reps: 12))
        #expect(OneRepMax.recordEstimate(weightG: 60_000, reps: 1) == 60_000)
    }

    @Test("Keeps the least assistance and the longest time")
    func otherTypes() {
        let assisted = ExerciseRecords(sets: [set("a", minute: 0, reps: 8, weightG: 30_000), set("a", minute: 1, reps: 6, weightG: 20_000)], type: .assistedBodyweight)
        #expect(assisted.records == [ExerciseRecord(kind: .minAssistance, value: 20_000)])
        #expect(assisted.lastSet?.weightG == 20_000)

        let plank = ExerciseRecords(sets: [set("a", minute: 0, durationS: 45), set("b", minute: 10, durationS: 30)], type: .duration)
        #expect(plank.records == [ExerciseRecord(kind: .bestTime, value: 45)])
        #expect(plank.lastSet?.durationS == 30)
    }

    @Test("Shows nothing before the exercise is done, or with warm-ups only")
    func empty() {
        #expect(ExerciseRecords(sets: [], type: .weightReps).isEmpty)
        #expect(ExerciseRecords(sets: [set("a", minute: 0, kind: .warmup, reps: 10, weightG: 20_000)], type: .weightReps).isEmpty)
        // Done without a value: the set is still the last time.
        let bare = ExerciseRecords(sets: [set("a", minute: 0)], type: .weightReps)
        #expect(bare.records.isEmpty)
        #expect(bare.lastSet == SetTarget(kind: .normal))
    }
}
