import HalkoCore
import SwiftUI

// An exercise of the workout being edited: its picture, name and number of sets, then how its sets are planned and
// its note. `collapsed` while the exercises are being put in order: a compact row. `grip` moves it.
struct ItemEditor<Grip: View>: View {
    @Binding var item: ItemDraft
    let exercise: Exercise?
    let fields: FieldText
    let collapsed: Bool
    let focus: FocusState<EditorField?>.Binding
    let remove: () -> Void
    @ViewBuilder let grip: Grip
    // The sets as they were when a box got the keyboard: a value typed is applied to them.
    @State private var editStart: EditStart?
    @State private var openSet: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct EditStart {
        let targets: [SetTarget]
        let shown: [SetTarget]
    }

    private var type: ExerciseType {
        exercise?.exerciseType ?? .weightReps
    }

    private var name: String {
        exercise?.localizedName ?? String(localized: "Exercise")
    }

    // Done one side then the other: reps, times and distances are per side.
    private var perSide: Bool {
        exercise?.unilateral == true && item.bySide != false
    }

    private var stacked: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // With the largest text sizes, the name goes under the picture and the buttons, which would leave it
            // too narrow a column beside them.
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ExerciseThumbnail(mediaID: exercise?.mediaIDs.first, side: collapsed ? 36 : 44)
                        Spacer()
                        removeButton
                        grip
                    }
                    title
                }
            } else {
                HStack(spacing: 10) {
                    ExerciseThumbnail(mediaID: exercise?.mediaIDs.first, side: collapsed ? 36 : 44)
                    title
                    removeButton
                    grip
                }
            }
            if !collapsed {
                Picker("Entry mode", selection: Binding { item.mode } set: { item.setMode($0) }) {
                    Text("Simple")
                        .tag(ItemMode.simple)
                    Text("Set by set")
                        .tag(ItemMode.perSet)
                }
                .pickerStyle(.segmented)
                if item.mode == .simple {
                    simpleFields
                } else {
                    setTable
                }
                if exercise?.unilateral == true && type.metrics.contains(.duration) {
                    sidesPause
                }
                note
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // Its name, whether it is done one side at a time, its number of sets.
    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: name)
                .font(.headline)
                .lineLimit(collapsed ? 1 : nil)
            if !collapsed, exercise?.unilateral == true {
                Tag(Text("One side at a time"), color: Color(.oneSide))
            }
            Text("\(item.targets.count) sets")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // Hidden while the exercises are put in order.
    @ViewBuilder
    private var removeButton: some View {
        if !collapsed {
            Button(action: remove) {
                Label("Remove \(name)", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .foregroundStyle(Color(.secondaryText))
        }
    }

    // MARK: Simple mode

    // One value for all the sets: their number, the measures of the type, the rest.
    private var simpleFields: some View {
        let first = item.targets.first { $0.kind != .warmup } ?? item.targets.first
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
        return layout {
            labeled(Text("Sets")) {
                ValueField(
                    Text("Number of sets"),
                    value: Double(item.targets.count),
                    format: { $0.map { Int($0).formatted() } ?? "" },
                    parse: { FieldText.count($0).flatMap { (1...30).contains($0) ? Double($0) : nil } },
                    focus: focus,
                    field: .setCount(item.id)
                ) { count in
                    item.targets = PlannedSetEdits.withCount(item.targets, Int(count ?? 1))
                }
            }
            ForEach(columns, id: \.self) { field in
                labeled(label(field)) {
                    box(field, label: label(field, long: true), value: first?[field], editing: .value(item.id, set: nil, field)) { value in
                        item.targets = PlannedSetEdits.settingAll(item.targets, field, to: value)
                    }
                }
            }
        }
    }

    // MARK: Set by set

    // A row for each set: warm-up or number, its values, its rest.
    private var setTable: some View {
        let shown = Warmups.filledIn(item.targets, type: type, equipment: exercise?.equipment ?? [], unit: fields.weightUnit)
        return VStack(spacing: 6) {
            if !stacked {
                HStack(spacing: 6) {
                    Text("Set")
                        .frame(width: 44)
                    ForEach(columns, id: \.self) { field in
                        label(field)
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.caption)
                .foregroundStyle(Color(.secondaryText))
            }
            ForEach(item.setIDs, id: \.self) { id in
                let index = item.setIDs.firstIndex(of: id) ?? 0
                SwipeToDelete(enabled: item.targets.count > 1, isOpen: Binding { openSet == id } set: { openSet = $0 ? id : nil }) {
                    item.removeSet(id)
                } content: {
                    setRow(index, id: id, shown: shown)
                }
            }
            Button {
                item.targets = PlannedSetEdits.addingSet(item.targets, shown: shown, type: type, unit: fields.weightUnit)
            } label: {
                Label("Add a set", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func setRow(_ index: Int, id: UUID, shown: [SetTarget]) -> some View {
        let target = item.targets[index]
        let number = index + 1
        let kind = kindButton(index, id: id, shown: shown)
        let boxes = ForEach(columns, id: \.self) { field in
            let spoken = String(localized: "Set \(number), \(label(field, long: true))")
            let workedOut = PlannedSetEdits.isWorkedOut(target, field, type: type)
            let valueBox = box(
                field,
                label: spoken,
                value: shown[index][field],
                workedOut: workedOut,
                canWorkOut: PlannedSetEdits.canWorkOut(target, field, type: type),
                editing: .value(item.id, set: index, field)
            ) { value in
                let start = editStart ?? EditStart(targets: item.targets, shown: shown)
                item.targets = PlannedSetEdits.setting(start.targets, field, to: value, at: index, from: start.shown[index][field])
            }
            if stacked {
                labeled(label(field)) {
                    valueBox
                }
            } else {
                valueBox
                    .frame(maxWidth: .infinity)
            }
        }
        if stacked {
            VStack(alignment: .leading, spacing: 6) {
                kind
                boxes
            }
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 6) {
                kind
                    .frame(width: 44)
                boxes
            }
        }
    }

    // "W" for a warm-up, the number of a working set: a tap switches between the two.
    private func kindButton(_ index: Int, id: UUID, shown: [SetTarget]) -> some View {
        let warmup = item.targets[index].kind == .warmup
        let working = item.targets[...index].count(where: { $0.kind != .warmup })
        return Button {
            item.targets = PlannedSetEdits.switchingKind(item.targets, shown: shown, at: index, type: type)
        } label: {
            Group {
                if warmup {
                    Text("W")
                } else {
                    Text(verbatim: working.formatted())
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(warmup ? Color(.warmup) : .primary)
            .frame(maxWidth: stacked ? 88 : .infinity, minHeight: 44)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Set \(index + 1)"))
        .accessibilityValue(warmup ? Text("Warm-up") : Text("Working set \(working)"))
        .accessibilityHint(Text("Switches between warm-up and working set."))
        .accessibilityActions {
            if item.targets.count > 1 {
                Button("Delete set") {
                    item.removeSet(id)
                }
            }
        }
    }

    // MARK: Sides, note

    // A timed exercise done one side then the other: whether to pause to change sides here, and how long.
    private var sidesPause: some View {
        let pauses = item.bySide != false
        return VStack(spacing: 8) {
            Toggle("Pause to change sides", isOn: Binding { pauses } set: { item.bySide = $0 ? nil : false })
            HStack {
                Text("Pause duration")
                Spacer()
                ValueField(
                    Text("Pause duration"),
                    value: Double(item.switchS ?? defaultSwitchSidesS),
                    format: { fields.text($0, of: .rest) },
                    parse: { FieldText.seconds($0).flatMap { $0 <= 600 ? Double($0) : nil } },
                    focus: focus,
                    field: .sidesPause(item.id)
                ) { seconds in
                    item.switchS = seconds.map { Int($0) }
                }
                .frame(width: stacked ? 160 : 96)
            }
            .disabled(!pauses)
            .opacity(pauses ? 1 : 0.5)
        }
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(Color(.secondaryText))
                .accessibilityHidden(true)
            TextField(text: $item.note, prompt: Text("Add a note (machine setting, cue…)").foregroundStyle(Color(.secondaryText)), axis: .vertical) {
                Text("Note for \(name)")
            }
            .focused(focus, equals: .note(item.id))
            .font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
    }

    // MARK: Boxes

    // The measures of the type, then the rest.
    private var columns: [SetField] {
        type.metrics.map(SetField.init) + [.rest]
    }

    private func box(
        _ field: SetField,
        label: String,
        value: Double?,
        workedOut: Bool = false,
        canWorkOut: Bool = false,
        editing: EditorField,
        commit: @escaping (Double?) -> Void
    ) -> some View {
        let targets = item.targets
        return ValueField(
            Text(verbatim: label),
            value: value,
            format: { fields.text($0, of: field) },
            parse: { fields.value($0, of: field) },
            keyboard: field == .weight || field == .distance ? .decimalPad : .numberPad,
            workedOut: workedOut,
            canWorkOut: canWorkOut,
            focus: focus,
            field: editing,
            begin: {
                editStart = EditStart(
                    targets: targets,
                    shown: Warmups.filledIn(targets, type: type, equipment: exercise?.equipment ?? [], unit: fields.weightUnit)
                )
            },
            commit: commit
        )
    }

    // A box under its label, or beside it with the largest text sizes.
    @ViewBuilder
    private func labeled<Box: View>(_ label: Text, @ViewBuilder box: () -> Box) -> some View {
        if stacked {
            HStack {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                box()
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 4) {
                label
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                box()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // The title of a column: "kg", "Reps", "Time/side", "Rest"…
    private func label(_ field: SetField) -> Text {
        Text(verbatim: label(field, long: false))
    }

    // `long`: as VoiceOver reads it, the units in words.
    private func label(_ field: SetField, long: Bool) -> String {
        fields.columnTitle(field, type: type, perSide: perSide, long: long)
    }
}
