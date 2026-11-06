import HalkoCore
import os
import SwiftData
import SwiftUI

// A box of the session that has the keyboard: a value of a set, by step key.
nonisolated enum LiveField: Hashable, Sendable {
    case value(String, SetField)
}

// The session in progress: every exercise one under the other with its sets, and at the bottom the set to do (its
// values and Validate), which becomes the rest once validated. Everything is written on the device first.
struct LiveSessionView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")

    let state: LiveState
    let finished: (Session) -> Void
    @Environment(LiveSessionStore.self) private var store
    @Environment(WorkoutRecorder.self) private var recorder
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Query private var sessions: [Session]
    @Query private var sets: [SetLog]
    @Query private var exercises: [Exercise]
    // Values changed on sets not done yet, by step key: kept until the set is validated.
    @State private var edits: [String: SetValues] = [:]
    // Last time's sets of each exercise, by exercise id.
    @State private var previous: [String: [Int: SetValues]] = [:]
    // Exercises done, opened again to correct a set, until the set to do changes.
    @State private var unfolded: Set<String> = []
    // Asked from Finish at the top, or from the panel once every set is done.
    @State private var finishing = false
    @State private var finishingAllDone = false
    @State private var discarding = false
    // The bottom of the screen not to draw in: the home indicator's, or the keyboard's.
    @State private var bottomInset: CGFloat = 0
    @FocusState private var focus: LiveField?

    init(state: LiveState, finished: @escaping (Session) -> Void) {
        self.state = state
        self.finished = finished
        let id = state.sessionID
        _sessions = Query(filter: #Predicate<Session> { $0.id == id })
        _sets = Query(filter: #Predicate<SetLog> { !$0.removed && $0.sessionID == id }, sort: \SetLog.completedAt)
        _exercises = Query(filter: Exercise.withIDs(state.plan.map(\.exerciseID)))
    }

    var body: some View {
        let table = self.table
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let heartRate = recorder.heartRate {
                            HeartRateChip(bpm: heartRate)
                        }
                        ForEach(Array(state.plan.enumerated()), id: \.element.itemID) { index, item in
                            LiveExerciseView(
                                index: index,
                                table: table,
                                actions: actions,
                                folded: table.isFinished(index) && !unfolded.contains(item.itemID),
                                unfold: { unfold(item.itemID) },
                                focus: $focus
                            )
                            .id(item.itemID)
                        }
                    }
                    .padding()
                }
                .scrollingToFocus(focus, in: proxy)
                // Pulled down, the sets put the keyboard away too.
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: state.cursor) {
                    unfolded = []
                }
                .onChange(of: table.step?.item) { _, item in
                    guard let item else { return }
                    withAnimation {
                        proxy.scrollTo(state.plan[item].itemID, anchor: .top)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .trailing, spacing: 8) {
                    // While a value is typed: a button above the panel puts the keyboard away.
                    if focus != nil {
                        Button {
                            focus = nil
                        } label: {
                            Label("Hide the keyboard", systemImage: "keyboard.chevron.compact.down")
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .padding(.trailing)
                    }
                    panel(table)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { inset in
                bottomInset = inset
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbar(table)
            }
        }
        .alert("Discard the session?", isPresented: $discarding) {
            Button("Discard", role: .destructive) {
                discard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sets done in this session will be deleted.")
        }
        .task(id: state.sessionID) {
            loadPrevious()
        }
    }

    private var table: LiveTable {
        LiveTable(
            state: state,
            plan: state.livePlan,
            logged: Dictionary(sets.compactMap { set in set.workoutItemID.map { (LivePlan.key($0, set.setIndex), set) } }, uniquingKeysWith: { first, _ in first }),
            previous: previous,
            edits: edits,
            exercises: Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            fields: FieldText(weightUnit: .preferred(for: locale), distanceUnit: .preferred(for: locale), locale: locale),
            text: SetsText(locale: locale)
        )
    }

    private var actions: LiveActions {
        LiveActions(
            validate: validate,
            startTimer: startTimer,
            undo: undo,
            correct: correct,
            edit: { key, values in edits[key] = values },
            addSet: { item in change { try context.addSet(&$0, item: item, unit: .preferred(for: locale)) } },
            deleteSet: deleteSet,
            deleteExercise: { item in change { try context.deleteExercise(&$0, item: item) } }
        )
    }

    // MARK: Bars

    @ToolbarContentBuilder
    private func toolbar(_ table: LiveTable) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                store.isPresented = false
            } label: {
                Label("Workouts", systemImage: "chevron.backward")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityHint(Text("The session goes on."))
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                if let session = sessions.first {
                    Text(timerInterval: session.startedAt...Date.distantFuture, countsDown: false)
                        .font(.headline)
                        .monospacedDigit()
                }
                if !state.plan.isEmpty {
                    Text("Exercise \((table.step?.item ?? 0) + 1) of \(state.plan.count)")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryText))
                }
            }
            .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Finish") {
                finishing = true
            }
            .foregroundStyle(.red)
            .finishDialog(isPresented: $finishing, setsDone: sets.count, of: table.plan.steps.count, save: finish) {
                discarding = true
            }
        }
    }

    @ViewBuilder
    private func panel(_ table: LiveTable) -> some View {
        if table.allDone {
            AllDonePanel(bottomPadding: panelBottomPadding) {
                finishingAllDone = true
            }
            .finishDialog(isPresented: $finishingAllDone, setsDone: sets.count, of: table.plan.steps.count, save: finish) {
                discarding = true
            }
        } else if let timer = table.timer, let step = table.step {
            TimerPanel(table: table, actions: actions, step: step, timer: timer, bottomPadding: panelBottomPadding) {
                store.change { $0.beginHolding() }
            } cancel: {
                store.change { $0.setTimer = nil }
            } stop: {
                change { try context.stopTimer(&$0) }
            }
        } else if state.restEndsAt != nil || table.step != nil {
            SetOrRestPanel(
                table: table,
                actions: actions,
                step: table.step,
                restEnd: state.restEndsAt,
                restTotalS: state.restTotalS,
                bottomPadding: panelBottomPadding
            ) {
                store.change { $0.shortenRest() }
            } skip: {
                store.change { $0.endRest() }
            } lengthen: {
                store.change { $0.lengthenRest() }
            }
        }
    }

    // Above the home indicator, the panel goes down into its area, a small margin above the edge of the screen; above
    // the keyboard, or on a screen without a home indicator, it keeps a margin of its own.
    private var panelBottomPadding: CGFloat {
        (1...50).contains(bottomInset) ? 20 - bottomInset : 12
    }

    // MARK: Actions

    private func validate() {
        let table = self.table
        guard let step = table.step else { return }
        let key = table.plan.key(step)
        let values = table.draft(step)
        let startedFrom = table.startedFrom(step)
        let index = state.cursor
        focus = nil
        change { try context.logSet(&$0, step: index, values: values, startedFrom: startedFrom) }
        edits[key] = nil
    }

    private func startTimer() {
        let table = self.table
        guard let step = table.step else { return }
        focus = nil
        store.change {
            $0.startTimer(
                stepKey: table.plan.key(step),
                values: table.draft(step),
                startedFrom: table.startedFrom(step),
                sidesPauseS: table.plan.items[step.item].sidesPauseS,
                settings: SetTimerSettings(defaults: .standard)
            )
        }
    }

    // A set validated by mistake: to do again, with the values it had.
    private func undo(_ item: Int, _ set: Int) {
        let key = LivePlan.key(state.plan[item].itemID, set)
        if let log = table.logged[key] {
            edits[key] = SetValues(log)
        }
        change { try context.unlogSet(&$0, item: item, set: set, unit: .preferred(for: locale)) }
    }

    // A set done, changed in its boxes: kept at once, without a new rest.
    private func correct(_ item: Int, _ set: Int, _ values: SetValues) {
        guard let index = state.livePlan.stepIndex(item: item, set: set) else { return }
        change { try context.logSet(&$0, step: index, values: values) }
    }

    // The values typed for the sets after it move up with them. The only set of an exercise: the exercise goes.
    private func deleteSet(_ item: Int, _ set: Int) {
        guard state.canDeleteSet(of: item) else {
            change { try context.deleteExercise(&$0, item: item) }
            return
        }
        let itemID = state.plan[item].itemID
        let count = state.plan[item].targets.count
        change { try context.deleteSet(&$0, item: item, set: set) }
        for index in set..<count {
            edits[LivePlan.key(itemID, index)] = index + 1 < count ? edits[LivePlan.key(itemID, index + 1)] : nil
        }
    }

    private func unfold(_ itemID: String) {
        withAnimation {
            _ = unfolded.insert(itemID)
        }
    }

    private func finish() {
        do {
            guard let session = try context.finishSession(state) else {
                recorder.discard()
                store.set(nil)
                store.isPresented = false
                return
            }
            recorder.finish(at: session.endedAt ?? .now)
            finished(session)
            store.set(nil)
        } catch {
            Self.logger.error("Cannot finish the session: \(String(describing: error))")
        }
    }

    private func discard() {
        do {
            try context.discardSession(state)
            recorder.discard()
            store.set(nil)
            store.isPresented = false
        } catch {
            Self.logger.error("Cannot discard the session: \(String(describing: error))")
        }
    }

    private func loadPrevious() {
        do {
            var found: [String: [Int: SetValues]] = [:]
            for exerciseID in Set(state.plan.map(\.exerciseID)) {
                found[exerciseID] = try context.previousPerformance(of: exerciseID, excluding: state.sessionID)
            }
            previous = found
        } catch {
            Self.logger.error("Cannot read the last sessions: \(String(describing: error))")
        }
    }

    private func change(_ body: (inout LiveState) throws -> Void) {
        do {
            try store.change(body)
        } catch {
            Self.logger.error("Cannot change the session: \(String(describing: error))")
        }
    }
}

private extension View {
    // « Finish the session? »: save it (once a set is done), discard it, or go on; shown where it was asked from.
    func finishDialog(isPresented: Binding<Bool>, setsDone: Int, of total: Int, save: @escaping () -> Void, discard: @escaping () -> Void) -> some View {
        confirmationDialog("Finish the session?", isPresented: isPresented, titleVisibility: .visible) {
            if setsDone > 0 {
                Button("Save the session", action: save)
            }
            Button("Discard the session", role: .destructive, action: discard)
            Button("Continue the session", role: .cancel) {}
        } message: {
            Text("\(setsDone) of \(total) sets done.")
        }
    }
}

// What the session's views do.
struct LiveActions {
    let validate: () -> Void
    let startTimer: () -> Void
    let undo: (_ item: Int, _ set: Int) -> Void
    let correct: (_ item: Int, _ set: Int, SetValues) -> Void
    // New values of a set not done yet, by step key.
    let edit: (String, SetValues) -> Void
    let addSet: (_ item: Int) -> Void
    let deleteSet: (_ item: Int, _ set: Int) -> Void
    let deleteExercise: (_ item: Int) -> Void
}

// The heart rate measured by a watch or a sensor: absent without one.
private struct HeartRateChip: View {
    let bpm: Double

    var body: some View {
        let value = Int(bpm.rounded())
        Label {
            Text("\(value) bpm")
                .monospacedDigit()
        } icon: {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate"))
        .accessibilityValue(Text("\(value) beats per minute"))
    }
}
