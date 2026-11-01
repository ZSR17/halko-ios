import HalkoCore
import SwiftData
import SwiftUI

// The page of an exercise: its pictures, what it is, the muscles it works, the records from the sets done of it, and
// how to do it, in the language of the app. "Edit" changes it in a sheet; "Add to a workout" asks which one, then opens
// its editor with the exercise added.
struct ExerciseView: View {
    let exercise: Exercise
    @Query private var sets: [SetLog]
    @State private var sheet: ExerciseSheet?
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    init(exercise: Exercise) {
        self.exercise = exercise
        let id = exercise.id
        _sets = Query(filter: #Predicate<SetLog> { !$0.removed && $0.exerciseID == id }, sort: \SetLog.completedAt)
    }

    var body: some View {
        let muscles = WorkedMuscle.of(exercise)
        let instructions = exercise.localizedInstructions
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ExercisePictures(mediaIDs: exercise.mediaIDs)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: exercise.localizedName)
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        Tag(Text(exercise.exerciseType.name), color: Color(.secondaryText))
                        ForEach(exercise.equipment, id: \.self) { equipment in
                            Tag(Text(verbatim: Equipment.name(of: equipment)), color: Color(.secondaryText))
                        }
                        if exercise.unilateral {
                            Tag(Text("One side at a time"), color: Color(.oneSide))
                        }
                        ExerciseBadge(exercise: exercise)
                    }
                }
                if !muscles.isEmpty {
                    WorkedMusclesCard(muscles: muscles)
                }
                RecordTiles(records: ExerciseRecords(sets: sets, type: exercise.exerciseType), type: exercise.exerciseType, text: SetsText(locale: locale))
                if !instructions.isEmpty {
                    Steps(steps: instructions)
                }
            }
            .padding([.horizontal, .bottom])
        }
        .background(Color(.systemGroupedBackground))
        // Below the steps, never over them.
        .safeAreaInset(edge: .bottom) {
            Button {
                sheet = .choosing
            } label: {
                // The text in the color made to be read on the accent color, in light and dark appearance.
                Label("Add to a workout", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(Color(.onAccent))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    sheet = .editing
                }
            }
        }
        .sheet(item: $sheet, onDismiss: {
            // Deleted in the sheet: back to the list.
            if exercise.removed {
                dismiss()
            }
        }) { sheet in
            switch sheet {
            case .editing:
                ExerciseEditor(exercise: exercise)
            case .choosing:
                // The choice closes this sheet and opens the editor.
                AddToWorkoutSheet(exercise: exercise) { workout in
                    self.sheet = .adding(workout)
                }
            case .adding(let workout):
                AddingEditor(workout: workout, exercise: exercise)
            }
        }
    }
}

private enum ExerciseSheet: Identifiable {
    case editing
    case choosing
    // nil: a new workout.
    case adding(Workout?)

    var id: String {
        switch self {
        case .editing: "editing"
        case .choosing: "choosing"
        case .adding(let workout): "adding-\(workout?.id ?? "")"
        }
    }
}

// The bests of the sets done, and the last time: nothing until the exercise is done.
private struct RecordTiles: View {
    let records: ExerciseRecords
    let type: ExerciseType
    let text: SetsText
    @ScaledMetric(relativeTo: .title3) private var tileWidth = 100.0

    var body: some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Heading("Records")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(records.records, id: \.kind) { record in
                        tile(text.record(record), caption: Text(record.kind.name))
                    }
                    if let last = records.lastSet {
                        tile(text.set(last, type: type), caption: Text("Last time"))
                    }
                }
            }
        }
    }

    private func tile(_ value: String, caption: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.title3.bold())
            caption
                .font(.caption)
                .foregroundStyle(Color(.secondaryText))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

// How to do the exercise, step by step.
private struct Steps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Heading("How to")
            // Plain texts: by their place, which is their number.
            ForEach(Array(steps.enumerated()), id: \.offset) { number, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\((number + 1).formatted()).")
                        .monospacedDigit()
                        .foregroundStyle(Color(.secondaryText))
                    Text(verbatim: step)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct Heading: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.title3.bold())
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
