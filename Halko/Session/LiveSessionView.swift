import HalkoCore
import os
import SwiftData
import SwiftUI

// A box of the session that has the keyboard: a value of a set, by step key.
enum LiveField: Hashable {
    case value(String, SetField)
}

// The session in progress: every exercise one under the other with its sets, and at the bottom the set to do (its
// values and Validate), which becomes the rest once validated. Everything is written on the device first.
struct LiveSessionView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "session")

    let state: LiveState
    let finished: (Session) -> Void
    @Environment(LiveSessionStore.self) private var store
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
    @State private var finishing = false
    @State private var discarding = false
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
                        ForEach(Array(state.plan.enumerated()), id: \.element.itemID) { index, item in
                            LiveExerciseView(
                                index: index,
                                table: table,
                                folded: table.isFinished(index) && !unfolded.contains(item.itemID),
                                unfold: { unfold(item.itemID) },
                                focus: $focus
                            )
                            .id(item.itemID)
                        }
                    }
                    .padding()
                }
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
                panel(table)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbar(table)
            }
        }
        .confirmationDialog("Finish the session?", isPresented: $finishing, titleVisibility: .visible) {
            if !sets.isEmpty {
                Button("Save the session") {
                    finish()
                }
            }
            Button("Discard the session", role: .destructive) {
                discarding = true
            }
            Button("Continue the session", role: .cancel) {}
        } message: {
            Text("\(sets.count) of \(table.plan.steps.count) sets done.")
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
        // The end of the rest: the set panel comes back.
        .task(id: state.restEndsAt) {
            guard let end = state.restEndsAt else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            } catch {
                return
            }
            store.change { $0.endRest() }
        }
        .sensoryFeedback(.success, trigger: state.restEndsAt) { old, new in
            old != nil && new == nil
        }
        // Finished or deleted on another device: nothing left to do here.
        .task(id: sessions.first.map { $0.removed || $0.endedAt != nil } ?? false) {
            // Finished here, the summary follows: only a session still held is let go.
            guard let session = sessions.first, session.removed || session.endedAt != nil,
                  store.state?.sessionID == session.id else { return }
            store.set(nil)
            store.isPresented = false
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
            text: SetsText(locale: locale),
            actions: LiveActions(
                validate: validate,
                undo: undo,
                correct: correct,
                edit: { key, values in edits[key] = values },
                addSet: { item in change { try context.addSet(&$0, item: item, unit: .preferred(for: locale)) } },
                deleteSet: deleteSet,
                deleteExercise: { item in change { try context.deleteExercise(&$0, item: item) } }
            )
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
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                focus = nil
            }
        }
    }

    @ViewBuilder
    private func panel(_ table: LiveTable) -> some View {
        if table.allDone {
            AllDonePanel {
                finishing = true
            }
        } else if let end = state.restEndsAt {
            RestPanel(end: end, totalS: state.restTotalS, next: table.nextText) {
                store.change { $0.shortenRest() }
            } skip: {
                store.change { $0.endRest() }
            } lengthen: {
                store.change { $0.lengthenRest() }
            }
        } else if let step = table.step {
            SetPanel(table: table, step: step)
        }
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

    // The values typed for the sets after it move up with them.
    private func deleteSet(_ item: Int, _ set: Int) {
        guard state.canDeleteSet(of: item) else { return }
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
                store.set(nil)
                store.isPresented = false
                return
            }
            finished(session)
            store.set(nil)
        } catch {
            Self.logger.error("Cannot finish the session: \(String(describing: error))")
        }
    }

    private func discard() {
        do {
            try context.discardSession(state)
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

// What the session's views do.
struct LiveActions {
    let validate: () -> Void
    let undo: (_ item: Int, _ set: Int) -> Void
    let correct: (_ item: Int, _ set: Int, SetValues) -> Void
    // New values of a set not done yet, by step key.
    let edit: (String, SetValues) -> Void
    let addSet: (_ item: Int) -> Void
    let deleteSet: (_ item: Int, _ set: Int) -> Void
    let deleteExercise: (_ item: Int) -> Void
}

// Everything the views of the session read, worked out once for each change.
struct LiveTable {
    let state: LiveState
    let plan: LivePlan
    // Sets done, by step key.
    let logged: [String: SetLog]
    let previous: [String: [Int: SetValues]]
    let edits: [String: SetValues]
    let exercises: [String: Exercise]
    let fields: FieldText
    let text: SetsText
    let actions: LiveActions

    var step: LiveStep? {
        plan.steps.indices.contains(state.cursor) ? plan.steps[state.cursor] : nil
    }

    var allDone: Bool {
        !plan.steps.isEmpty && plan.steps.allSatisfy { logged[plan.key($0)] != nil }
    }

    func exercise(_ item: Int) -> Exercise? {
        exercises[plan.items[item].exerciseID]
    }

    func name(_ item: Int) -> String {
        exercise(item)?.localizedName ?? String(localized: "Exercise")
    }

    // Every set of the exercise is done (it has one at least).
    func isFinished(_ item: Int) -> Bool {
        let count = plan.setCount(item)
        return count > 0 && (0..<count).allSatisfy { logged[LivePlan.key(plan.items[item].itemID, $0)] != nil }
    }

    // What a set not done is offered with: last time's values or the plan, raised to what earlier sets reached.
    func proposed(_ item: Int, set: Int) -> SetValues {
        plan.proposed(item, set: set, previous: previous[plan.items[item].exerciseID] ?? [:], bumps: state.bumps, unit: fields.weightUnit)
    }

    // What the current set started with: its values when done, else what it is offered with.
    func startedFrom(_ step: LiveStep) -> SetValues {
        logged[plan.key(step)].map(SetValues.init) ?? proposed(step.item, set: step.set)
    }

    func draft(_ step: LiveStep) -> SetValues {
        edits[plan.key(step)] ?? startedFrom(step)
    }

    // The values a set shows: done, typed, or offered (an increase typed on the current set shows on the next sets of
    // the exercise straight away).
    func values(_ item: Int, set: Int) -> SetValues {
        let key = LivePlan.key(plan.items[item].itemID, set)
        if let log = logged[key] {
            return SetValues(log)
        }
        if let edited = edits[key] {
            return edited
        }
        let offered = proposed(item, set: set)
        guard let step, step.item == item, set > step.set else { return offered }
        return offered.raised(to: draft(step).increase(over: startedFrom(step)))
    }

    // "2" for the second working set, "W" for a warm-up.
    func number(_ item: Int, set: Int) -> Text {
        plan.target(item, set: set).kind == .warmup ? Text("W") : Text(verbatim: plan.items[item].workingNumber(set).formatted())
    }

    // As VoiceOver reads it: "Set 2", "Warm-up 1".
    func spokenNumber(_ item: Int, set: Int) -> String {
        if plan.target(item, set: set).kind == .warmup {
            let warmup = (0...set).count(where: { plan.target(item, set: $0).kind == .warmup })
            return String(localized: "Warm-up \(warmup)")
        }
        return String(localized: "Set \(plan.items[item].workingNumber(set))")
    }

    // The sets of an exercise, by index (warm-ups included).
    func setNumbers(_ item: Int) -> [Int] {
        Array(0..<plan.setCount(item))
    }

    func workingCount(_ item: Int) -> Int {
        (0..<plan.setCount(item)).count(where: { plan.target(item, set: $0).kind != .warmup })
    }

    // A set as on the page of a workout: "80 × 8".
    func setText(_ item: Int, values: SetValues) -> String {
        let target = SetTarget(kind: .normal, reps: values.reps, weightG: values.weightG, durationS: values.durationS, distanceM: values.distanceM)
        return text.set(target, type: plan.items[item].exerciseType)
    }

    // What comes after the rest: "Set 3 · 80 × 8", or the next exercise.
    var nextText: String? {
        guard let step else { return nil }
        let values = setText(step.item, values: draft(step))
        if plan.target(step.item, set: step.set).kind == .warmup {
            return String(localized: "\(name(step.item)) · warm-up · \(values)")
        }
        return String(localized: "\(name(step.item)) · set \(plan.items[step.item].workingNumber(step.set)) · \(values)")
    }

    func metrics(_ item: Int) -> [SetField] {
        plan.items[item].exerciseType.metrics.map(SetField.init)
    }

    func columnTitle(_ field: SetField, item: Int, long: Bool) -> String {
        fields.columnTitle(field, type: plan.items[item].exerciseType, perSide: plan.items[item].unilateral, long: long)
    }
}
