import HalkoCore
import os
import SwiftData
import SwiftUI

// Creating an exercise, or changing one, in a sheet: its pictures and video, name, type, equipment, muscles and
// steps. A library exercise becomes the user's version, which can go back to the original; the user's own exercise
// can be deleted. Written to the local database only.
struct ExerciseEditor: View {
    // nil: a new exercise.
    let exercise: Exercise?
    // As the sheet opened: kept when the exercise changes under it, once saved.
    @State private var original: ExerciseDraft
    @State private var draft: ExerciseDraft
    @State private var created: Exercise?
    // Picked while editing: their files go again if the exercise does not keep them.
    @State private var imported: Set<String> = []
    @State private var doneSets = 0
    @State private var pendingType: ExerciseType?
    @State private var showsAllEquipment: Bool
    @State private var confirmsDiscard = false
    @State private var confirmsRevert = false
    @State private var confirmsDelete = false
    @State private var failed = false
    @FocusState private var focusedStep: ExerciseStep.ID?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private static let logger = Logger(subsystem: "com.zsr.halko", category: "exercises")
    // The equipment shown first; "More…" shows the rest.
    private static let commonEquipment: [Equipment] = [.bodyOnly, .barbell, .dumbbell, .kettlebells, .cable, .machine, .bands]

    init(exercise: Exercise?) {
        self.exercise = exercise
        let draft = exercise.map { ExerciseDraft($0, language: Exercise.appLanguage) } ?? ExerciseDraft()
        _original = State(initialValue: draft)
        _draft = State(initialValue: draft)
        _showsAllEquipment = State(initialValue: Equipment.allCases.contains { !Self.commonEquipment.contains($0) && draft.uses($0) })
    }

    private var hasChanges: Bool {
        draft.differs(from: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let exercise, exercise.source == .builtin {
                    Section {
                        Label {
                            exercise.customized
                                ? Text("Library exercise: your changes make it your version, on all your devices. You can go back to the original at the bottom.")
                                : Text("Library exercise: your changes make it your version, on all your devices.")
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.tint)
                        }
                        .font(.footnote)
                    }
                }
                Section {
                    MediaStrip(mediaIDs: $draft.mediaIDs) { id in
                        imported.insert(id)
                    }
                } header: {
                    SectionText("Photos and video")
                } footer: {
                    SectionText("The first picture is the thumbnail. Touch and hold one to move it.")
                }
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Name").foregroundStyle(Color(.secondaryText)))
                        .font(.title3.weight(.semibold))
                } header: {
                    SectionText("Name")
                }
                Section {
                    Picker("Exercise type", selection: exerciseType) {
                        ForEach(ExerciseType.allCases, id: \.self) { type in
                            Text(type.name)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("One side at a time", isOn: $draft.unilateral)
                }
                Section {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(showsAllEquipment ? Equipment.allCases : Self.commonEquipment, id: \.self) { equipment in
                            Toggle(isOn: Binding { draft.uses(equipment) } set: { _ in draft.toggle(equipment) }) {
                                Text(equipment.name)
                            }
                        }
                        if !showsAllEquipment {
                            Toggle("More…", isOn: $showsAllEquipment)
                        }
                    }
                    .toggleStyle(ChipToggleStyle())
                    .padding(.vertical, 4)
                } header: {
                    SectionText("Equipment")
                }
                Section {
                    MusclePicker(pick: draft.muscles) { area in
                        draft.muscles.cycle(area)
                    }
                    .padding(.vertical, 4)
                } header: {
                    SectionText("Muscles worked")
                }
                Section {
                    ForEach($draft.steps) { $step in
                        let number = (draft.steps.firstIndex { $0.id == step.id } ?? 0) + 1
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: "\(number.formatted()).")
                                .monospacedDigit()
                                .foregroundStyle(Color(.secondaryText))
                                .accessibilityHidden(true)
                            TextField("Step \(number)", text: $step.text, axis: .vertical)
                                .focused($focusedStep, equals: step.id)
                        }
                    }
                    .onDelete { offsets in
                        draft.steps.remove(atOffsets: offsets)
                    }
                    Button("Add a step", systemImage: "plus") {
                        let step = ExerciseStep("")
                        draft.steps.append(step)
                        focusedStep = step.id
                    }
                } header: {
                    SectionText("How to")
                } footer: {
                    if !draft.steps.isEmpty {
                        SectionText("Swipe a step left to delete it.")
                    }
                }
                if let exercise {
                    if exercise.source == .custom {
                        Section {
                            Button("Delete exercise", role: .destructive) {
                                confirmsDelete = true
                            }
                            .confirmationDialog("Delete this exercise?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                                Button("Delete the exercise", role: .destructive) {
                                    change { try modelContext.removeExercise(exercise) }
                                }
                            } message: {
                                Text("The sessions already done keep it in the history.")
                            }
                        }
                    } else if exercise.customized {
                        Section {
                            Button("Revert to original", role: .destructive) {
                                confirmsRevert = true
                            }
                            .confirmationDialog("Go back to the original?", isPresented: $confirmsRevert, titleVisibility: .visible) {
                                Button("Go back to the original", role: .destructive) {
                                    change { try modelContext.revertToLibrary(exercise) }
                                }
                            } message: {
                                Text("Your changes to this exercise will be lost.")
                            }
                        }
                    }
                }
            }
            .navigationTitle(exercise == nil ? Text("New exercise") : Text("Edit exercise"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            confirmsDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog("Discard the changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                        Button("Discard changes", role: .destructive) {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        change {
                            if let exercise {
                                try modelContext.updateExercise(exercise, with: draft)
                            } else {
                                created = try modelContext.createExercise(draft)
                            }
                        }
                    }
                    .disabled(!draft.canSave || !hasChanges)
                }
            }
            // Pulled down with changes, the sheet stays: "Cancel" asks before losing them.
            .interactiveDismissDisabled(hasChanges)
            .alert(Text("Switch to “\(String(localized: (pendingType ?? original.exerciseType).name))”?"), isPresented: Binding {
                pendingType != nil
            } set: { shown in
                if !shown {
                    pendingType = nil
                }
            }, presenting: pendingType) { type in
                Button("Cancel", role: .cancel) {}
                Button("Switch") {
                    draft.exerciseType = type
                }
            } message: { _ in
                typeChangeMessage
            }
            .alert("The exercise could not be saved.", isPresented: $failed) {
                Button("OK") {}
            }
            .task {
                if let exercise {
                    doneSets = (try? modelContext.doneSetCount(of: exercise)) ?? 0
                }
            }
            .onDisappear {
                // The files of the pictures and videos the exercise does not hold, now that it is saved or not.
                let kept = (exercise ?? created)?.mediaIDs ?? []
                ExerciseMedia.delete(imported.union(original.mediaIDs).subtracting(kept))
            }
        }
    }

    // Leaving the type of an exercise already done asks first: its sets are no longer counted under the new one.
    private var exerciseType: Binding<ExerciseType> {
        Binding {
            draft.exerciseType
        } set: { type in
            if doneSets > 0 && draft.exerciseType == original.exerciseType && type != original.exerciseType {
                pendingType = type
            } else {
                draft.exerciseType = type
            }
        }
    }

    private var typeChangeMessage: Text {
        let type = String(localized: original.exerciseType.name)
        return doneSets == 1
            ? Text("Your set already done was recorded as “\(type)”: it will no longer count in the records or the progress of this exercise. It stays recorded: switch back to “\(type)” and it comes back.")
            : Text("Your \(doneSets) sets already done were recorded as “\(type)”: they will no longer count in the records or the progress of this exercise. They stay recorded: switch back to “\(type)” and they all come back.")
    }

    // Writes to the local database, then closes the sheet.
    private func change(_ write: () throws -> Void) {
        do {
            try write()
            dismiss()
        } catch {
            Self.logger.error("Cannot save the exercise: \(String(describing: error))")
            failed = true
        }
    }
}

// The title or note of a section, in the gray of the app's secondary texts: the system's is too light to read
// easily (4.5:1).
private struct SectionText: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(Color(.secondaryText))
    }
}
