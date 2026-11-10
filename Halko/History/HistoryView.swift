import HalkoCore
import os
import SwiftData
import SwiftUI

// The History tab: this week's figures, then the sessions finished by month, or the progress of an exercise.
struct HistoryView: View {
    private enum Page {
        case sessions, progress
    }

    private static let logger = Logger(subsystem: "com.zsr.halko", category: "history")

    @Query(filter: #Predicate<Session> { !$0.removed && $0.endedAt != nil }) private var sessions: [Session]
    @Environment(\.modelContext) private var context
    @Environment(\.units) private var units
    @State private var history: SessionHistory?
    @State private var page = Page.sessions

    var body: some View {
        let text = HistoryText(sets: SetsText(units: units))
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let history {
                    week(history.week, text: text)
                    Picker("Display", selection: $page) {
                        Text("Sessions")
                            .tag(Page.sessions)
                        Text("Progress")
                            .tag(Page.progress)
                    }
                    .pickerStyle(.segmented)
                    switch page {
                    case .sessions:
                        if history.isEmpty {
                            NoSessions()
                                .padding(.top, 60)
                        } else {
                            SessionMonths(months: history.months, text: text)
                        }
                    case .progress:
                        ProgressPage(history: history, text: text)
                    }
                }
            }
            .padding([.horizontal, .bottom])
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("History")
        // Also each time the tab comes back: a new week, an exercise renamed.
        .task(id: sessions.map(\.updatedAt)) {
            do {
                history = try context.sessionHistory()
            } catch {
                Self.logger.error("Cannot read the history: \(String(describing: error))")
            }
        }
        .navigationDestination(for: PastSessionLink.self) { link in
            PastSessionView(link: link)
        }
        .navigationDestination(for: Exercise.self) { exercise in
            ExerciseView(exercise: exercise)
        }
    }

    private func week(_ week: HistoryWeek, text: HistoryText) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.secondaryText))
                .accessibilityAddTraits(.isHeader)
            ThreeFigures(
                first: Figure(value: week.sessionCount.formatted(), label: sessionsLabel(week.sessionCount)),
                second: Figure(value: text.tonnage(week.volumeG), label: Text("lifted")),
                third: Figure(value: text.minutes(week.duration), label: Text("of training"))
            )
        }
        .sessionCard()
    }

    // Beside a number shown apart, so without the plural of the catalog, which needs the number in its text. In French,
    // no session is singular.
    private func sessionsLabel(_ count: Int) -> Text {
        switch count {
        case 0: Text("sessions (none)")
        case 1: Text("session")
        default: Text("sessions (several)")
        }
    }
}

// A session of the history to open.
struct PastSessionLink: Hashable {
    let sessionID: String
}

// The months: the latest unfolded, the others with a tap, so that a long history stays short to scroll.
private struct SessionMonths: View {
    let months: [HistoryMonth]
    let text: HistoryText
    // Those not as they start: the first one unfolded, the others folded.
    @State private var changed: Set<String> = []

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(months) { month in
                let isOpen = (month.id == months.first?.id) != changed.contains(month.id)
                MonthHeader(month: month, isOpen: isOpen, text: text) {
                    if changed.remove(month.id) == nil {
                        changed.insert(month.id)
                    }
                }
                if isOpen {
                    ForEach(month.sessions) { session in
                        NavigationLink(value: PastSessionLink(sessionID: session.id)) {
                            PastSessionRow(session: session, text: text)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct MonthHeader: View {
    let month: HistoryMonth
    let isOpen: Bool
    let text: HistoryText
    let toggle: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: toggle) {
            // The figures under the month when the text is too large for both on a line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    title
                    figures
                    chevron
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        title
                        chevron
                    }
                    figures
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        .accessibilityAddTraits(.isHeader)
    }

    private var title: some View {
        Text(verbatim: month.date.formatted(.dateTime.month(.wide).year()).capitalized(with: locale))
            .font(.headline)
            .foregroundStyle(Color(.label))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var figures: some View {
        Text(verbatim: details)
            .font(.footnote)
            .foregroundStyle(Color(.secondaryText))
    }

    private var chevron: some View {
        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(.secondaryText))
            .accessibilityHidden(true)
    }

    // "3 sessions · 14.2 t".
    private var details: String {
        let sessions = String(localized: "\(month.sessions.count) sessions")
        return month.volumeG > 0 ? "\(sessions) · \(text.tonnage(month.volumeG))" : sessions
    }
}

private struct PastSessionRow: View {
    let session: HistorySession
    let text: HistoryText
    @ScaledMetric(relativeTo: .title2) private var dayWidth = 44.0

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(verbatim: session.startedAt.formatted(.dateTime.day()))
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(verbatim: session.startedAt.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryText))
            }
            .frame(minWidth: dayWidth)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide))))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: session.name)
                    .font(.headline)
                Text(verbatim: text.details(of: session))
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryText))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if session.beatRecord {
                Image(systemName: "trophy")
                    .foregroundStyle(Color(.warmup))
                    .accessibilityLabel(Text("Record beaten"))
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.secondaryText))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct NoSessions: View {
    var body: some View {
        // The description in a darker grey than the system's, for a contrast of 4.5:1.
        ContentUnavailableView {
            Label("No sessions", systemImage: "clock")
        } description: {
            Text("Finished sessions will appear here.")
                .foregroundStyle(Color(.secondaryText))
        }
    }
}
