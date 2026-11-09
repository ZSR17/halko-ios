import HalkoCore
import SwiftUI

// The Tools tab: a line for each tool, which opens it in full screen. Worked out on the device: the same offline.
struct ToolsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                NavigationLink {
                    PlatesView()
                } label: {
                    ToolRow(title: Text("Plate calculator"), symbol: "dumbbell")
                }
                .buttonStyle(.plain)
                NavigationLink {
                    OneRepMaxView()
                } label: {
                    ToolRow(title: Text("1RM calculator"), symbol: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(.plain)
            }
            .padding([.horizontal, .bottom])
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tools")
    }
}

private struct ToolRow: View {
    let title: Text
    let symbol: String
    @ScaledMetric(relativeTo: .title3) private var iconSide = 48.0

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color(.onAccent))
                .frame(width: iconSide, height: iconSide)
                .background(.tint, in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            title
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.secondaryText))
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .contentShape(.rect)
    }
}

// A box of a tool that has the keyboard.
nonisolated enum ToolField: Hashable, Sendable {
    case target, bar, load, reps, reserve
    case plate(String)
}

// A value of a tool, changed with − and +, or typed in its box.
struct ToolStepper: View {
    let title: Text
    let less: Text
    let more: Text
    // Beside the box: "kg".
    var unit: String?
    let value: Double
    let field: SetField
    let step: Double
    let range: ClosedRange<Double>
    let fields: FieldText
    let focus: FocusState<ToolField?>.Binding
    let id: ToolField
    let change: (Double) -> Void
    @State private var text = ""
    @State private var selection: TextSelection?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Room for "100.5" beside its unit, for a count less.
    @ScaledMetric(relativeTo: .body) private var weightWidth = 68.0
    @ScaledMetric(relativeTo: .body) private var countWidth = 40.0

    private var isFocused: Bool {
        focus.wrappedValue == id
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            title
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                button("minus", by: -step)
                    .accessibilityLabel(less)
                box
                button("plus", by: step)
                    .accessibilityLabel(more)
            }
            // Its own width, whatever room the title takes.
            .fixedSize(horizontal: true, vertical: false)
        }
        .onAppear {
            text = fields.text(value, of: field)
        }
        .onChange(of: value) { _, value in
            if !isFocused {
                text = fields.text(value, of: field)
            }
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused else {
                selectAllText(text, in: $selection)
                return
            }
            if let typed = fields.value(text, of: field) {
                change(min(max(typed, range.lowerBound), range.upperBound))
            }
            text = fields.text(value, of: field)
        }
    }

    private var box: some View {
        HStack(spacing: 2) {
            TextField(text: $text, selection: $selection) {
                title
            }
            .focused(focus, equals: id)
            .keyboardType(field == .weight ? .decimalPad : .numberPad)
            .multilineTextAlignment(.trailing)
            .fontWeight(.bold)
            .monospacedDigit()
            .accessibilityLabel(title)
            // Grows with the text, up to what still leaves room for the buttons on the line.
            .frame(width: field == .weight ? min(weightWidth, 130) : min(countWidth, 80))
            if let unit {
                Text(verbatim: unit)
                    .fontWeight(.bold)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
    }

    private func button(_ symbol: String, by amount: Double) -> some View {
        Button {
            change(min(max(value + amount, range.lowerBound), range.upperBound))
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                // Within its 44 points, at the largest text sizes too.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

extension SetsText {
    // A weight of a tool: "25 kg".
    func toolWeight(_ grams: Int) -> String {
        record(ExerciseRecord(kind: .maxWeight, value: Double(grams)))
    }

    var weightSymbol: String {
        (weightUnit == .kg ? UnitMass.kilograms : UnitMass.pounds).symbol
    }
}
