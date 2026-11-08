import HalkoCore
import SwiftUI

// The block fixed at the bottom of the session: the set to do, the rest, or the end. `bottomPadding` may be negative,
// to go down into the area of the home indicator.
private struct Panel<Content: View>: View {
    var tint: Color?
    let bottomPadding: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Fixed over the sets: with the largest text sizes, it would hide them all.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // For the interface tests: the sets hidden under it are not measured.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottom-panel")
        .background(alignment: .top) {
            let shape = UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
            shape
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    if let tint {
                        shape.fill(tint.opacity(0.12))
                    }
                }
                // Down past the bottom edge of the screen, so that nothing shows under it.
                .padding(.bottom, -400)
                .shadow(color: .black.opacity(0.2), radius: 12, y: -4)
        }
    }
}

// The set to do, or the rest after a set. The panel keeps the height of the taller of the two, so that it does not
// change size from one to the other: the one not shown is laid out hidden under the other.
struct SetOrRestPanel: View {
    let table: LiveTable
    let actions: LiveActions
    // The set to do, or the one after the rest.
    let step: LiveStep?
    // The end of the rest, while resting.
    let restEnd: Date?
    let restTotalS: Int
    let bottomPadding: CGFloat
    let shorten: () -> Void
    let skip: () -> Void
    let lengthen: () -> Void

    var body: some View {
        Panel(tint: restEnd == nil ? nil : Color(.rest), bottomPadding: bottomPadding) {
            ZStack(alignment: .topLeading) {
                if let restEnd {
                    rest(end: restEnd)
                    if let step {
                        SetContent(table: table, actions: actions, step: step)
                            .hidden()
                            .accessibilityHidden(true)
                    }
                } else if let step {
                    SetContent(table: table, actions: actions, step: step)
                    rest(end: .now + Double(restTotalS))
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func rest(end: Date) -> some View {
        RestContent(end: end, totalS: restTotalS, next: table.nextText, shorten: shorten, skip: skip, lengthen: lengthen)
    }
}

// The timer of the set to do: getting in position, the time held, the pause between two sides. As high as the panel of
// the set and of the rest, laid out hidden under it. The screen stays on, the iPhone probably on the floor.
struct TimerPanel: View {
    let table: LiveTable
    let actions: LiveActions
    let step: LiveStep
    let timer: SetTimer
    let bottomPadding: CGFloat
    let begin: () -> Void
    let cancel: () -> Void
    let stop: () -> Void
    // The date the panel is drawn for, moved at each change of the timer.
    @State private var phase = Date.now
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let display = SetTimerDisplay(timer: timer, date: phase)
        Panel(tint: display.isPause ? Color(.rest) : nil, bottomPadding: bottomPadding) {
            ZStack(alignment: .topLeading) {
                content(display, tint: display.isPause ? Color(.rest) : Color.accentColor)
                SetContent(table: table, actions: actions, step: step)
                    .hidden()
                    .accessibilityHidden(true)
                RestContent(end: phase + 60, totalS: 60, next: table.nextText, shorten: {}, skip: {}, lengthen: {})
                    .hidden()
                    .accessibilityHidden(true)
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
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // What the timer shows at a tick, which falls exactly on a whole second give or take the rounding of the dates.
    private func ticking<Content: View>(@ViewBuilder _ content: @escaping (SetTimerDisplay) -> Content) -> some View {
        TimelineView(.periodic(from: timer.startsAt - 3600, by: 1)) { context in
            content(SetTimerDisplay(timer: timer, date: context.date + 0.001))
        }
    }

    private func content(_ display: SetTimerDisplay, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: display.title)
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(tint)
                    // Over a hidden text as wide as it can get: its change each second does not make the panel work
                    // out its layout again.
                    Text(verbatim: FieldText.clock(599))
                        .hidden()
                        .overlay(alignment: .leading) {
                            ticking { now in
                                Text(verbatim: FieldText.clock(now.seconds))
                            }
                        }
                        .font(.system(size: timeSize, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .accessibilityElement(children: .combine)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                aside(display)
            }
            ticking { now in
                Capsule()
                    .fill(tint)
                    .scaleEffect(x: now.part, anchor: .leading)
                    // Empty at zero: its rounded ends would still show.
                    .opacity(now.part > 0.001 ? 1 : 0)
            }
            .frame(height: 6)
            .background(tint.opacity(0.25), in: .capsule)
            .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    buttons(display, tint: tint)
                }
                VStack(spacing: 8) {
                    buttons(display, tint: tint)
                }
            }
        }
    }

    // What goes with the time, under the heart rate.
    private func aside(_ display: SetTimerDisplay) -> some View {
        let alignment: HorizontalAlignment = dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
        return VStack(alignment: alignment, spacing: 8) {
            HeartRateChip()
            facts(display, alignment: alignment)
        }
    }

    @ViewBuilder
    private func facts(_ display: SetTimerDisplay, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            if display.isPause {
                if let firstSide = display.firstSide {
                    Text(verbatim: firstSide)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryText))
                }
                Text("Next: right side")
                    .font(.headline)
            } else if display.isWaiting {
                Text("Next")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
                if let next = table.nextText {
                    Text(verbatim: next)
                        .font(.headline)
                }
            } else if display.isOver {
                Text("Over")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
                ticking { now in
                    Text(verbatim: now.extra ?? "")
                        .font(.headline)
                        .monospacedDigit()
                }
            } else if let targetS = timer.targetS {
                Text("Target")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
                Text(verbatim: FieldText.clock(targetS))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func buttons(_ display: SetTimerDisplay, tint: Color) -> some View {
        Button(action: cancel) {
            Text("Cancel")
                .foregroundStyle(Color(.label))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        Button(action: display.isWaiting ? begin : stop) {
            Group {
                if display.isWaiting {
                    Text("Begin")
                } else {
                    Text(verbatim: display.stopTitle)
                }
            }
            .foregroundStyle(display.isPause ? Color(.onRest) : Color(.onAccent))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }
}

// The set to do: which one, its values with − and + buttons, and Validate.
private struct SetContent: View {
    let table: LiveTable
    let actions: LiveActions
    let step: LiveStep
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let draft = table.draft(step)
        let fields = table.metrics(step.item)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                HeartRateChip()
            }
            let layout = dynamicTypeSize.isAccessibilitySize || fields.count > 2
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ForEach(fields, id: \.self) { field in
                    ValueStepper(
                        title: table.columnTitle(field, item: step.item, long: true),
                        unit: table.columnTitle(field, item: step.item, long: false),
                        value: draft[field],
                        field: field,
                        fields: table.fields
                    ) { value in
                        var edited = draft
                        edited[field] = value
                        actions.edit(table.plan.key(step), edited)
                    }
                }
            }
            if table.canUseTimer(step) {
                // On one line, so that the panel stays as high as for any other set.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        timerButtons
                    }
                    VStack(spacing: 8) {
                        timerButtons
                    }
                }
            } else {
                Button(action: actions.validate) {
                    Text(verbatim: validateTitle)
                        .font(.headline)
                        .foregroundStyle(Color(.onAccent))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var timerButtons: some View {
        Button(action: actions.validate) {
            Text("Validate")
                .font(.headline)
                .foregroundStyle(Color(.label))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        Button(action: actions.startTimer) {
            Text("Start the timer")
                .font(.headline)
                .foregroundStyle(Color(.onAccent))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private var isWarmup: Bool {
        table.plan.target(step.item, set: step.set).kind == .warmup
    }

    // "Set 2 of 4 · Bench press".
    private var title: String {
        let name = table.name(step.item)
        if isWarmup {
            return String(localized: "Warm-up · \(name)")
        }
        return String(localized: "Set \(table.plan.items[step.item].workingNumber(step.set)) of \(table.workingCount(step.item)) · \(name)")
    }

    private var validateTitle: String {
        if table.logged[table.plan.key(step)] != nil {
            return String(localized: "Correct the set")
        }
        return isWarmup ? String(localized: "Validate the warm-up") : String(localized: "Validate the set")
    }
}

// A value of the set to do, between − and + buttons.
private struct ValueStepper: View {
    let title: String
    let unit: String
    let value: Double?
    let field: SetField
    let fields: FieldText
    let change: (Double) -> Void
    @ScaledMetric(relativeTo: .title2) private var buttonSide: CGFloat = 44

    var body: some View {
        HStack(spacing: 4) {
            button("minus", by: -1)
                .accessibilityLabel(Text(verbatim: field == .reps ? String(localized: "One rep less") : String(localized: "Remove \(amount)")))
            VStack(spacing: 0) {
                Text(verbatim: text)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(verbatim: unit)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryText))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityValue(Text(verbatim: text))
            button("plus", by: 1)
                .accessibilityLabel(Text(verbatim: field == .reps ? String(localized: "One rep more") : String(localized: "Add \(amount)")))
        }
        .padding(4)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 16))
    }

    // What a button adds or removes: "0.5 kg", "5 s".
    private var amount: String {
        switch field {
        case .weight: "\(fields.text(increment, of: .weight)) \((fields.weightUnit == .kg ? UnitMass.kilograms : UnitMass.pounds).symbol)"
        case .distance: "\(fields.text(increment, of: .distance)) \((fields.distanceUnit == .km ? UnitLength.kilometers : UnitLength.miles).symbol)"
        case .reps: "1"
        case .duration, .rest: "\(Int(increment)) \(UnitDuration.seconds.symbol)"
        }
    }

    private var text: String {
        value.map { fields.text($0, of: field) } ?? "–"
    }

    private var increment: Double {
        fields.increment(of: field)
    }

    private func step(by direction: Double) {
        change(max(0, (value ?? 0) + direction * increment))
    }

    private func button(_ symbol: String, by direction: Double) -> some View {
        Button {
            step(by: direction)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: buttonSide, height: buttonSide)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(direction < 0 && (value ?? 0) <= 0)
    }
}

// The rest after a set: the time left (an absolute end, the same everywhere), what comes next, −15 s, Skip, +15 s.
private struct RestContent: View {
    let end: Date
    let totalS: Int
    let next: String?
    let shorten: () -> Void
    let skip: () -> Void
    let lengthen: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Rest")
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color(.rest))
                    Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                        .font(.system(size: timeSize, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .accessibilityElement(children: .combine)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 8) {
                    HeartRateChip()
                    if let next {
                        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                            Text("Next")
                                .font(.subheadline)
                                .foregroundStyle(Color(.secondaryText))
                            Text(verbatim: next)
                                .font(.headline)
                                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            ProgressView(timerInterval: (end - Double(totalS))...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(Color(.rest))
            .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    buttons
                }
                VStack(spacing: 8) {
                    buttons
                }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: shorten) {
            Text(verbatim: "−15 s")
                .foregroundStyle(Color(.label))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(Text("Remove 15 seconds"))
        .buttonStyle(.bordered)
        Button(action: skip) {
            Text("Skip")
                .foregroundStyle(Color(.onRest))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(.rest))
        Button(action: lengthen) {
            Text(verbatim: "+15 s")
                .foregroundStyle(Color(.label))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(Text("Add 15 seconds"))
        .buttonStyle(.bordered)
    }
}

// Every set is done: the session can be finished.
struct AllDonePanel: View {
    let bottomPadding: CGFloat
    let finish: () -> Void

    var body: some View {
        Panel(bottomPadding: bottomPadding) {
            Text("All sets done")
                .font(.headline)
            Button(action: finish) {
                Text("Finish the session")
                    .font(.headline)
                    .foregroundStyle(Color(.onAccent))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }
}

// The heart rate measured by a watch or a sensor, in a corner of the panel whatever it shows: absent without one.
struct HeartRateChip: View {
    @Environment(WorkoutRecorder.self) private var recorder

    var body: some View {
        if let bpm = recorder.heartRate {
            let value = Int(bpm.rounded())
            Label {
                Text("\(value) bpm")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(Text("Heart rate"))
            .accessibilityValue(Text("\(value) beats per minute"))
        }
    }
}
