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

    // "Max weight 85 kg (before 82.5 kg)".
    private func beaten(_ record: SessionSummary.BeatenRecord) -> String {
        let history = HistoryText(sets: text)
        let kind = String(localized: record.measure.name)
        let value = history.value(record.value, of: record.measure)
        let before = history.value(record.before, of: record.measure)
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
