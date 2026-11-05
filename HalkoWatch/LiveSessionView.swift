import HalkoCore
import os
import SwiftData
import SwiftUI
import WatchKit

// The session in progress: the set to do, which becomes the rest once validated, and swiped aside, what is measured.
// Everything is written on the watch first; it needs neither the iPhone nor the network.
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
    @State private var finishing = false
    @State private var discarding = false

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
        TabView {
            work(table)
            MetricsPage(table: table, session: sessions.first) {
                finishing = true
            }
        }
        .tabViewStyle(.page)
        .confirmationDialog("Finish the session?", isPresented: $finishing, titleVisibility: .visible) {
            if !sets.isEmpty {
                Button("Save the session", action: finish)
            }
            Button("Discard the session", role: .destructive) {
                discarding = true
            }
        } message: {
            Text("\(sets.count) of \(table.plan.steps.count) sets done.")
        }
        .alert("Discard the session?", isPresented: $discarding) {
            Button("Discard", role: .destructive, action: discard)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sets done in this session will be deleted.")
        }
        .task(id: state.sessionID) {
            loadPrevious()
        }
        .task(id: RestAlarm(end: state.restEndsAt, recording: recorder.isRecording)) {
            await waitForTheEndOfRest(next: table.nextText)
        }
    }

    @ViewBuilder
    private func work(_ table: LiveTable) -> some View {
        if table.allDone {
            AllDonePage(session: sessions.first) {
                finishing = true
            }
        } else if let end = state.restEndsAt {
            RestPage(table: table, end: end, totalS: state.restTotalS) {
                store.change { $0.shortenRest() }
            } skip: {
                store.change { $0.endRest() }
            } lengthen: {
                store.change { $0.lengthenRest() }
            }
        } else if let step = table.step {
            SetPage(table: table, step: step, session: sessions.first) { values in
                edits[table.plan.key(step)] = values
            } validate: {
                validate(table, step)
            }
            // Another set starts from its first box.
            .id(table.plan.key(step))
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

    // The end of the rest: a vibration while the app runs (a workout of Health keeps it running with the wrist down);
    // without one, a notification takes over when the watch puts the app to sleep.
    private func waitForTheEndOfRest(next: String?) async {
        let end = state.restEndsAt
        await RestAlert.schedule(recorder.isRecording ? nil : end.map { RestAlert.Request(end: $0, body: next ?? "") })
        guard let end else { return }
        try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
        guard !Task.isCancelled else { return }
        // Not for a rest long over, when the app comes back.
        if end.timeIntervalSinceNow > -10 {
            WKInterfaceDevice.current().play(.notification)
        }
        store.change { $0.endRest() }
    }

    private func validate(_ table: LiveTable, _ step: LiveStep) {
        let key = table.plan.key(step)
        let values = table.draft(step)
        let startedFrom = table.startedFrom(step)
        let index = state.cursor
        do {
            try store.change { try context.logSet(&$0, step: index, values: values, startedFrom: startedFrom) }
            edits[key] = nil
        } catch {
            Self.logger.error("Cannot change the session: \(String(describing: error))")
        }
    }

    private func finish() {
        do {
            let session = try context.finishSession(state)
            if let session {
                recorder.finish(at: session.endedAt ?? .now)
                finished(session)
            } else {
                recorder.discard()
            }
            leave()
        } catch {
            Self.logger.error("Cannot finish the session: \(String(describing: error))")
        }
    }

    private func discard() {
        do {
            try context.discardSession(state)
            recorder.discard()
            leave()
        } catch {
            Self.logger.error("Cannot discard the session: \(String(describing: error))")
        }
    }

    private func leave() {
        store.set(nil)
        Task {
            await RestAlert.schedule(nil)
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
}

// What the alarm of the end of the rest depends on.
private struct RestAlarm: Equatable {
    let end: Date?
    let recording: Bool
}

extension LiveTable {
    // "Set 2 / 4", "Warm-up 1 / 4".
    func position(_ step: LiveStep) -> String {
        let item = plan.items[step.item]
        if step.target.kind == .warmup {
            let number = item.targets.prefix(step.set + 1).count(where: { $0.kind == .warmup })
            let total = item.targets.count(where: { $0.kind == .warmup })
            return String(localized: "Warm-up \(number) / \(total)")
        }
        return String(localized: "Set \(item.workingNumber(step.set)) / \(workingCount(step.item))")
    }

    // The working sets done.
    var workingSetsDone: Int {
        logged.values.count(where: { $0.kind != .warmup })
    }

    // The next exercise after the set to do.
    var nextExercise: String? {
        guard let step else { return nil }
        return plan.steps.dropFirst(state.cursor + 1).first { $0.item != step.item && logged[plan.key($0)] == nil }.map { name($0.item) }
    }
}

// On the line of the clock: the heart rate, when it is measured, and in the middle the time since the start.
private struct SessionHeader: View {
    let session: Session?
    @Environment(WorkoutRecorder.self) private var recorder

    var body: some View {
        ZStack {
            HStack {
                if let heartRate = recorder.heartRate {
                    let value = Int(heartRate.rounded())
                    Label {
                        Text(verbatim: value.formatted())
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                    }
                    .labelStyle(.titleAndIcon)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Heart rate"))
                    .accessibilityValue(Text("\(value) beats per minute"))
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            if let session {
                // A timer text would take all the width the end of its range could need.
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text(verbatim: FieldText.clock(Int(context.date.timeIntervalSince(session.startedAt))))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }
            }
        }
        .font(.body.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // The line is shared with the clock: it does not grow with the rest of the page.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

// Enough for the corners of the screen and the dots of the pages.
private let lowerMargin = 10.0

// A page down to the lower edge of the screen, with what comes last at the bottom when it has spacers. It scrolls only
// when its text is too large for the screen.
struct FullPage<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var height = 0.0

    var body: some View {
        ScrollView {
            content
                .padding(.bottom, lowerMargin)
                .frame(maxWidth: .infinity, minHeight: height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: Double.self) { $0.size.height } action: { height = $0 }
        .ignoresSafeArea(edges: .bottom)
    }
}

extension View {
    // What goes on the line of the clock, above the page: centred on it, as high as it is on every size of watch.
    func onClockLine<Line: View>(@ViewBuilder _ line: () -> Line) -> some View {
        NavigationStack {
            overlay(alignment: .top) {
                line()
                    .frame(height: 0)
                    .offset(y: -20)
            }
        }
    }
}

// The set to do: a box for each of its values, the one chosen set with the Digital Crown, and Validate.
private struct SetPage: View {
    let table: LiveTable
    let step: LiveStep
    let session: Session?
    let edit: (SetValues) -> Void
    let validate: () -> Void
    @State private var chosen: SetField?
    @State private var crown = 0.0
    @State private var isWide = false
    @FocusState private var crownHeld: Bool

    var body: some View {
        let fields = table.metrics(step.item)
        let field = chosen ?? fields[0]
        FullPage {
            VStack(spacing: 2) {
                Text(verbatim: table.name(step.item))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                HStack(spacing: 6) {
                    ForEach(fields, id: \.self) { box in
                        ValueBox(
                            title: table.columnTitle(box, item: step.item, long: true),
                            unit: table.columnTitle(box, item: step.item, long: false),
                            text: text(box),
                            isChosen: box == field
                        ) {
                            chosen = box
                            crownHeld = true
                        } adjust: { direction in
                            change(box, to: max(0, (table.draft(step)[box] ?? 0) + direction * table.fields.increment(of: box)))
                        }
                    }
                }
                .focusable()
                .focused($crownHeld)
                .focusEffectDisabled()
                .digitalCrownRotation($crown, from: 0, through: Self.limit(field), by: table.fields.increment(of: field))
                Spacer(minLength: 4)
                Button(action: validate) {
                    Text("Validate")
                        .font(.headline)
                        .foregroundStyle(Color(.onAccent))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
        .onClockLine {
            SessionHeader(session: session)
        }
        .onChange(of: field, initial: true) {
            crown = table.draft(step)[field] ?? 0
        }
        .onChange(of: crown) { _, value in
            let increment = table.fields.increment(of: field)
            // The value the crown settles on; not when it was only given the value of the box.
            guard abs(value - (table.draft(step)[field] ?? 0)) >= increment / 2 else { return }
            change(field, to: (value / increment).rounded() * increment)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= Self.wideScreen } action: { wide in
            isWide = wide
        }
        .task {
            crownHeld = true
        }
    }

    // The largest watches have room for last time's values.
    nonisolated private static let wideScreen: CGFloat = 195

    // The highest value the crown reaches, in stored units.
    private static func limit(_ field: SetField) -> Double {
        switch field {
        case .weight: 500_000
        case .reps: 999
        case .duration, .rest: 7200
        case .distance: 100_000
        }
    }

    private var subtitle: String {
        let position = table.position(step)
        guard isWide, let last = table.previous[table.plan.items[step.item].exerciseID]?[step.set] else { return position }
        let values = table.setText(step.item, values: last)
        return String(localized: "\(position) · prev. \(values)")
    }

    private func text(_ field: SetField) -> String {
        table.draft(step)[field].map { table.fields.text($0, of: field) } ?? "–"
    }

    private func change(_ field: SetField, to value: Double) {
        var values = table.draft(step)
        values[field] = value
        edit(values)
    }
}

// A value of the set to do: touched, the crown sets it; with VoiceOver, swiped up or down.
private struct ValueBox: View {
    let title: String
    let unit: String
    let text: String
    let isChosen: Bool
    let choose: () -> Void
    let adjust: (Double) -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 0) {
                Text(verbatim: text)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(verbatim: unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
            .overlay {
                if isChosen {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: text))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(1)
            case .decrement: adjust(-1)
            @unknown default: break
            }
        }
    }
}

// The rest after a set: the time left (an absolute end), the set that follows, Skip, −15 s and +15 s. The time in a ring
// when the screen has room for it, above a bar when it has not.
private struct RestPage: View {
    let table: LiveTable
    let end: Date
    let totalS: Int
    let shorten: () -> Void
    let skip: () -> Void
    let lengthen: () -> Void
    @ScaledMetric(relativeTo: .title2) private var ringSide = 66.0

    var body: some View {
        NavigationStack {
            ViewThatFits(in: .vertical) {
                page {
                    ring
                }
                page {
                    bar
                }
                // Only when the text is too large for the screen.
                ScrollView {
                    page {
                        bar
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip", action: skip)
                        .foregroundStyle(Color(.rest))
                }
            }
        }
    }

    private func page<Time: View>(@ViewBuilder _ time: () -> Time) -> some View {
        VStack(spacing: 2) {
            Text("Rest")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color(.rest))
            time()
            Spacer(minLength: 2)
            if let step = table.step {
                Text(verbatim: table.name(step.item))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: "\(table.position(step)) · \(table.setText(step.item, values: table.draft(step), unit: true))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 2)
            HStack(spacing: 6) {
                Button(action: shorten) {
                    Text(verbatim: "−15 s")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(Text("Remove 15 seconds"))
                Button(action: lengthen) {
                    Text(verbatim: "+15 s")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(Text("Add 15 seconds"))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .padding(.bottom, lowerMargin)
    }

    private var timeLeft: some View {
        Text(timerInterval: Date.now...max(end, .now), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    // The part of the rest still to come.
    private func left(at date: Date) -> Double {
        totalS > 0 ? min(1, max(0, end.timeIntervalSince(date)) / Double(totalS)) : 0
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color(.rest).opacity(0.25), lineWidth: 5)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = left(at: context.date)
                Circle()
                    .trim(from: 0, to: left)
                    .stroke(Color(.rest), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
            }
            timeLeft
                .font(.title2.weight(.bold))
                .padding(8)
        }
        .frame(width: ringSide, height: ringSide)
    }

    // Empties from right to left.
    private var bar: some View {
        VStack(spacing: 4) {
            timeLeft
                .font(.title.weight(.bold))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = left(at: context.date)
                Capsule()
                    .fill(Color(.rest))
                    .scaleEffect(x: left, anchor: .leading)
                    .animation(.linear(duration: 1), value: left)
            }
            .frame(height: 7)
            .background(Color(.rest).opacity(0.25), in: .capsule)
            .accessibilityHidden(true)
        }
    }
}

// Every set is done: the session can be finished.
private struct AllDonePage: View {
    let session: Session?
    let finish: () -> Void

    var body: some View {
        FullPage {
            VStack {
                Spacer(minLength: 0)
                Text("All sets done")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 4)
                Button(action: finish) {
                    Text("Finish the session")
                        .font(.headline)
                        .foregroundStyle(Color(.onAccent))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
        .onClockLine {
            SessionHeader(session: session)
        }
    }
}

// What is measured, with the next exercise, and the way out of the session.
private struct MetricsPage: View {
    let table: LiveTable
    let session: Session?
    let finish: () -> Void
    @Environment(WorkoutRecorder.self) private var recorder

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let session {
                    Text(timerInterval: session.startedAt...Date.distantFuture, countsDown: false)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }
                metric(recorder.heartRate, unit: Text("bpm"), label: Text("Heart rate"), symbol: "heart.fill")
                metric(recorder.activeKilocalories, unit: Text("active kcal"), label: Text("Active calories"))
                metric(Double(table.workingSetsDone), unit: Text("sets"), label: Text("sets"))
                if let next = table.nextExercise {
                    Text("Next: \(next)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Finish", role: .destructive, action: finish)
                    // A button of the watch stays narrower than the page.
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // A dash when nothing measures it.
    private func metric(_ value: Double?, unit: Text, label: Text, symbol: String? = nil) -> some View {
        let shown = value.map { Int($0.rounded()).formatted() } ?? "–"
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Text(verbatim: shown)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            unit
                .font(.footnote)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: shown))
    }
}
