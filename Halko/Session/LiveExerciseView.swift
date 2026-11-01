import HalkoCore
import SwiftUI

// An exercise of the session: its picture, name and plan, then a row for each set (warm-up or number, last time's
// values, the values, a check) and « Add a set ». As in the workout editor, a set swiped left shows Delete; « … » deletes
// the exercise. Folded to its name once every set is done; a tap opens it again, until the next set is validated.
struct LiveExerciseView: View {
    let index: Int
    let table: LiveTable
    let folded: Bool
    let unfold: () -> Void
    let focus: FocusState<LiveField?>.Binding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // The set whose Delete button shows.
    @State private var openSet: Int?
    @State private var confirmingDelete = false

    var body: some View {
        if folded {
            foldedRow
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                if !dynamicTypeSize.isAccessibilitySize {
                    columnTitles
                }
                // A set is known by its index in the exercise.
                ForEach(table.setNumbers(index), id: \.self) { set in
                    SwipeToDelete(
                        enabled: table.state.canDeleteSet(of: index),
                        isOpen: Binding { openSet == set } set: { openSet = $0 ? set : nil }
                    ) {
                        table.actions.deleteSet(index, set)
                    } content: {
                        LiveSetRow(item: index, set: set, table: table, focus: focus)
                    }
                    .accessibilityActions {
                        if table.state.canDeleteSet(of: index) {
                            Button("Delete set") {
                                table.actions.deleteSet(index, set)
                            }
                        }
                    }
                }
                addSet
            }
            .confirmationDialog(
                "Delete “\(table.name(index))” from this session?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete the exercise", role: .destructive) {
                    table.actions.deleteExercise(index)
                }
            } message: {
                Text("The sets done of it are deleted too.")
            }
        }
    }

    // Like the workout editor's: a set like the last one.
    private var addSet: some View {
        Button {
            table.actions.addSet(index)
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

    private var item: PlanItem {
        table.plan.items[index]
    }

    private var foldedRow: some View {
        let count = table.plan.setCount(index)
        return Button {
            unfold()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(verbatim: table.name(index))
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "\(count.formatted())/\(count.formatted())")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text("Done"))
        .accessibilityHint(Text("Shows its sets."))
    }

    private var header: some View {
        let exercise = table.exercise(index)
        let sets = PlannedSets(item.targets, type: item.exerciseType, equipment: item.equipment, unit: table.fields.weightUnit)
        return HStack(alignment: .top, spacing: 12) {
            ExerciseThumbnail(mediaID: exercise?.mediaIDs.first)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: table.name(index))
                    .font(.headline)
                if !sets.working.isEmpty {
                    Text(verbatim: table.text.working(sets, type: item.exerciseType, perSide: item.unilateral, sidesPauseS: item.sidesPauseS))
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryText))
                }
                if item.supersetGroup != nil {
                    Tag(Text("Superset"), color: Color(.superset))
                }
                if let note = item.note {
                    Label {
                        Text(verbatim: note)
                    } icon: {
                        Image(systemName: "pencil")
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if table.state.canDeleteExercise {
                Menu {
                    Button("Delete the exercise", systemImage: "trash", role: .destructive) {
                        deleteExercise()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("More actions for \(table.name(index))"))
            }
        }
    }

    // Asked first when sets of it are done.
    private func deleteExercise() {
        let done = table.setNumbers(index).contains { table.logged[LivePlan.key(item.itemID, $0)] != nil }
        if done {
            confirmingDelete = true
        } else {
            table.actions.deleteExercise(index)
        }
    }

    private var columnTitles: some View {
        HStack(spacing: 8) {
            Text("Set")
                .frame(width: 44)
            Text("Previous")
                .frame(maxWidth: .infinity)
            ForEach(table.metrics(index), id: \.self) { field in
                Text(verbatim: table.columnTitle(field, item: index, long: false))
                    .frame(maxWidth: .infinity)
            }
            Color.clear
                .frame(width: 44, height: 1)
        }
        .font(.caption)
        .foregroundStyle(Color(.secondaryText))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityHidden(true)
    }
}

// A set of an exercise of the session. The current one stands out; during the rest its values are in boxes to change
// them. A set done shows its values in boxes too, to correct them.
private struct LiveSetRow: View {
    let item: Int
    let set: Int
    let table: LiveTable
    let focus: FocusState<LiveField?>.Binding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var key: String {
        LivePlan.key(table.plan.items[item].itemID, set)
    }

    private var isCurrent: Bool {
        table.step.map { $0.item == item && $0.set == set } ?? false
    }

    private var isDone: Bool {
        table.logged[key] != nil
    }

    var body: some View {
        let values = table.values(item, set: set)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        number
                        Spacer()
                        check
                    }
                    ForEach(table.metrics(item), id: \.self) { field in
                        HStack {
                            Text(verbatim: table.columnTitle(field, item: item, long: false))
                                .foregroundStyle(Color(.secondaryText))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityHidden(true)
                            cell(field, values: values)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    previous
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    number
                        .frame(width: 44)
                    previous
                        .frame(maxWidth: .infinity)
                    ForEach(table.metrics(item), id: \.self) { field in
                        cell(field, values: values)
                            .frame(maxWidth: .infinity)
                    }
                    check
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .background(isCurrent ? Color(.tertiarySystemFill) : .clear, in: .rect(cornerRadius: 10))
        .padding(.horizontal, -8)
    }

    private var number: some View {
        let warmup = table.plan.target(item, set: set).kind == .warmup
        return table.number(item, set: set)
            .font(.body.weight(isCurrent ? .bold : .semibold))
            .foregroundStyle(warmup ? Color(.warmup) : isCurrent ? Color.accentColor : .primary)
            .accessibilityLabel(Text(verbatim: table.spokenNumber(item, set: set)))
            .accessibilityValue(isCurrent ? Text("Current set") : isDone ? Text("Done") : Text(verbatim: ""))
    }

    private var previous: some View {
        let last = table.previous[table.plan.items[item].exerciseID]?[set]
        return Text(verbatim: last.map { table.setText(item, values: $0) } ?? "–")
            .font(.subheadline)
            .foregroundStyle(Color(.secondaryText))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(Text("Previous"))
            .accessibilityValue(Text(verbatim: last.map { table.setText(item, values: $0) } ?? String(localized: "none")))
    }

    @ViewBuilder
    private func cell(_ field: SetField, values: SetValues) -> some View {
        let spoken = String(localized: "\(table.spokenNumber(item, set: set)), \(table.columnTitle(field, item: item, long: true))")
        if isDone {
            SetCell(label: spoken, value: values[field], field: field, fields: table.fields, boxed: false, focus: focus, id: .value(key, field)) { value in
                var corrected = values
                corrected[field] = value
                table.actions.correct(item, set, corrected)
            }
        } else if isCurrent && table.state.restEndsAt != nil {
            SetCell(label: spoken, value: values[field], field: field, fields: table.fields, boxed: true, focus: focus, id: .value(key, field)) { value in
                var edited = values
                edited[field] = value
                table.actions.edit(key, edited)
            }
        } else {
            Text(verbatim: values[field].map { table.fields.text($0, of: field) } ?? "–")
                .font(isCurrent ? .body.weight(.bold) : .body)
                .foregroundStyle(isCurrent ? .primary : Color(.secondaryText))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(Text(verbatim: spoken))
                .accessibilityValue(Text(verbatim: values[field].map { table.fields.text($0, of: field) } ?? String(localized: "none")))
        }
    }

    // A set done: a filled check, which undoes it. The current set: an empty one, which validates it.
    @ViewBuilder
    private var check: some View {
        if isDone {
            Button {
                table.actions.undo(item, set)
            } label: {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color(.onAccent))
                    .frame(width: 32, height: 32)
                    .background(.tint, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Undo \(table.spokenNumber(item, set: set))"))
        } else if isCurrent {
            Button {
                table.actions.validate()
            } label: {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Validate \(table.spokenNumber(item, set: set))"))
        } else {
            Circle()
                .strokeBorder(Color(.separator), lineWidth: 2)
                .frame(width: 32, height: 32)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }
}

// A value of a set in a box: kept when the box loses the keyboard. `boxed` false: shown as plain text until tapped.
struct SetCell: View {
    let label: String
    let value: Double?
    let field: SetField
    let fields: FieldText
    let boxed: Bool
    let focus: FocusState<LiveField?>.Binding
    let id: LiveField
    let commit: (Double?) -> Void
    @State private var text: String
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 36

    init(
        label: String,
        value: Double?,
        field: SetField,
        fields: FieldText,
        boxed: Bool,
        focus: FocusState<LiveField?>.Binding,
        id: LiveField,
        commit: @escaping (Double?) -> Void
    ) {
        self.label = label
        self.value = value
        self.field = field
        self.fields = fields
        self.boxed = boxed
        self.focus = focus
        self.id = id
        self.commit = commit
        _text = State(initialValue: fields.text(value, of: field))
    }

    private var isFocused: Bool {
        focus.wrappedValue == id
    }

    var body: some View {
        TextField(text: $text, prompt: Text(verbatim: "–").foregroundStyle(Color(.secondaryText))) {
            Text(verbatim: label)
        }
        .focused(focus, equals: id)
        .keyboardType(field == .weight || field == .distance ? .decimalPad : .numberPad)
        .multilineTextAlignment(.center)
        .font(.body.weight(boxed ? .bold : .regular))
        .monospacedDigit()
        .padding(.horizontal, 4)
        .frame(minHeight: max(36, height))
        .background {
            if boxed || isFocused {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(.secondaryText), lineWidth: 1.5)
            }
        }
        .accessibilityHint(Text("Double tap to change it."))
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            if let typed = fields.value(text, of: field), typed != value {
                commit(typed)
            }
            text = fields.text(value, of: field)
        }
        .onChange(of: value) { _, value in
            if !isFocused {
                text = fields.text(value, of: field)
            }
        }
    }
}
