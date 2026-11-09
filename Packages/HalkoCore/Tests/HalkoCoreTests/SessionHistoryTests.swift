import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct SessionHistoryTests {
    let context: ModelContext
    let container: ModelContainer
    let calendar: Calendar
    // Friday 6 November 2026, noon.
    let now: Date
    let bench: Exercise

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!
        bench = Exercise(name: "Bench", exerciseType: .weightReps, equipment: [], primaryMuscles: [.chest], secondaryMuscles: [])
        context.insert(bench)
    }

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 18))!
    }

    @discardableResult
    private func session(
        on date: Date,
        name: String = "Push",
        exercise: Exercise? = nil,
        sets: [(kind: SetKind, reps: Int?, weightG: Int?)] = [],
        finished: Bool = true
    ) -> Session {
        let session = Session(name: name, startedAt: date, endedAt: finished ? date + 3240 : nil)
        context.insert(session)
        for (index, set) in sets.enumerated() {
            context.insert(SetLog(
                sessionID: session.id,
                exerciseID: (exercise ?? bench).id,
                position: 0,
                setIndex: index,
                kind: set.kind,
                reps: set.reps,
                weightG: set.weightG,
                completedAt: date + Double(index) * 60
            ))
        }
        return session
    }

    private func loaded() throws -> SessionHistory {
        try context.save()
        return try context.sessionHistory(now: now, calendar: calendar)
    }

    @Test("Counts this week's sessions, from its Monday, with their load and duration")
    func week() throws {
        session(on: day(11, 2), sets: [(.normal, 10, 80_000)])
        session(on: day(11, 4), sets: [(.warmup, 10, 20_000), (.normal, 5, 100_000)])
        session(on: day(11, 1), sets: [(.normal, 10, 100_000)])
        let week = try loaded().week
        #expect(week.sessionCount == 2)
        // Warm-ups left out.
        #expect(week.volumeG == 1_300_000)
        #expect(week.duration == 6480)
    }

    @Test("Groups the finished sessions by month, the latest first")
    func months() throws {
        let latest = session(on: day(11, 4))
        session(on: day(11, 2))
        session(on: day(10, 30))
        session(on: day(11, 5), finished: false)
        let removed = session(on: day(11, 3))
        removed.removed = true
        let months = try loaded().months
        #expect(months.map(\.sessions.count) == [2, 1])
        #expect(months[0].sessions[0].id == latest.id)
    }

    @Test("Marks the sessions that beat a record of the sessions before them, a first time beating nothing")
    func records() throws {
        let first = session(on: day(10, 1), sets: [(.normal, 3, 80_000)])
        let beaten = session(on: day(10, 8), sets: [(.normal, 3, 85_000)])
        let lighter = session(on: day(10, 15), sets: [(.normal, 3, 80_000)])
        let rows = try loaded().months.flatMap(\.sessions)
        #expect(rows.first { $0.id == first.id }?.beatRecord == false)
        #expect(rows.first { $0.id == beaten.id }?.beatRecord == true)
        #expect(rows.first { $0.id == lighter.id }?.beatRecord == false)
    }

    @Test("Does not count an estimated 1RM beaten as a record")
    func estimateIsNotARecord() throws {
        session(on: day(10, 1), sets: [(.normal, 3, 85_000), (.normal, 12, 60_000)])
        let estimate = session(on: day(10, 8), sets: [(.normal, 8, 80_000)])
        #expect(try loaded().months.flatMap(\.sessions).first { $0.id == estimate.id }?.beatRecord == false)
        #expect(try context.summary(of: estimate).records.isEmpty)
    }

    @Test("Counts as records the volume of the session and the total reps")
    func volumeRecords() throws {
        session(on: day(10, 1), sets: [(.normal, 5, 100_000)])
        let more = session(on: day(10, 8), sets: [(.normal, 4, 80_000), (.normal, 4, 80_000)])
        #expect(try loaded().months.flatMap(\.sessions).first { $0.id == more.id }?.beatRecord == true)
        #expect(try context.summary(of: more).records.map(\.measure) == [.sessionVolume, .totalReps])
    }

    @Test("Lists the exercises done, the last one first")
    func exercises() throws {
        let squat = Exercise(name: "Squat", exerciseType: .weightReps, equipment: [], primaryMuscles: [.quads], secondaryMuscles: [])
        context.insert(squat)
        session(on: day(10, 1), exercise: squat, sets: [(.normal, 5, 100_000)])
        session(on: day(10, 8), sets: [(.normal, 5, 80_000)])
        #expect(try loaded().exercises.map(\.id) == [bench.id, squat.id])
    }

    @Test("Follows each measure of a session, leaving out the warm-ups")
    func measures() throws {
        session(on: day(10, 1), sets: [(.warmup, 10, 200_000), (.normal, 8, 80_000), (.normal, 5, 90_000)])
        let history = try loaded()
        let value = { (measure: ProgressMeasure) in history.progress(of: bench, measure: measure).points.first?.value }
        #expect(value(.maxWeight) == 90_000)
        #expect(value(.sessionVolume) == 1_090_000)
        #expect(value(.bestSetVolume) == 640_000)
        #expect(value(.totalReps) == 13)
        // 90 kg × 5, Epley.
        #expect(value(.oneRepMax) == 105_000)
    }

    @Test("Offers the measures of the type of the exercise")
    func measuresOfType() {
        #expect(ProgressMeasure.measures(for: .weightReps) == [.maxWeight, .sessionVolume, .bestSetVolume, .totalReps, .oneRepMax])
        #expect(ProgressMeasure.measures(for: .duration) == [.bestTime])
        #expect(!ProgressMeasure.oneRepMax.isRecord)
    }

    @Test("Keeps as the best the first session to reach it, and the lowest for an assistance")
    func best() {
        let dates = [day(10, 1), day(10, 8), day(10, 15)]
        let points = zip(dates, [80.0, 90, 90]).map { ProgressPoint(id: "\($0)", date: $0, value: $1) }
        #expect(ExerciseProgress(measure: .maxWeight, points: points).best == points[1])
        #expect(ExerciseProgress(measure: .minAssistance, points: points).best == points[0])
    }

    @Test("Keeps the sessions of the period")
    func period() {
        let dates = [day(3, 1), day(9, 1), day(10, 20)]
        let points = dates.map { ProgressPoint(id: "\($0)", date: $0, value: 1) }
        let progress = ExerciseProgress(measure: .maxWeight, points: points)
        #expect(progress.points(in: .oneMonth, now: now, calendar: calendar).count == 1)
        #expect(progress.points(in: .threeMonths, now: now, calendar: calendar).count == 2)
        #expect(progress.points(in: .oneYear, now: now, calendar: calendar).count == 3)
        #expect(progress.points(in: .all, now: now, calendar: calendar).count == 3)
    }

    @Test("Numbers the sets of a past session by exercise, the warm-ups apart")
    func pastExercises() throws {
        let done = session(on: day(10, 1), sets: [(.warmup, 10, 40_000), (.warmup, 5, 60_000), (.normal, 8, 80_000), (.normal, 6, 85_000)])
        try context.save()
        let exercises = PastExercise.exercises(of: try context.sets(of: done.id))
        #expect(exercises.count == 1)
        #expect(exercises[0].sets.map(\.isWarmup) == [true, true, false, false])
        #expect(exercises[0].sets.map(\.number) == [1, 2, 1, 2])
        #expect(exercises[0].sets[3].values.weightG == 85_000)
    }

    @Test("Removes a session and its sets from the history, and from the records of the others")
    func remove() throws {
        let beaten = session(on: day(10, 1), sets: [(.normal, 3, 90_000)])
        let kept = session(on: day(10, 8), sets: [(.normal, 3, 85_000)])
        try context.save()
        try context.removeSession(id: beaten.id, now: now)
        #expect(beaten.removed)
        #expect(beaten.updatedAt == now)
        let history = try loaded()
        #expect(history.months.flatMap(\.sessions).map(\.id) == [kept.id])
        #expect(history.progress(of: bench, measure: .maxWeight).best?.value == 85_000)
    }
}
