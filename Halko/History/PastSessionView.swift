import HalkoCore
import os
import SwiftData
import SwiftUI

// A session of the history, read only: its figures, the records beaten against the sessions before it, then each
// exercise with its sets in columns, as during a session. « … » deletes it, once confirmed.
struct PastSessionView: View {
    private struct Details {
        let summary: SessionSummary
        let exercises: [PastExercise]
        let byID: [String: Exercise]
    }

    private static let logger = Logger(subsystem: "com.zsr.halko", category: "history")

    let link: PastSessionLink
    @Query private var sessions: [Session]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var details: Details?
    @State private var confirmingDelete = false

    init(link: PastSessionLink) {
        self.link = link
        let id = link.sessionID
        _sessions = Query(filter: #Predicate<Session> { !$0.removed && $0.id == id })
    }

    var body: some View {
        let sets = SetsText(locale: locale)
        ScrollView {
            if let details {
                VStack(alignment: .leading, spacing: 18) {
                    ThreeFigures(
                        first: Figure(value: HistoryText(sets: sets).minutes(details.summary.duration), label: Text("duration")),
                        second: Figure(value: details.summary.setCount.formatted(), label: Text("sets")),
                        third: Figure(value: sets.volume(details.summary.volumeG), label: Text("volume"))
                    )
                    .sessionCard()
                    if !details.summary.records.isEmpty {
                        BeatenRecords(
                            records: details.summary.records,
                            names: details.byID.mapValues(\.localizedName),
                            text: sets
                        )
                    }
                    if !details.exercises.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Exercises")
                                .font(.title3.bold())
                                .accessibilityAddTraits(.isHeader)
                            ForEach(details.exercises) { group in
                                PastExerciseCard(
                                    group: group,
                                    exercise: details.byID[group.exerciseID],
                                    fields: FieldText(weightUnit: sets.weightUnit, distanceUnit: sets.distanceUnit, locale: locale)
                                )
                            }
                        }
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(sessions.first?.name ?? "")
        .navigationSubtitle(date)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More actions", systemImage: "ellipsis") {
                    Button("Delete the session", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                }
                // Asked where the menu was.
                .confirmationDialog("Delete this session?", isPresented: $confirmingDelete, titleVisibility: .hidden) {
                    Button("Delete the session", role: .destructive, action: delete)
                } message: {
                    Text("Its sets disappear from the history, the records and “Previous”. The session saved in Health stays.")
                }
            }
        }
        .task(id: link) {
            load()
        }
    }

    // "Thursday 6 November, 18:04".
    private var date: String {
        guard let startedAt = sessions.first?.startedAt else { return "" }
        let day = startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "\(day.prefix(1).uppercased())\(day.dropFirst()), \(startedAt.formatted(date: .omitted, time: .shortened))"
    }

    private func load() {
        guard let session = sessions.first else { return }
        do {
            let sets = try context.sets(of: session.id)
            let exercises = try context.fetch(FetchDescriptor(predicate: Exercise.withIDs(Array(Set(sets.map(\.exerciseID))))))
            details = Details(
                summary: try context.summary(of: session),
                exercises: PastExercise.exercises(of: sets),
                byID: Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            )
        } catch {
            Self.logger.error("Cannot read the session: \(String(describing: error))")
        }
    }

    private func delete() {
        do {
            try context.removeSession(id: link.sessionID)
            dismiss()
        } catch {
            Self.logger.error("Cannot delete the session: \(String(describing: error))")
        }
    }
}

// An exercise done: a tap on its name opens its page; its sets in columns, numbered as during a session.
private struct PastExerciseCard: View {
    let group: PastExercise
    let exercise: Exercise?
    let fields: FieldText

    private var type: ExerciseType {
        exercise?.exerciseType ?? .weightReps
    }

    private var metrics: [SetField] {
        type.metrics.map(SetField.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let exercise {
                NavigationLink(value: exercise) {
                    header(chevron: true)
                }
                .buttonStyle(.plain)
            } else {
                header(chevron: false)
            }
            columnTitles
            ForEach(group.sets) { set in
                row(set)
            }
        }
        .sessionCard()
    }

    private func header(chevron: Bool) -> some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(mediaID: exercise?.mediaIDs.first)
            Text(verbatim: exercise?.localizedName ?? String(localized: "Exercise"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.secondaryText))
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private var columnTitles: some View {
        HStack(spacing: 8) {
            Text("Set")
                .frame(width: 44)
            ForEach(metrics, id: \.self) { field in
                Text(verbatim: fields.columnTitle(field, type: type, perSide: group.perSide, long: false))
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption)
        .foregroundStyle(Color(.secondaryText))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func row(_ set: PastSet) -> some View {
        HStack(spacing: 8) {
            number(set)
                .frame(width: 44)
            ForEach(metrics, id: \.self) { field in
                let value = set.values[field].map { fields.boxText($0, of: field) } ?? "–"
                Text(verbatim: value)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(verbatim: "\(value) \(fields.columnTitle(field, type: type, perSide: group.perSide, long: true))"))
            }
        }
        .font(.body)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }

    // "2" for the second working set, "W" for a warm-up.
    private func number(_ set: PastSet) -> some View {
        Group {
            if set.isWarmup {
                Text("W")
                    .foregroundStyle(Color(.warmup))
                    .accessibilityLabel(Text("Warm-up \(set.number)"))
            } else {
                Text(verbatim: set.number.formatted())
                    .accessibilityLabel(Text("Set \(set.number)"))
            }
        }
        .fontWeight(.semibold)
    }
}
