import HalkoCore
import os
import SwiftData
import SwiftUI

// Changing a workout, in a sheet: its name, its exercises in order, how each one's sets are planned, the supersets
// and the notes. Nothing is written before ✓, then only to the local database: the same offline.
struct WorkoutEditor: View {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

    let workout: Workout
    // As the sheet opened, to know whether anything changed.
    @State private var original: WorkoutDraft
    @State private var draft: WorkoutDraft
    @State private var confirmsDiscard = false
    @State private var picking = false
    @State private var showsHelp = false
    @State private var failed = false
    @FocusState private var focus: EditorField?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    // `items`: its exercises, in order.
    init(workout: Workout, items: [WorkoutItem]) {
        self.workout = workout
        let draft = WorkoutDraft(workout, items: items)
        _original = State(initialValue: draft)
        _draft = State(initialValue: draft)
    }

    private var hasChanges: Bool {
        draft.differs(from: original)
    }

    private var fields: FieldText {
        FieldText(weightUnit: .preferred(for: locale), distanceUnit: .preferred(for: locale), locale: locale)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workout name")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryText))
                            .accessibilityHidden(true)
                        TextField("Workout name", text: $draft.name)
                            .font(.title2.weight(.bold))
                            .focused($focus, equals: .name)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    }
                    HStack {
                        summary
                            .font(.subheadline)
                            .foregroundStyle(Color(.secondaryText))
                        Spacer()
                        Button("How editing works", systemImage: "info.circle") {
                            showsHelp = true
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color(.secondaryText))
                        .frame(minWidth: 44, minHeight: 44)
                        .popover(isPresented: $showsHelp) {
                            EditorHelp()
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                    EditorItems(draft: $draft, fields: fields, focus: $focus)
                    Button {
                        picking = true
                    } label: {
                        Label("Add an exercise", systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                .padding([.horizontal, .bottom])
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // ✕ and ✓, as in the exercise editor. With changes, ✕ turns into "Discard Changes": a tap elsewhere
                // keeps editing.
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        if hasChanges {
                            confirmsDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog("Are you sure you want to discard changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) {
                            dismiss()
                        }
                    }
                    .accessibilityLabel(Text("Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        save()
                    }
                    .accessibilityLabel(Text("Save"))
                    .disabled(!draft.canSave || !hasChanges)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focus = nil
                    }
                }
            }
            // Pulled down with changes, the sheet stays: ✕ asks before losing them.
            .interactiveDismissDisabled(hasChanges)
            .sheet(isPresented: $picking) {
                ExercisePicker { exercises in
                    add(exercises)
                }
            }
            .alert("The workout could not be saved.", isPresented: $failed) {
                Button("OK") {}
            }
        }
    }

    // "5 exercises · 1 superset"
    private var summary: Text {
        let exercises = Text("\(draft.items.count) exercises")
        let supersets = draft.supersetCount
        return supersets == 0 ? exercises : Text("\(exercises) · \(Text("\(supersets) supersets"))")
    }

    // At the end, each from what is known of it.
    private func add(_ exercises: [Exercise]) {
        let unit = fields.weightUnit
        for exercise in exercises {
            do {
                draft.items.append(try modelContext.startingItem(for: exercise, unit: unit))
            } catch {
                Self.logger.error("Cannot read what is known of the exercise: \(String(describing: error))")
                draft.items.append(ItemDraft(exerciseID: exercise.id, mode: .simple, targets: PlannedSetEdits.defaultTargets(exercise.exerciseType, unit: unit)))
            }
        }
    }

    private func save() {
        do {
            try modelContext.saveWorkout(workout, with: draft)
            dismiss()
        } catch {
            Self.logger.error("Cannot save the workout: \(String(describing: error))")
            failed = true
        }
    }
}

// What the (i) of the editor explains, instead of help texts in every exercise.
private struct EditorHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("In gray italics: worked out from the first working set. Type a value to set it.", systemImage: "italic")
            Label("Tap W or a set number to switch between warm-up and working set.", systemImage: "hand.tap")
            Label("Swipe a set left to delete it.", systemImage: "arrow.left")
            Label("Drag the handle to put the exercises in order.", systemImage: "line.3.horizontal")
        }
        .font(.subheadline)
        .padding()
        .frame(idealWidth: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// A row of the list of exercises being edited: the tag of a superset above its exercises, or an exercise.
private enum EditorEntry: Identifiable {
    case superset(group: String, items: [ItemDraft.ID])
    case item(ItemDraft.ID)

    var id: String {
        switch self {
        case .superset(let group, _): "superset-\(group)"
        case .item(let id): id
        }
    }

    // A superset with its exercises, or an exercise alone, starts with it.
    func startsBlock(in draft: WorkoutDraft) -> Bool {
        switch self {
        case .superset: true
        case .item(let id): draft.items.first { $0.id == id }?.supersetGroup == nil
        }
    }

    static func entries(of draft: WorkoutDraft) -> [EditorEntry] {
        var entries: [EditorEntry] = []
        for (index, item) in draft.items.enumerated() {
            if let group = item.supersetGroup, index == 0 || draft.items[index - 1].supersetGroup != group {
                entries.append(.superset(group: group, items: draft.items[index...].prefix { $0.supersetGroup == group }.map(\.id)))
            }
            entries.append(.item(item.id))
        }
        return entries
    }
}

// What a handle moves: an exercise, or a superset with its exercises.
private struct Moving: Equatable {
    // The row of the handle held.
    let grabbed: String
    let entries: [String]
    let items: [ItemDraft.ID]
    let isBlock: Bool
    var fingerY: CGFloat
}

// The exercises being edited, between the links of the supersets. Holding a handle folds them all into compact rows:
// the one held follows the finger, its place shows dashed, and they unfold where it is let go.
private struct EditorItems: View {
    @Binding var draft: WorkoutDraft
    let fields: FieldText
    let focus: FocusState<EditorField?>.Binding
    @Query private var exercises: [Exercise]
    @State private var moving: Moving?
    // Where each row is laid out, before it is moved aside.
    @State private var frames: [String: CGRect] = [:]

    private static let space = "workout-editor-items"

    init(draft: Binding<WorkoutDraft>, fields: FieldText, focus: FocusState<EditorField?>.Binding) {
        _draft = draft
        self.fields = fields
        self.focus = focus
        _exercises = Query(filter: Exercise.withIDs(draft.wrappedValue.items.map(\.exerciseID)))
    }

    var body: some View {
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = EditorEntry.entries(of: draft)
        let plan = moving.flatMap { reorderPlan(for: $0, entries: entries) }
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                row(entry, exercises: byID)
                    .zIndex(moving?.entries.contains(entry.id) == true ? 1 : 0)
                    .offset(y: plan?.offsets[entry.id] ?? 0)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                        frames[entry.id] = frame
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let gap = plan?.gap {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: gap.width, height: max(0, gap.height - 8))
                    .offset(x: gap.minX, y: gap.minY)
                    .accessibilityHidden(true)
            }
        }
        .coordinateSpace(.named(Self.space))
        .sensoryFeedback(.selection, trigger: plan?.slot)
    }

    @ViewBuilder
    private func row(_ entry: EditorEntry, exercises: [String: Exercise]) -> some View {
        let collapsed = moving != nil
        switch entry {
        case .superset(_, let items):
            HStack {
                Tag(Text("Superset · no rest in between"), color: Color(.superset))
                Spacer()
                grip(Moving(grabbed: entry.id, entries: [entry.id] + items, items: items, isBlock: true, fingerY: 0), label: Text("Move the superset"))
            }
            .padding(.leading, 12)
            .padding(.bottom, collapsed ? 0 : 4)
            .supersetBar()
        case .item(let id):
            if let index = draft.items.firstIndex(where: { $0.id == id }) {
                let item = draft.items[index]
                let exercise = exercises[item.exerciseID]
                let name = exercise?.localizedName ?? String(localized: "Exercise")
                let linked = draft.isLinked(after: index)
                VStack(spacing: 0) {
                    ItemEditor(
                        item: binding(for: item),
                        exercise: exercise,
                        fields: fields,
                        collapsed: collapsed,
                        focus: focus,
                        remove: { draft.remove(id) }
                    ) {
                        grip(Moving(grabbed: id, entries: [id], items: [id], isBlock: false, fingerY: 0), label: Text("Move \(name)"))
                    }
                    .padding(.leading, item.supersetGroup == nil ? 0 : 12)
                    .padding(.bottom, collapsed ? 8 : 0)
                    .supersetBar(item.supersetGroup != nil)
                    if !collapsed && index + 1 < draft.items.count {
                        link(after: index, linked: linked)
                            .padding(.leading, linked ? 12 : 0)
                            .supersetBar(linked)
                    }
                }
            }
        }
    }

    // By its id: the exercise may have moved, or gone, since the row was made.
    private func binding(for item: ItemDraft) -> Binding<ItemDraft> {
        Binding {
            draft.items.first { $0.id == item.id } ?? item
        } set: { changed in
            if let index = draft.items.firstIndex(where: { $0.id == item.id }) {
                draft.items[index] = changed
            }
        }
    }

    // Between two exercises: makes them a superset, or splits it.
    private func link(after index: Int, linked: Bool) -> some View {
        Button {
            draft.toggleSuperset(after: index)
        } label: {
            Group {
                if linked {
                    Label("Linked, no rest · unlink", systemImage: "link")
                } else {
                    Text("Link as a superset with the next")
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(linked ? Color(.superset) : Color(.secondaryText))
        .accessibilityAddTraits(linked ? .isSelected : [])
    }

    // The handle: held and dragged, it moves `what`; VoiceOver moves it a place up or down.
    private func grip(_ what: Moving, label: Text) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.body.weight(.semibold))
            .foregroundStyle(moving?.grabbed == what.grabbed ? Color.accentColor : Color(.secondaryText))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { value in
                if moving == nil {
                    focus.wrappedValue = nil
                    withAnimation(.snappy) {
                        moving = what
                    }
                }
                moving?.fingerY = value.location.y
            }.onEnded { _ in
                drop()
            })
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityActions {
                Button("Move up") {
                    step(what, by: -1)
                }
                Button("Move down") {
                    step(what, by: 1)
                }
            }
    }

    // Where the rows go while `what` is held: the rows it passed move aside to leave it a place, the nearest to it.
    private func reorderPlan(for what: Moving, entries: [EditorEntry]) -> ReorderPlan? {
        let others = entries.filter { !what.entries.contains($0.id) }
        return ReorderPlan(
            order: entries.map(\.id),
            frames: frames,
            moved: what.entries,
            grabbed: what.grabbed,
            fingerY: what.fingerY
        ) { slot in
            if what.isBlock {
                // Between blocks only.
                slot == others.count || others[slot].startsBlock(in: draft)
            } else if slot > 0, case .superset = others[slot - 1] {
                // Under the tag of a superset: the same as above it.
                false
            } else {
                true
            }
        }
    }

    private func drop() {
        guard let what = moving else { return }
        let entries = EditorEntry.entries(of: draft)
        withAnimation(.snappy) {
            moving = nil
            guard let plan = reorderPlan(for: what, entries: entries), plan.slot != plan.originalSlot else { return }
            let others = entries.filter { !what.entries.contains($0.id) }
            // The first exercise below the place it was let go in.
            let before = others[plan.slot...].lazy.compactMap { entry -> ItemDraft.ID? in
                if case .item(let id) = entry { id } else { nil }
            }.first
            if what.isBlock {
                draft.moveBlock(what.items, before: before)
            } else {
                draft.move(what.items[0], before: before)
            }
        }
    }

    // One place up or down: past the exercise above or below, or for a superset past the block above or below.
    private func step(_ what: Moving, by offset: Int) {
        let blocks = what.isBlock ? Self.runs(of: draft.items) : draft.items.map { [$0.id] }
        guard let index = blocks.firstIndex(where: { $0.contains(what.items[0]) }) else { return }
        let target = index + offset
        guard blocks.indices.contains(target) else { return }
        let before = offset < 0 ? blocks[target].first : blocks.indices.contains(target + 1) ? blocks[target + 1].first : nil
        withAnimation(.snappy) {
            if what.isBlock {
                draft.moveBlock(what.items, before: before)
            } else {
                draft.move(what.items[0], before: before)
            }
        }
    }
}

extension EditorItems {
    // The ids of the exercises in blocks: those of a superset together, every other one alone.
    fileprivate static func runs(of items: [ItemDraft]) -> [[ItemDraft.ID]] {
        var runs: [[ItemDraft.ID]] = []
        for (index, item) in items.enumerated() {
            if index > 0, let group = item.supersetGroup, items[index - 1].supersetGroup == group {
                runs[runs.count - 1].append(item.id)
            } else {
                runs.append([item.id])
            }
        }
        return runs
    }
}

// Where the rows of the list go while some are held: those held follow the finger; the others make room for them at
// the allowed place nearest to them.
private struct ReorderPlan {
    // The place among the rows not held, and the one they were taken from.
    let slot: Int
    let originalSlot: Int
    let offsets: [String: CGFloat]
    // Where they would go, dashed.
    let gap: CGRect

    init?(order: [String], frames: [String: CGRect], moved: [String], grabbed: String, fingerY: CGFloat, allowed: (Int) -> Bool) {
        guard let first = order.first, let top = frames[first]?.minY, let held = frames[grabbed],
              let movedTop = moved.first.flatMap({ frames[$0]?.minY }), let start = order.firstIndex(of: moved[0]) else {
            return nil
        }
        let height = { (id: String) in frames[id]?.height ?? 0 }
        let others = order.filter { !moved.contains($0) }
        let movedHeight = moved.map(height).reduce(0, +)
        let lift = fingerY - held.midY
        let center = movedTop + lift + movedHeight / 2
        // The top of each place among the others.
        var tops = [top]
        for id in others {
            tops.append(tops[tops.count - 1] + height(id))
        }
        originalSlot = order[..<start].count(where: { !moved.contains($0) })
        slot = (0...others.count).filter(allowed).min { abs(tops[$0] + movedHeight / 2 - center) < abs(tops[$1] + movedHeight / 2 - center) }
            ?? originalSlot
        var offsets: [String: CGFloat] = [:]
        for (index, id) in others.enumerated() {
            offsets[id] = tops[index] + (index >= slot ? movedHeight : 0) - (frames[id]?.minY ?? 0)
        }
        for id in moved {
            offsets[id] = lift
        }
        self.offsets = offsets
        gap = CGRect(x: held.minX, y: tops[slot], width: held.width, height: movedHeight)
    }
}

private extension View {
    // The bar along the exercises of a superset.
    func supersetBar(_ shown: Bool = true) -> some View {
        overlay(alignment: .leading) {
            if shown {
                Rectangle()
                    .fill(Color(.superset))
                    .frame(width: 3)
            }
        }
    }
}
