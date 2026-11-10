import HalkoCore
import HealthKit
import os
import SwiftData
import SwiftUI

// The end of a session once saved: its duration, working sets and load moved, and the records beaten, worked out on
// the device; then what Health measured, once its workout is saved there. The sending to the server, when there is
// one, shows nothing.
struct SessionSummaryView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")

    let session: Session
    @Environment(LiveSessionStore.self) private var store
    @Environment(WorkoutRecorder.self) private var recorder
    @Environment(\.modelContext) private var context
    @Environment(\.units) private var units
    @State private var summary: SessionSummary?
    @State private var names: [String: String] = [:]
    @State private var rings: HKActivitySummary?
    @ScaledMetric(relativeTo: .body) private var ringsSide = 96.0

    var body: some View {
        let text = SetsText(units: units)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let summary {
                    stats(summary, text: text)
                    if !summary.records.isEmpty {
                        BeatenRecords(records: summary.records, names: names, text: text)
                    }
                }
                if let health = recorder.saved, health.sessionID == session.id {
                    healthCard(health)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button {
                store.isPresented = false
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(Color(.onAccent))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .task(id: session.id) {
            load()
        }
        // The rings once the workout is in Health.
        .task(id: recorder.saved?.sessionID == session.id) {
            guard recorder.saved?.sessionID == session.id else { return }
            rings = await recorder.todayActivity()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(.onAccent))
                .frame(width: 44, height: 44)
                .background(.tint, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout saved")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: "\(session.name) · \(session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .padding(.top, 24)
    }

    private func stats(_ summary: SessionSummary, text: SetsText) -> some View {
        let seconds = Int(summary.duration.rounded())
        let duration = Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
        return ThreeFigures(
            first: Figure(value: duration, label: Text("duration")),
            second: Figure(value: summary.setCount.formatted(), label: Text("sets")),
            third: Figure(value: text.volume(summary.volumeG), label: Text("volume"))
        )
        .sessionCard()
    }

    private func healthCard(_ health: HealthResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Health")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 14) {
                ActivityRings(summary: rings)
                    .frame(width: ringsSide, height: ringsSide)
                VStack(alignment: .leading, spacing: 6) {
                    if let kilocalories = health.activeKilocalories {
                        measure(Text("Active calories"), Text(verbatim: Measurement(value: kilocalories, unit: UnitEnergy.kilocalories)
                            .formatted(.measurement(width: .abbreviated, usage: .workout, numberFormatStyle: .number.precision(.fractionLength(0))))))
                    }
                    if let average = health.averageHeartRate, let maximum = health.maximumHeartRate {
                        measure(Text("Heart rate"), Text("\(Int(average.rounded())) avg · \(Int(maximum.rounded())) max"))
                    }
                }
                .font(.subheadline)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        }
    }

    private func measure(_ label: Text, _ value: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label
                .foregroundStyle(Color(.secondaryText))
            value
                .bold()
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func load() {
        do {
            let summary = try context.summary(of: session)
            let ids = summary.records.map(\.exerciseID)
            let exercises = try context.fetch(FetchDescriptor(predicate: Exercise.withIDs(ids)))
            names = Dictionary(exercises.map { ($0.id, $0.localizedName) }, uniquingKeysWith: { first, _ in first })
            self.summary = summary
        } catch {
            Self.logger.error("Cannot sum up the session: \(String(describing: error))")
        }
    }
}
