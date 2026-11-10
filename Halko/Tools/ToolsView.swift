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
    // Makes the title a button, with this label: a plate's weight opens it to be corrected.
    var edit: (label: Text, action: () -> Void)?
    let change: (Double) -> Void
    @State private var text = ""
    @State private var selection: TextSelection?
    // The value last given: steps made while a button is held start from here, not from the `value` it had when pressed.
    @State private var latest: Double?
    // Steps made while a button is held down, and whether they started: the touch let go then changes nothing more.
    @State private var holding: Task<Void, Never>?
    @State private var held = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Room for "100.5 kg", the same for every value, so that the buttons of a page line up.
    @ScaledMetric(relativeTo: .body) private var boxWidth = 100.0

    private var isFocused: Bool {
        focus.wrappedValue == id
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Group {
                if let edit {
                    Button(action: edit.action) {
                        title
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(edit.label)
                } else {
                    title
                }
            }
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
        .onDisappear {
            holding?.cancel()
        }
        .onChange(of: value) { _, value in
            latest = value
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
            // As wide as its digits, drawn hidden for that: a text field's own width is not reliable, and it left no room
            // for the unit. The digits and the unit are then centred together between the buttons.
            Text(verbatim: text.isEmpty ? "0" : text)
                .fontWeight(.bold)
                .monospacedDigit()
                .padding(.horizontal, 2)
                .hidden()
                .overlay {
                    TextField(text: $text, selection: $selection) {
                        title
                    }
                    .focused(focus, equals: id)
                    .keyboardType(field == .weight ? .decimalPad : .numberPad)
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .accessibilityLabel(title)
                    // Easy to touch, wider than the digits it is centred on.
                    .frame(minWidth: 44, minHeight: 44)
                }
            if let unit {
                Text(verbatim: unit)
                    .fontWeight(.bold)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
        // Grows with the text, up to what still leaves room for the buttons on the line.
        .frame(width: min(boxWidth, 170))
        .frame(minHeight: 44)
    }

    private func button(_ symbol: String, by amount: Double) -> some View {
        Button {
            if !held {
                step(by: amount)
            }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                // Within its 44 points, at the largest text sizes too.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
                .contentShape(.rect)
        }
        .buttonStyle(HoldButtonStyle { pressed in
            hold(pressed, by: amount)
        })
    }

    private func step(by amount: Double) {
        let changed = min(max((latest ?? value) + amount, range.lowerBound), range.upperBound)
        latest = changed
        change(changed)
    }

    // Held down, a button starts stepping soon, then faster and faster.
    private func hold(_ pressed: Bool, by amount: Double) {
        holding?.cancel()
        holding = nil
        guard pressed else { return }
        held = false
        holding = Task {
            try? await Task.sleep(for: .milliseconds(300))
            var pause = 150.0
            while !Task.isCancelled {
                held = true
                step(by: amount)
                try? await Task.sleep(for: .milliseconds(Int(pause)))
                pause = max(35, pause * 0.85)
            }
        }
    }
}

// A plain button that tells when it is pressed and let go.
private struct HoldButtonStyle: ButtonStyle {
    let pressing: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                pressing(pressed)
            }
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
