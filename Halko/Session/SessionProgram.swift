import HalkoCore
import SwiftData
import SwiftUI

// Beside the session, on a wide screen (the iPhone Duo open): the exercises of the session, done or to come, then the
// last sessions of the exercise being done. Read from what the session already has, nothing more to load.
struct SessionProgram: View {
    let table: LiveTable

    var body: some View {
        let current = table.step?.item
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Program")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 4)
                ForEach(Array(table.plan.items.enumerated()), id: \.element.itemID) { index, item in
                    row(index, item: item, isCurrent: index == current)
                }
                if let current {
                    LastSessions(table: table, item: current)
                        .id(table.plan.items[current].exerciseID)
                        .padding(.top, 24)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func row(_ index: Int, item: PlanItem, isCurrent: Bool) -> some View {
        let group = item.supersetGroup
        let opensSuperset = group != nil && (index == 0 || table.plan.items[index - 1].supersetGroup != group)
        let finished = table.isFinished(index)
        return VStack(alignment: .leading, spacing: 6) {
            if opensSuperset {
                Tag(Text("Superset · no rest in between"), color: Color(.superset))
                    .padding(.top, 6)
            }
            HStack(spacing: 10) {
                Image(systemName: finished ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(finished || isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondaryText)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: table.name(index))
                        .font(isCurrent ? .body.weight(.semibold) : .body)
                    Text("\(table.workingDone(index)) / \(table.workingCount(index)) sets")
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryText))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isCurrent ? Color(.secondarySystemGroupedBackground) : .clear, in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .padding(.leading, group == nil ? 0 : 12)
            .supersetBar(group != nil)
        }
    }
}

// The last 3 sessions of an exercise, and its estimated 1RM record.
private struct LastSessions: View {
    let table: LiveTable
    let item: Int
    @Query private var sets: [SetLog]

    init(table: LiveTable, item: Int) {
        self.table = table
        self.item = item
        let exerciseID = table.plan.items[item].exerciseID
        let sessionID = table.state.sessionID
        _sets = Query(
            filter: #Predicate<SetLog> { !$0.removed && $0.exerciseID == exerciseID && $0.sessionID != sessionID },
            sort: \SetLog.completedAt,
            order: .reverse
        )
    }

    var body: some View {
        let sessions = lastSessions
        let oneRepMax = ExerciseRecords(sets: sets, type: table.plan.items[item].exerciseType).records.first { $0.kind == .oneRepMax }
        VStack(alignment: .leading, spacing: 0) {
            Text("\(table.name(item)) · history")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 6)
            if sessions.isEmpty {
                Text("No session yet with this exercise.")
                    .foregroundStyle(Color(.secondaryText))
            }
            ForEach(sessions, id: \.[0].sessionID) { done in
                session(done)
                Divider()
            }
            if let oneRepMax {
                HStack(spacing: 6) {
                    Text(oneRepMax.kind.name)
                        .foregroundStyle(Color(.secondaryText))
                    Text(verbatim: table.text.record(oneRepMax))
                        .bold()
                }
                .font(.subheadline)
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // The sets of each session, the latest session first, its sets in the order done.
    private var lastSessions: [[SetLog]] {
        var order: [String] = []
        var bySession: [String: [SetLog]] = [:]
        for set in sets where set.kind != .warmup {
            if bySession[set.sessionID] == nil {
                guard order.count < 3 else { continue }
                order.append(set.sessionID)
            }
            bySession[set.sessionID, default: []].insert(set, at: 0)
        }
        return order.compactMap { bySession[$0] }
    }

    private func session(_ done: [SetLog]) -> some View {
        let date = Text(done[0].completedAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let values = Text(verbatim: done.map { table.setText(item, values: SetValues($0)) }.joined(separator: " · "))
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                date
                Spacer(minLength: 0)
                values
                    .foregroundStyle(Color(.secondaryText))
            }
            .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                date
                values
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .font(.subheadline)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
