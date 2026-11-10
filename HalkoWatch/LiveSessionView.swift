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
    @Environment(\.units) private var units
    @Query private var sessions: [Session]
    @Query private var sets: [SetLog]
    @Query private var exercises: [Exercise]
    // Values being changed on sets not done yet, by step key: handed to the session once the crown pauses.
    @State private var typing: [String: SetValues] = [:]
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
        // On the iPhone too, once the crown pauses: not at each of its steps.
        .task(id: typing) {
            guard !typing.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            change { _ in }
        }
        .task(id: RestAlarm(end: state.restEndsAt, timerEnd: state.setTimer?.targetEnd, recording: recorder.isRecording)) {
            await waitForTheEndOfRest(next: table.nextText)
        }
        .task(id: state.setTimer) {
            await followTimer()
        }
    }

    @ViewBuilder
    private func work(_ table: LiveTable) -> some View {
        if table.allDone {
            AllDonePage(session: sessions.first) {
                finishing = true
            }
        } else if let timer = table.timer {
            TimerPage(table: table, timer: timer) {
                store.change { $0.beginHolding() }
            } cancel: {
                store.change { $0.setTimer = nil }
            } stop: {
                stopTimer()
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
                typing[table.plan.key(step)] = values
            } validate: {
                validate(table, step)
            } startTimer: {
                change {
                    $0.startTimer(
                        stepKey: table.plan.key(step),
                        values: table.draft(step),
                        startedFrom: table.startedFrom(step),
                        sidesPauseS: table.plan.items[step.item].sidesPauseS,
                        settings: SetTimerSettings(defaults: .standard)
                    )
                }
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
            edits: state.edits.merging(typing) { _, typed in typed },
            exercises: Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            fields: FieldText(weightUnit: units.weight, distanceUnit: units.distance, locale: locale),
            text: SetsText(units: units)
        )
    }

    // The end of the rest: a vibration while the app runs (a workout of Health keeps it running with the wrist down);
    // without one, a notification takes over when the watch puts the app to sleep.
    private func waitForTheEndOfRest(next: String?) async {
        if let timerEnd = state.setTimer?.targetEnd {
            await RestAlert.schedule(recorder.isRecording ? nil : RestAlert.Request(end: timerEnd, body: next ?? "", title: String(localized: "Target reached")))
            return
        }
        let end = state.restEndsAt
        await RestAlert.schedule(recorder.isRecording ? nil : end.map { RestAlert.Request(end: $0, body: next ?? "") })
        guard let end else { return }
        try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
        guard !Task.isCancelled else { return }
        // Not for a rest long over, when the app comes back.
        if end.timeIntervalSinceNow > -10 {
            WKInterfaceDevice.current().play(.notification)
        }
        store.restOver()
    }

    // A tap on the wrist when holding starts and at the target, and the stop on its own.
    private func followTimer() async {
        guard let timer = state.setTimer else { return }
        while let next = timer.nextChange(after: .now) {
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(next == timer.targetEnd ? .notification : .start)
        }
        if timer.isDue(at: .now) {
            stopTimer()
        }
    }

    private func stopTimer() {
        do {
            try store.change { try context.stopTimer(&$0) }
        } catch {
            Self.logger.error("Cannot change the session: \(String(describing: error))")
        }
    }

    private func validate(_ table: LiveTable, _ step: LiveStep) {
        let values = table.draft(step)
        let startedFrom = table.startedFrom(step)
        let index = state.cursor
        change { try context.logSet(&$0, step: index, values: values, startedFrom: startedFrom) }
    }

    // An action on the set takes the values being changed with it.
    private func change(_ body: (inout LiveState) throws -> Void) {
        let typed = typing
        typing = [:]
        do {
            try store.change { state in
                state.edits.merge(typed) { _, typed in typed }
                try body(&state)
            }
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
    let timerEnd: Date?
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

// On the line of the clock: the time since the start, and in the middle the heart rate, when it is measured.
private struct SessionHeader: View {
    let session: Session?

    var body: some View {
        ZStack {
            HStack {
                if let session {
                    // A timer text would take all the width the end of its range could need.
                    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                        Text(verbatim: FieldText.clock(Int(context.date.timeIntervalSince(session.startedAt))))
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            HeartRateText()
        }
        .clockLineStyle()
    }
}

// The heart rate, when it is measured, on every page of the session. `compact`: beside a button in the corner, where
// the line has little room left: without the margin of a label's icon, smaller if needed, the number alone when even
// that is too wide, and nothing on a watch too small for it.
private struct HeartRateText: View {
    var compact = false
    @Environment(WorkoutRecorder.self) private var recorder

    var body: some View {
        if let heartRate = recorder.heartRate {
            let value = Int(heartRate.rounded())
            if compact {
                ViewThatFits(in: .horizontal) {
                    announced(tight(value), value)
                    announced(tight(value).font(.subheadline.weight(.semibold)), value)
                    announced(tight(value).font(.footnote.weight(.semibold)), value)
                    announced(number(value), value)
                    Color.clear
                        .frame(width: 0, height: 0)
                }
            } else {
                announced(label(value), value)
            }
        }
    }

    private func announced(_ content: some View, _ value: Int) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(Text("Heart rate"))
            .accessibilityValue(Text("\(value) beats per minute"))
    }

    private func label(_ value: Int) -> some View {
        Label {
            number(value)
        } icon: {
            heart
        }
        .labelStyle(.titleAndIcon)
    }

    private func tight(_ value: Int) -> some View {
        HStack(spacing: 2) {
            heart
                .imageScale(.small)
            number(value)
        }
    }

    private var heart: some View {
        Image(systemName: "heart.fill")
            .foregroundStyle(.red)
    }

    private func number(_ value: Int) -> some View {
        Text(verbatim: value.formatted())
            .monospacedDigit()
    }
}

private extension View {
    // On a page with a button in its corner, which takes the left of the line of the clock and lowers the top of the
    // page: the heart rate clear of the button and of the clock, and as high as on the other pages. `centred`: in the
    // middle of the room between them; otherwise just after the button.
    func heartBesideCorner(_ cornerWidth: Double, centred: Bool = false) -> some View {
        clockLine {
            HStack {
                HeartRateText(compact: true)
                    .clockLineStyle()
                if !centred {
                    Spacer(minLength: 0)
                }
            }
            // Past the button: its margin to the edge of the screen, its capsule around the text, and a small gap.
            .padding(.leading, cornerWidth + 28)
            // Clear of the clock, at its widest ("10:09"): the number gets smaller rather than running into it.
            .padding(.trailing, 60)
            .offset(y: -17)
        }
    }

    // The width of the view, kept in `width`: unlike its place on the screen, it does not change as the pages move.
    func measuringWidth(_ width: Binding<Double>) -> some View {
        onGeometryChange(for: Double.self) { $0.size.width } action: { value in
            width.wrappedValue = value
        }
    }

    func clockLineStyle() -> some View {
        font(.body.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // The line is shared with the clock: it does not grow with the rest of the page.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            // Level with the clock on the watch.
            .offset(y: -2)
    }
}

// A ring or a bar that moves: smoothly with the screen lit, a step each second with the wrist down, on the whole seconds
// from `tick`. An animation's schedule stops in the Always On display: a periodic one goes on. Only the ring or the bar
// is drawn again: the page around it stays as it is.
private struct Advancing<Content: View>: View {
    let tick: Date
    @ViewBuilder let content: (Date) -> Content
    @Environment(\.isLuminanceReduced) private var isDimmed

    var body: some View {
        if isDimmed {
            TimelineView(.periodic(from: tick - 3600, by: 1)) { context in
                content(context.date + 0.001)
            }
        } else {
            TimelineView(.animation(minimumInterval: 0.05)) { context in
                content(context.date)
            }
        }
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
            clockLine(line)
        }
    }

    // The same, for a page in a navigation stack of its own.
    func clockLine<Line: View>(@ViewBuilder _ line: () -> Line) -> some View {
        overlay(alignment: .top) {
            line()
                // A line of no height would shrink its text.
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 0)
                .offset(y: -18)
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
    let startTimer: () -> Void
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
                // In steps of the value: the crown's sensitivity is a rotation per whole number, and grams would take
                // hundreds of them for a single step. Continuous, it shows no scroll bar; the ends are kept below.
                .digitalCrownRotation($crown, from: 0, through: crownSteps(field), by: 1, sensitivity: .low, isContinuous: true)
                Spacer(minLength: 4)
                if table.canUseTimer(step) {
                    HStack(spacing: 6) {
                        Button(action: validate) {
                            Text("Validate")
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button(action: startTimer) {
                            Text("Start")
                                .font(.headline)
                                .foregroundStyle(Color(.onAccent))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .handGestureShortcut(.primaryAction)
                    }
                    .buttonBorderShape(.capsule)
                    // Clear of the rounded corners of the screen.
                    .padding(.horizontal, 10)
                } else {
                    Button(action: validate) {
                        Text("Validate")
                            .font(.headline)
                            .foregroundStyle(Color(.onAccent))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .handGestureShortcut(.primaryAction)
                }
            }
        }
        .onClockLine {
            SessionHeader(session: session)
        }
        .onChange(of: crownStep(of: field), initial: true) { _, value in
            // The value of another box or another set, not the one the crown is settling on.
            if abs(crown - value) >= 0.5 {
                crown = value
            }
        }
        .onChange(of: crown) { old, value in
            guard abs(value - crownStep(of: field)) >= 0.5 else { return }
            // Past an end, the crown comes back at the other: the value stays where it is.
            if abs(value - old) > crownSteps(field) / 2 {
                crown = old
            } else {
                change(field, to: value.rounded() * table.fields.increment(of: field))
            }
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

    private func crownSteps(_ field: SetField) -> Double {
        Self.limit(field) / table.fields.increment(of: field)
    }

    private func crownStep(of field: SetField) -> Double {
        (table.draft(step)[field] ?? 0) / table.fields.increment(of: field)
    }

    private var subtitle: String {
        let position = table.position(step)
        guard isWide, let last = table.previous[table.plan.items[step.item].exerciseID]?[step.set] else { return position }
        let values = table.setText(step.item, values: last)
        return String(localized: "\(position) · prev. \(values)")
    }

    private func text(_ field: SetField) -> String {
        table.draft(step)[field].map { table.fields.steadyText($0, of: field) } ?? "–"
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
            // Clear of the border of the chosen box.
            .padding(.bottom, 4)
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
    // The width of the text of the button in the corner.
    @State private var cornerWidth = 0.0

    var body: some View {
        NavigationStack {
            ViewThatFits(in: .vertical) {
                page(raisingRest: 4) {
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
            .heartBesideCorner(cornerWidth, centred: true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: skip) {
                        Text("Skip")
                            .measuringWidth($cornerWidth)
                    }
                    .foregroundStyle(Color(.rest))
                }
            }
        }
    }

    private func page<Time: View>(raisingRest: Double = 2, @ViewBuilder _ time: () -> Time) -> some View {
        VStack(spacing: 0) {
            Text("Rest")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color(.rest))
                .offset(y: -raisingRest)
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
            // Clear of the rounded corners of the screen.
            .padding(.horizontal, 10)
        }
        // Closer to Skip than the bar of the page, and lower than the other pages: the dots fall between the two buttons.
        .padding(.top, -6)
        .padding(.bottom, 6)
    }

    // Over a hidden text as wide as it can get: its change each second does not make the page work out its layout again.
    private var timeLeft: some View {
        Text(verbatim: FieldText.clock(max(totalS, Int(end.timeIntervalSinceNow.rounded(.up)))))
            .hidden()
            .overlay {
                TimelineView(.periodic(from: end - 3600, by: 1)) { context in
                    // The tick falls exactly on a whole second, give or take the rounding of the dates.
                    Text(verbatim: FieldText.clock(Int((end.timeIntervalSince(context.date) - 0.001).rounded(.up))))
                }
            }
            .monospacedDigit()
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
            Advancing(tick: end) { date in
                let left = left(at: date)
                Circle()
                    .trim(from: 0, to: left)
                    .stroke(Color(.rest), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // Empty at zero: its rounded ends would still show.
                    .opacity(left > 0.001 ? 1 : 0)
            }
            timeLeft
                .font(.title2.weight(.bold))
                .padding(8)
        }
        .frame(width: ringSide, height: ringSide)
    }

    // Empties from right to left.
    private var bar: some View {
        VStack(spacing: 2) {
            timeLeft
                .font(.title2.weight(.bold))
            Advancing(tick: end) { date in
                Capsule()
                    .fill(Color(.rest))
                    .scaleEffect(x: left(at: date), anchor: .leading)
            }
            .frame(height: 7)
            .background(Color(.rest).opacity(0.25), in: .capsule)
            .accessibilityHidden(true)
        }
    }
}

// The timer of the set to do, laid out like the rest: Cancel at the top, the time in a ring when the screen has room for
// it, the main button at the bottom.
private struct TimerPage: View {
    let table: LiveTable
    let timer: SetTimer
    let begin: () -> Void
    let cancel: () -> Void
    let stop: () -> Void
    // The date the page is drawn for, moved at each change of the timer.
    @State private var phase = Date.now
    @ScaledMetric(relativeTo: .title2) private var ringSide = 66.0
    // The width of the text of the button in the corner.
    @State private var cornerWidth = 0.0

    var body: some View {
        NavigationStack {
            let display = SetTimerDisplay(timer: timer, date: phase)
            let tint = display.isPause ? Color(.rest) : Color.accentColor
            ViewThatFits(in: .vertical) {
                page(display, tint: tint, showsRing: true)
                page(display, tint: tint, showsRing: false)
                // Only when the text is too large for the screen.
                ScrollView {
                    page(display, tint: tint, showsRing: false)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .heartBesideCorner(cornerWidth)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: cancel) {
                        Text("Cancel")
                            .measuringWidth($cornerWidth)
                    }
                }
            }
        }
        .task(id: timer) {
            phase = .now
            while let next = timer.nextChange(after: .now) {
                try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                phase = .now
            }
        }
    }

    // What the timer shows at a tick, which falls exactly on a whole second give or take the rounding of the dates.
    private func ticking<Content: View>(@ViewBuilder _ content: @escaping (SetTimerDisplay) -> Content) -> some View {
        TimelineView(.periodic(from: timer.startsAt - 3600, by: 1)) { context in
            content(SetTimerDisplay(timer: timer, date: context.date + 0.001))
        }
    }

    private func page(_ display: SetTimerDisplay, tint: Color, showsRing: Bool) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: display.title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // As high as « Rest » on the page of the rest.
                .offset(y: showsRing ? -4 : -2)
            if showsRing {
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.25), lineWidth: 5)
                    Advancing(tick: timer.startsAt) { date in
                        let part = SetTimerDisplay(timer: timer, date: date).part
                        Circle()
                            .trim(from: 0, to: part)
                            .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            // Empty at zero: its rounded ends would still show.
                            .opacity(part > 0.001 ? 1 : 0)
                    }
                    time
                        .padding(8)
                }
                .frame(width: ringSide, height: ringSide)
            } else {
                time
            }
            Spacer(minLength: 2)
            Text(verbatim: firstLine(display))
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Group {
                if display.isOver {
                    ticking { now in
                        Text(verbatim: now.extra ?? "")
                    }
                } else {
                    Text(verbatim: secondLine(display))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Button(action: display.isWaiting ? begin : stop) {
                Group {
                    if display.isWaiting {
                        Text("Begin")
                    } else {
                        Text(timer.isFirstSide ? "Next side" : "Stop")
                    }
                }
                .font(.headline)
                .foregroundStyle(display.isPause ? Color(.onRest) : Color(.onAccent))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(tint)
            .handGestureShortcut(.primaryAction)
            // Clear of the rounded corners of the screen.
            .padding(.horizontal, 10)
        }
        .padding(.top, -6)
        .padding(.bottom, 6)
    }

    // Over a hidden text as wide as it can get: its change each second does not make the page work out its layout again.
    private var time: some View {
        Text(verbatim: FieldText.clock(599))
            .hidden()
            .overlay {
                ticking { now in
                    Text(verbatim: FieldText.clock(now.seconds))
                }
            }
            .font(.title2.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func firstLine(_ display: SetTimerDisplay) -> String {
        if display.isPause {
            return String(localized: "Next: right side")
        }
        if display.isOver {
            return String(localized: "Target reached")
        }
        return table.step.map { table.name($0.item) } ?? ""
    }

    private func secondLine(_ display: SetTimerDisplay) -> String {
        if display.isPause {
            return display.firstSide ?? ""
        }
        let position = table.step.map { table.position($0) } ?? ""
        return timer.targetS.map { "\(position) · \(FieldText.clock($0))" } ?? position
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
