import HalkoCore
import os
import SwiftData
import SwiftUI

// The estimated 1RM of a set, typed or taken from the best one done of an exercise, with the reps it was stopped short
// of failure, and what it means at lower loads: a line opens the plates for that weight.
struct OneRepMaxView: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "tools")
    private static let percentages = [95, 90, 85, 80, 75]

    @AppStorage("oneRepMaxWeightG") private var storedWeightG: Int?
    @AppStorage("oneRepMaxReps") private var storedReps = 8
    @AppStorage("oneRepMaxReserve") private var reserve = 0
    @AppStorage("oneRepMaxFormula") private var formula = OneRepMaxFormula.brzycki
    @AppStorage("oneRepMaxExercise") private var exerciseID: String?
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @FocusState private var focus: ToolField?
    @State private var lifted: [LiftedExercise] = []

    private var text: SetsText {
        SetsText(locale: locale)
    }

    private var fields: FieldText {
        FieldText(weightUnit: text.weightUnit, distanceUnit: text.distanceUnit, locale: locale)
    }

    private var best: LiftedExercise.LiftedSet? {
        lifted.first { $0.exercise.id == exerciseID }?.best(formula: formula)
    }

    private var weightG: Int {
        best?.weightG ?? storedWeightG ?? text.weightUnit.nice(80_000)
    }

    private var reps: Int {
        best?.reps ?? storedReps
    }

    var body: some View {
        let increment = fields.increment(of: .weight)
        let amount = "\(fields.text(increment, of: .weight)) \(text.weightSymbol)"
        let toFailure = min(OneRepMax.maxReps, reps + reserve)
        let estimate = OneRepMax.estimate(weightG: weightG, reps: toFailure, formula: formula)
        List {
            if !lifted.isEmpty {
                Section {
                    Picker("Exercise", selection: $exerciseID) {
                        Text("Choose")
                            .tag(String?.none)
                        ForEach(lifted, id: \.exercise.id) { lifted in
                            Text(verbatim: lifted.exercise.localizedName)
                                .tag(Optional(lifted.exercise.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("Optional: fills in the load and reps with your best set.")
                        .foregroundStyle(Color(.secondaryText))
                }
            }
            Section {
                ToolStepper(
                    title: Text("Load"),
                    less: Text("Remove \(amount)"),
                    more: Text("Add \(amount)"),
                    unit: text.weightSymbol,
                    value: Double(weightG),
                    field: .weight,
                    step: increment,
                    range: 0...1_000_000,
                    fields: fields,
                    focus: $focus,
                    id: .load
                ) { value in
                    edit(weightG: Int(value), reps: reps)
                }
                ToolStepper(
                    title: Text("Repetitions"),
                    less: Text("One rep less"),
                    more: Text("One rep more"),
                    value: Double(reps),
                    field: .reps,
                    step: 1,
                    range: 1...Double(OneRepMax.maxReps),
                    fields: fields,
                    focus: $focus,
                    id: .reps
                ) { value in
                    edit(weightG: weightG, reps: Int(value))
                }
                ToolStepper(
                    title: Text("In reserve"),
                    less: Text("One rep less in reserve"),
                    more: Text("One rep more in reserve"),
                    value: Double(reserve),
                    field: .reps,
                    step: 1,
                    range: 0...10,
                    fields: fields,
                    focus: $focus,
                    id: .reserve
                ) { value in
                    reserve = Int(value)
                }
            }
            Section("Method") {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(OneRepMaxFormula.allCases, id: \.self) { method in
                        Toggle(isOn: Binding { formula == method } set: { if $0 { formula = method } }) {
                            Text(verbatim: method.name)
                        }
                        .toggleStyle(ChipToggleStyle())
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Estimated 1RM")
                            .foregroundStyle(Color(.secondaryText))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: oneRepMax(estimate))
                            .font(.largeTitle.bold())
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    if reserve > 0 {
                        Text("Counted as \(toFailure) reps to failure (\(reps) done + \(reserve) in reserve)")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryText))
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                ForEach(Self.percentages, id: \.self) { percent in
                    NavigationLink {
                        PlatesView(openingTargetG: text.weightUnit.rounded(Double(estimate * percent / 100), step: 0.1))
                    } label: {
                        row(percent, estimate: estimate)
                    }
                }
            } footer: {
                Text("Tap a line to see the plates to put on the bar.")
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("1RM calculator")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focus = nil
                }
            }
        }
        .task {
            do {
                lifted = try context.liftedExercises()
            } catch {
                Self.logger.error("Cannot read the sets done: \(String(describing: error))")
            }
        }
    }

    // Values changed by hand are no longer those of the exercise.
    private func edit(weightG: Int, reps: Int) {
        storedWeightG = weightG
        storedReps = reps
        exerciseID = nil
    }

    private func oneRepMax(_ grams: Int) -> String {
        text.record(ExerciseRecord(kind: .oneRepMax, value: Double(grams)))
    }

    private func row(_ percent: Int, estimate: Int) -> some View {
        HStack {
            Text(verbatim: (Double(percent) / 100).formatted(.percent))
                .foregroundStyle(Color(.secondaryText))
                .frame(minWidth: 56, alignment: .leading)
            Text(verbatim: oneRepMax(estimate * percent / 100))
                .frame(maxWidth: .infinity, alignment: .leading)
            repsText(percent)
                .foregroundStyle(Color(.secondaryText))
        }
        .font(.subheadline)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private func repsText(_ percent: Int) -> Text {
        if let reps = OneRepMax.reps(atPercent: percent, formula: formula) {
            return Text("≈ \(reps) reps")
        }
        return Text("\(OneRepMax.maxReps)+ reps")
    }
}

extension OneRepMaxFormula {
    // The names of their authors.
    var name: String {
        switch self {
        case .brzycki: "Brzycki"
        case .epley: "Epley"
        case .mcglothin: "McGlothin"
        case .lombardi: "Lombardi"
        case .mayhew: "Mayhew"
        case .oconner: "O'Conner"
        case .wathen: "Wathen"
        }
    }
}
