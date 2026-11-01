import HalkoCore
import os
import SwiftData
import SwiftUI

// The end of a session once saved: its duration, working sets and load moved, and the records beaten. Worked out on
// the device; the sending to the server, when there is one, shows nothing.
struct SessionSummaryView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")

    let session: Session
    @Environment(LiveSessionStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @State private var summary: SessionSummary?
    @State private var names: [String: String] = [:]

    var body: some View {
        let text = SetsText(locale: locale)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let summary {
                    stats(summary, text: text)
                    if !summary.records.isEmpty {
                        records(summary, text: text)
                    }
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
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                stat(duration, Text("duration"))
                Spacer()
                stat(summary.setCount.formatted(), Text("sets"))
                Spacer()
                stat(text.volume(summary.volumeG), Text("volume"))
            }
            VStack(alignment: .leading, spacing: 12) {
                stat(duration, Text("duration"))
                stat(summary.setCount.formatted(), Text("sets"))
                stat(text.volume(summary.volumeG), Text("volume"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    private func stat(_ value: String, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.title2.bold())
                .monospacedDigit()
            label
                .font(.caption)
                .foregroundStyle(Color(.secondaryText))
        }
        .accessibilityElement(children: .combine)
    }

    private func records(_ summary: SessionSummary, text: SetsText) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Records beaten")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(summary.records, id: \.self) { record in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "trophy")
                            .foregroundStyle(Color(.warmup))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: names[record.exerciseID] ?? String(localized: "Exercise"))
                                .font(.headline)
                            Text(verbatim: beaten(record, text: text))
                                .font(.subheadline)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        }
    }

    // "Estimated 1RM 101.3 kg (before 98.5 kg)".
    private func beaten(_ record: SessionSummary.BeatenRecord, text: SetsText) -> String {
        let kind = String(localized: record.kind.name)
        let value = text.record(ExerciseRecord(kind: record.kind, value: record.value))
        let before = text.record(ExerciseRecord(kind: record.kind, value: record.before))
        return String(localized: "\(kind) \(value) (before \(before))")
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
