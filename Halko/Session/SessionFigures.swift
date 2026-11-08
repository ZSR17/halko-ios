import HalkoCore
import SwiftUI

// What the end of a session and the History tab show alike.

struct Figure {
    let value: String
    let label: Text
}

// Three figures side by side, or one under the other when they don't fit.
struct ThreeFigures: View {
    let first: Figure
    let second: Figure
    let third: Figure

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                figure(first)
                Spacer()
                figure(second)
                Spacer()
                figure(third)
            }
            VStack(alignment: .leading, spacing: 12) {
                figure(first)
                figure(second)
                figure(third)
            }
        }
    }

    private func figure(_ figure: Figure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: figure.value)
                .font(.title2.bold())
                .monospacedDigit()
            figure.label
                .font(.caption)
                .foregroundStyle(Color(.secondaryText))
        }
        .accessibilityElement(children: .combine)
    }
}

struct BeatenRecords: View {
    let records: [SessionSummary.BeatenRecord]
    let names: [String: String]
    let text: SetsText

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Records beaten")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(records, id: \.self) { record in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "trophy")
                            .foregroundStyle(Color(.warmup))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: names[record.exerciseID] ?? String(localized: "Exercise"))
                                .font(.headline)
                            Text(verbatim: beaten(record))
                                .font(.subheadline)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .sessionCard()
        }
    }

    // "Estimated 1RM 101.3 kg (before 98.5 kg)".
    private func beaten(_ record: SessionSummary.BeatenRecord) -> String {
        let kind = String(localized: record.kind.name)
        let value = text.record(ExerciseRecord(kind: record.kind, value: record.value))
        let before = text.record(ExerciseRecord(kind: record.kind, value: record.before))
        return String(localized: "\(kind) \(value) (before \(before))")
    }
}

extension View {
    func sessionCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}
