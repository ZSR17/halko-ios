import HalkoCore
import SwiftUI

// The plates to put on the bar for a weight, from the plates owned, which are kept on this device.
struct PlatesView: View {
    // Opened from the 1RM calculator with a weight to make.
    var openingTargetG: Int?
    @AppStorage(PlateSettings.storageKey) private var stored = Data()
    @Environment(\.locale) private var locale
    @FocusState private var focus: ToolField?
    @State private var adding = false
    @State private var newWeight = ""

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
                answer
            }
            Section("My plates") {
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
    }

    private func update(_ change: (inout PlateSettings) -> Void) {
        var changed = settings
        change(&changed)
        if let data = try? JSONEncoder().encode(changed) {
            stored = data
        }
    }

    // Two of them, one on each side, or two more of a weight already there.
    private func addPlate() {
        guard let weight = fields.value(newWeight, of: .weight).map({ Int($0) }), weight > 0 else { return }
        update { settings in
            if let index = settings.plates.firstIndex(where: { $0.weightG == weight }) {
                settings.plates[index].count += 2
            } else {
                settings.plates.append(Plate(weightG: weight, count: 2))
            }
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
                Text("You can't make \(text.toolWeight(targetG)) with your plates. The closest:")
                closest(below)
                if let above {
                    closest(above)
                } else {
                    Text("You don't have enough plates to go higher.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryText))
                }
            }
        }
    }

    private func closest(_ load: PlateLoad) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(text.toolWeight(load.totalG)) in total, bar included")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Choose") {
                    update { $0.targetG = load.totalG }
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityLabel(Text("Choose \(text.toolWeight(load.totalG))"))
            }
            LoadView(load: load, text: text, fields: fields)
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
            id: .plate(plate.id)
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
                    .accessibilityHidden(true)
            }
            Text(verbatim: details)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    // "Per side: 1 × 25 kg + 1 × 15 kg".
    private var details: String {
        guard !load.perSide.isEmpty else { return String(localized: "Just the bar, nothing to add.") }
        let plates = load.perSide.map { "\($0.count.formatted()) × \(text.toolWeight($0.weightG))" }.joined(separator: " + ")
        return String(localized: "Per side: \(plates)")
    }
}

// One side of the bar: the heaviest plates against the collar, each as tall as it is heavy.
private struct BarDrawing: View {
    let load: PlateLoad
    let fields: FieldText

    var body: some View {
        Canvas { context, size in
            let plates = load.perSide.flatMap { Array(repeating: $0.weightG, count: $0.count) }.reversed()
            let heaviest = Double(load.perSide.map(\.weightG).max() ?? 1)
            let stems = 64.0 + 18 + 36
            let room = max(0, size.width - stems - 12)
            let plateWidth = min(19, room / Double(plates.count) - 3)
            let total = stems + Double(plates.count) * (plateWidth + 3) + 6
            var x = (size.width - total) / 2
            let middle = size.height / 2
            let bar = GraphicsContext.Shading.color(Color(.systemGray))
            context.fill(Path(roundedRect: CGRect(x: x, y: middle - 4, width: 64, height: 8), cornerRadius: 4), with: bar)
            x += 67
            for weight in plates {
                let height = 36 + 44 * Double(weight) / heaviest
                let rect = CGRect(x: x, y: middle - height / 2, width: plateWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color(weight)))
                if plateWidth >= 14 {
                    let label = Text(verbatim: fields.text(Double(weight), of: .weight))
                        .font(.caption2.bold())
                        .foregroundStyle(.black)
                    context.draw(context.resolve(label), at: CGPoint(x: rect.midX, y: rect.midY))
                }
                x += plateWidth + 3
            }
            context.fill(Path(roundedRect: CGRect(x: x, y: middle - 6, width: 18, height: 12), cornerRadius: 3), with: bar)
            x += 18
            context.fill(Path(CGRect(x: x, y: middle - 4, width: 36, height: 8)), with: bar)
        }
    }

    private func color(_ grams: Int) -> Color {
        switch grams {
        case 25_000...: .red
        case 20_000..<25_000: .yellow
        case 15_000..<20_000: .blue
        case 10_000..<15_000: .green
        default: Color(.systemGray3)
        }
    }
}
