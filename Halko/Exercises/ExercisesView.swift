import HalkoCore
import SwiftData
import SwiftUI

// The Exercises tab: the embedded library and the exercises made on the device, narrowed down by muscles,
// equipment and a search of their names. All of it local: the same offline.
struct ExercisesView: View {
    @Query(filter: #Predicate<Exercise> { !$0.removed }) private var exercises: [Exercise]
    @State private var catalog = ExerciseCatalog()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MusclePicker(filter: $catalog.filter)
                FilterChips(filter: $catalog.filter)
                Text("\(catalog.results.count) exercises")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
                    .padding(.top, 4)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(catalog.results) { entry in
                        NavigationLink(value: entry.exercise) {
                            ExerciseListRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                if catalog.results.isEmpty {
                    Text("No exercises match.")
                        .foregroundStyle(Color(.secondaryText))
                }
            }
            .padding([.horizontal, .bottom])
        }
        .searchable(text: $catalog.filter.query, prompt: Text("Search \(catalog.pool) exercises"))
        .navigationTitle("Exercises")
        .navigationDestination(for: Exercise.self) { exercise in
            ExerciseView(exercise: exercise)
        }
        .onChange(of: exercises, initial: true) { _, exercises in
            catalog.show(exercises)
        }
    }
}

// The exercises of the list in the alphabetical order of the app's language, and those the filter keeps, worked
// out again when it changes.
@Observable
final class ExerciseCatalog {
    var filter = ExerciseFilter() {
        didSet {
            if filter != oldValue {
                update()
            }
        }
    }

    // The exercises of the muscles and equipment chosen, which the search looks among.
    private(set) var pool = 0
    private(set) var results: [ExerciseEntry] = []
    @ObservationIgnored private var entries: [ExerciseEntry] = []

    func show(_ exercises: [Exercise]) {
        entries = exercises.map(ExerciseEntry.init).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        update()
    }

    private func update() {
        let chosen = entries.filter { filter.chooses($0.exercise) }
        let query = filter.queryKey
        pool = chosen.count
        results = query.isEmpty ? chosen : chosen.filter { $0.searchKeys.contains { $0.contains(query) } }
    }
}

struct ExerciseEntry: Identifiable {
    let exercise: Exercise
    let name: String
    // Its names in the app's language and in English, as the search compares them.
    let searchKeys: [String]

    init(_ exercise: Exercise) {
        self.exercise = exercise
        name = exercise.localizedName
        searchKeys = [name, exercise.name].map(ExerciseFilter.searchKey)
    }

    var id: String {
        exercise.id
    }
}

// The muscle groups, then the equipment at hand, each in a row scrolling sideways.
private struct FilterChips: View {
    @Binding var filter: ExerciseFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChipRow {
                Toggle("All", isOn: Binding { filter.isAllMuscles } set: { on in
                    if on {
                        filter.choose(nil)
                    }
                })
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    Toggle(isOn: Binding { filter.group == group } set: { on in filter.choose(on ? group : nil) }) {
                        Text(group.name)
                    }
                }
            }
            Text("Equipment")
                .font(.footnote)
                .foregroundStyle(Color(.secondaryText))
                .padding(.top, 6)
            ChipRow {
                ForEach(Equipment.allCases, id: \.self) { equipment in
                    Toggle(isOn: Binding { filter.equipment.contains(equipment) } set: { on in
                        if on {
                            filter.equipment.insert(equipment)
                        } else {
                            filter.equipment.remove(equipment)
                        }
                    }) {
                        equipment == .bodyOnly ? Text("No equipment") : Text(equipment.name)
                    }
                }
            }
        }
    }
}

private struct ChipRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                content
            }
            .toggleStyle(.button)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

// An exercise of the list: its picture, its name, its primary muscles and its equipment.
private struct ExerciseListRow: View {
    let entry: ExerciseEntry

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(mediaID: entry.exercise.mediaIDs.first)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name)
                    .font(.headline)
                Text(verbatim: details)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ExerciseBadge(exercise: entry.exercise)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    // "Chest · barbell"
    private var details: String {
        let muscles = entry.exercise.primaryMuscles.map { String(localized: $0.name) }.joined(separator: ", ")
        let equipment = entry.exercise.equipment.map { Equipment.name(of: $0).localizedLowercase }.joined(separator: ", ")
        return [muscles, equipment].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// "your version" on an exercise of the library the user changed, "custom" on one they made.
struct ExerciseBadge: View {
    let exercise: Exercise

    var body: some View {
        if exercise.source == .custom {
            Tag(Text("custom"), color: Color(.secondaryText))
        } else if exercise.customized {
            Tag(Text("your version"), color: .accentColor)
        }
    }
}
