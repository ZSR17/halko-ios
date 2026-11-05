import HalkoCore
import os
import SwiftData
import SwiftUI

// The end of a session once saved: its duration, working sets and load moved, and the exercises with a record beaten,
// worked out on the watch.
struct SessionSummaryView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")

    let session: Session
    let done: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @State private var summary: SessionSummary?
    @State private var recordNames: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(.onAccent))
                    .frame(width: 32, height: 32)
                    .background(.tint, in: .circle)
                    .accessibilityHidden(true)
                Text("Workout saved")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let summary {
                    Text(verbatim: line(summary))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(recordNames, id: \.self) { name in
                    Label {
                        Text("Record: \(name)")
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color(.warmup))
                    }
                    .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .bottomButton {
            Button(action: done) {
                Text("OK")
                    .frame(maxWidth: .infinity)
            }
            .buttonBorderShape(.capsule)
        }
        .task(id: session.id) {
            load()
        }
    }

    // "54:10 · 17 sets · 6,840 kg".
    private func line(_ summary: SessionSummary) -> String {
        let seconds = Int(summary.duration.rounded())
        let duration = Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
        let sets = String(localized: "\(summary.setCount) sets")
        return [duration, sets, SetsText(locale: locale).volume(summary.volumeG)].joined(separator: " · ")
    }

    private func load() {
        do {
            let summary = try context.summary(of: session)
            var ids: [String] = []
            for record in summary.records where !ids.contains(record.exerciseID) {
                ids.append(record.exerciseID)
            }
            let exercises = try context.fetch(FetchDescriptor(predicate: Exercise.withIDs(ids)))
            let names = Dictionary(exercises.map { ($0.id, $0.localizedName) }, uniquingKeysWith: { first, _ in first })
            recordNames = ids.map { names[$0] ?? String(localized: "Exercise") }
            self.summary = summary
        } catch {
            Self.logger.error("Cannot sum up the session: \(String(describing: error))")
        }
    }
}
