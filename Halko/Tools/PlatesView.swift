import HalkoCore
import SwiftUI

// The plates to put on the bar for a weight, from the plates owned, which are kept on this device.
struct PlatesView: View {
    // Opened from the 1RM calculator with a weight to make.
    var openingTargetG: Int?
    @AppStorage(PlateSettings.storageKey) private var stored = Data()
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focus: ToolField?
    @ScaledMetric(relativeTo: .body) private var answerHeight = 170.0
    @State private var adding = false
    @State private var newWeight = ""
    @State private var correcting = false
    @State private var corrected: Plate?

    private var settings: PlateSettings {
        (try? JSONDecoder().decode(PlateSettings.self, from: stored)) ?? PlateSettings()
    }

    private var text: SetsText {
        SetsText(locale: locale)
    }

    private var fields: FieldText {
        FieldText(weightUnit: text.weightUnit, distanceUnit: text.distanceUnit, locale: locale)
    }

    private var barG: Int {
        settings.barG ?? text.weightUnit.barG
    }

    private var targetG: Int {
        settings.targetG ?? text.weightUnit.nice(100_000)
    }

    var body: some View {
        let increment = fields.increment(of: .weight)
        let amount = "\(fields.text(increment, of: .weight)) \(text.weightSymbol)"
        List {
            Section {
                ToolStepper(
                    title: Text("Total weight"),
                    less: Text("Remove \(amount)"),
                    more: Text("Add \(amount)"),
                    unit: text.weightSymbol,
                    value: Double(targetG),
                    field: .weight,
                    step: increment,
                    range: 0...1_000_000,
                    fields: fields,
                    focus: $focus,
                    id: .target
                ) { value in
                    update { $0.targetG = Int(value) }
                }
                ToolStepper(
                    title: Text("Bar"),
                    less: Text("Lighter bar"),
                    more: Text("Heavier bar"),
                    unit: text.weightSymbol,
                    value: Double(barG),
                    field: .weight,
                    step: increment,
                    range: 0...100_000,
                    fields: fields,
                    focus: $focus,
                    id: .bar
                ) { value in
                    update { $0.barG = Int(value) }
                }
            }
            Section {
                // The same height for the bar and for the two closest weights, so that nothing below moves.
                answer
                    .frame(maxWidth: .infinity, minHeight: answerHeight)
            }
            Section {
                ForEach(settings.plates.sorted { $0.weightG > $1.weightG }) { plate in
                    plateRow(plate)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                update { $0.plates.removeAll { $0.id == plate.id } }
                            }
                        }
                }
                Button("Add a plate", systemImage: "plus.circle.fill") {
                    newWeight = ""
                    adding = true
                }
            } header: {
                // In a darker grey than the system's, for a contrast of 4.5:1.
                Text("My plates")
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Plate calculator")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focus = nil
                }
            }
        }
        .onAppear {
            if let openingTargetG {
                update { $0.targetG = openingTargetG }
            }
        }
        .alert("Add a plate", isPresented: $adding) {
            TextField("Plate weight", text: $newWeight)
                .keyboardType(.decimalPad)
            Button("Add", action: addPlate)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Edit the plate", isPresented: $correcting, presenting: corrected) { plate in
            TextField("Plate weight", text: $newWeight)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let weight = typedWeight {
                    update { $0.correct(id: plate.id, weightG: weight) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var typedWeight: Int? {
        fields.value(newWeight, of: .weight).map { Int($0) }
    }

    private func update(_ change: (inout PlateSettings) -> Void) {
        var changed = settings
        change(&changed)
        if let data = try? JSONEncoder().encode(changed) {
            stored = data
        }
    }

    private func addPlate() {
        if let weight = typedWeight {
            update { $0.add(weightG: weight) }
        }
    }

    @ViewBuilder
    private var answer: some View {
        if targetG < barG {
            Text("The weight is lighter than the bar.")
        } else if targetG > barG && !settings.plates.contains(where: { $0.weightG > 0 && $0.count >= 2 }) {
            Text("Add your plates first, at least two of each weight (one on each side).")
        } else {
            switch PlateCalculator.load(barG: barG, targetG: targetG, plates: settings.plates, unit: text.weightUnit) {
            case .exact(let load):
                LoadView(load: load, text: text, fields: fields)
            case .closest(let below, let above):
                // In place of the bar, the closest weights that can be made: below on the left, above on the right.
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                layout {
                    ClosestChoice(side: Text("Below"), load: below, text: text, fields: fields) {
                        update { $0.targetG = below.totalG }
                    }
                    ClosestChoice(side: Text("Above"), load: above, text: text, fields: fields) {
                        if let above {
                            update { $0.targetG = above.totalG }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func plateRow(_ plate: Plate) -> some View {
        ToolStepper(
            title: Text(verbatim: text.toolWeight(plate.weightG)).bold(),
            less: Text("One plate of \(text.toolWeight(plate.weightG)) less"),
            more: Text("One plate of \(text.toolWeight(plate.weightG)) more"),
            value: Double(plate.count),
            field: .reps,
            step: 1,
            range: 1...100,
            fields: fields,
            focus: $focus,
            id: .plate(plate.id),
            edit: (Text("Edit the plate of \(text.toolWeight(plate.weightG))"), {
                newWeight = fields.text(Double(plate.weightG), of: .weight)
                corrected = plate
                correcting = true
            })
        ) { value in
            update { settings in
                if let index = settings.plates.firstIndex(where: { $0.id == plate.id }) {
                    settings.plates[index].count = Int(value)
                }
            }
        }
    }
}

// The loaded bar, and what goes on each side.
private struct LoadView: View {
    let load: PlateLoad
    let text: SetsText
    let fields: FieldText

    var body: some View {
        VStack(spacing: 8) {
            if !load.perSide.isEmpty {
                BarDrawing(load: load, fields: fields)
                    .frame(height: 90)
                    // Its numbers stay within the plates.
                    .dynamicTypeSize(.large)
                    .accessibilityHidden(true)
            }
            Text(verbatim: details)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plates-load")
    }

    // "Per side: 1 × 25 kg + 1 × 15 kg".
    private var details: String {
        guard !load.perSide.isEmpty else { return String(localized: "Just the bar, nothing to add.") }
        let plates = load.perSide.map { "\($0.count.formatted()) × \(text.toolWeight($0.weightG))" }.joined(separator: " + ")
        return String(localized: "Per side: \(plates)")
    }
}

// One of the closest weights that can be made, taken as the total weight when touched. Without one above, the plates
// owned don't go higher.
private struct ClosestChoice: View {
    let side: Text
    let load: PlateLoad?
    let text: SetsText
    let fields: FieldText
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 4) {
                side
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryText))
                if let load {
                    Text(verbatim: text.toolWeight(load.totalG))
                        .font(.title2.bold())
                        .monospacedDigit()
                    // Two lines kept for it, used or not, so that a long one doesn't make the choices taller.
                    Text(verbatim: perSide(load))
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryText))
                        .lineLimit(2, reservesSpace: true)
                        .minimumScaleFactor(0.8)
                    Text("Choose")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                } else {
                    Text("Not enough plates")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryText))
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(.separator))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(load == nil)
        .accessibilityElement(children: .combine)
    }

    // "Per side: 25 + 2 × 10", or the bar alone.
    private func perSide(_ load: PlateLoad) -> String {
        guard !load.perSide.isEmpty else { return String(localized: "Just the bar") }
        let plates = load.perSide.map { side in
            let weight = fields.text(Double(side.weightG), of: .weight)
            return side.count > 1 ? "\(side.count.formatted()) × \(weight)" : weight
        }
        return String(localized: "Per side: \(plates.joined(separator: " + "))")
    }
}

// One side of the bar: the heaviest plates against the collar, each as tall as it is heavy, in the colours of
// competition plates, the change plates thinner.
private struct BarDrawing: View {
    let load: PlateLoad
    let fields: FieldText

    var body: some View {
        Canvas { context, size in
            let plates = load.perSide.flatMap { Array(repeating: $0.weightG, count: $0.count) }.reversed()
            let heaviest = Double(load.perSide.map(\.weightG).max() ?? 1)
            let stems = 64.0 + 18 + 36
            let room = max(0, size.width - stems - 12 - 3 * Double(plates.count))
            let widths = plates.map { PlateColor.isChange(weightG: $0) ? 0.75 : 1.0 }
            let unit = min(19, room / widths.reduce(0, +))
            let total = stems + widths.reduce(0) { $0 + $1 * unit + 3 } + 6
            var x = (size.width - total) / 2
            let middle = size.height / 2
            let bar = GraphicsContext.Shading.color(Color(.systemGray))
            context.fill(Path(roundedRect: CGRect(x: x, y: middle - 4, width: 64, height: 8), cornerRadius: 4), with: bar)
            x += 67
            for (weight, width) in zip(plates, widths) {
                let height = 36 + 44 * Double(weight) / heaviest
                let rect = CGRect(x: x, y: middle - height / 2, width: width * unit, height: height)
                let plate = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(plate, with: .color(color(PlateColor(weightG: weight))))
                // The white ones stand out from a light background.
                context.stroke(plate, with: .color(.black.opacity(0.25)), lineWidth: 1)
                if rect.width >= 14 {
                    let label = Text(verbatim: fields.text(Double(weight), of: .weight))
                        .font(.caption2.bold())
                        .foregroundStyle(.black)
                    context.draw(context.resolve(label), at: CGPoint(x: rect.midX, y: rect.midY))
                }
                x += rect.width + 3
            }
            context.fill(Path(roundedRect: CGRect(x: x, y: middle - 6, width: 18, height: 12), cornerRadius: 3), with: bar)
            x += 18
            context.fill(Path(CGRect(x: x, y: middle - 4, width: 36, height: 8)), with: bar)
        }
    }

    private func color(_ plate: PlateColor) -> Color {
        switch plate {
        case .red: .red
        case .blue: .blue
        case .yellow: .yellow
        case .green: .green
        case .white: .white
        }
    }
}
