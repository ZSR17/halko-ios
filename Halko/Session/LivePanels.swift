import HalkoCore
import SwiftUI

// The block fixed at the bottom of the session: the set to do, the rest, or the end.
private struct Panel<Content: View>: View {
    var tint: Color?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Fixed over the sets: with the largest text sizes, it would hide them all.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // For the interface tests: the sets hidden under it are not measured.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottom-panel")
        .background {
            ZStack {
                Color(.secondarySystemGroupedBackground)
                if let tint {
                    tint.opacity(0.12)
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            .shadow(color: .black.opacity(0.2), radius: 12, y: -4)
            // Down to the bottom edge of the screen.
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

// The set to do: which one, its values with − and + buttons, and Validate.
struct SetPanel: View {
    let table: LiveTable
    let step: LiveStep
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let draft = table.draft(step)
        let fields = table.metrics(step.item)
        Panel {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
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
                        table.actions.edit(table.plan.key(step), edited)
                    }
                }
            }
            Button(action: table.actions.validate) {
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

    // What a button adds or removes: "2.5 kg", "5 s".
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

    // 2.5 kg or 5 lb, a rep, 5 s, a hundredth of a km or mile.
    private var increment: Double {
        switch field {
        case .weight: fields.weightUnit == .kg ? 2500 : 5 * fields.weightUnit.grams
        case .reps: 1
        case .duration, .rest: 5
        case .distance: fields.distanceUnit == .km ? 10 : 16.09344
        }
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
struct RestPanel: View {
    let end: Date
    let totalS: Int
    let next: String?
    let shorten: () -> Void
    let skip: () -> Void
    let lengthen: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Panel(tint: Color(.rest)) {
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
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(Text("Add 15 seconds"))
        .buttonStyle(.bordered)
    }
}

// Every set is done: the session can be finished.
struct AllDonePanel: View {
    let finish: () -> Void

    var body: some View {
        Panel {
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
