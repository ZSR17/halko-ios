import HalkoCore
import SwiftData
import SwiftUI

// A planned workout: its name, number of exercises, when it was last done and the muscles it works most.
struct WorkoutCard: View {
    let workout: Workout
    @Query private var items: [WorkoutItem]
    @Query private var lastSessions: [Session]

    init(workout: Workout) {
        self.workout = workout
        let id = workout.id
        let sessionWorkoutID: String? = workout.id
        _items = Query(filter: #Predicate<WorkoutItem> { !$0.deleted && $0.workoutID == id }, sort: \WorkoutItem.position)
        var last = FetchDescriptor<Session>(
            predicate: #Predicate { !$0.deleted && $0.workoutID == sessionWorkoutID && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        last.fetchLimit = 1
        _lastSessions = Query(last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.headline)
                details
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            MainMuscles(items: items)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var details: Text {
        let exercises = Text("\(items.count) exercises")
        guard let last = lastSessions.first else { return exercises }
        return Text("\(exercises) · \(last.startedAt, format: .relative(presentation: .named))")
    }
}

// The muscles a workout works most, as in its card.
private struct MainMuscles: View {
    private let items: [WorkoutItem]
    @Query private var exercises: [Exercise]

    init(items: [WorkoutItem]) {
        self.items = items
        _exercises = Query(filter: Exercise.withIDs(items.map(\.exerciseID)))
    }

    var body: some View {
        let muscles = WorkedMuscles.main(items: items, exercises: exercises, limit: 3)
        if !muscles.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    chips(muscles)
                }
                VStack(alignment: .leading, spacing: 6) {
                    chips(muscles)
                }
            }
        }
    }

    private func chips(_ muscles: [WorkedMuscle]) -> some View {
        ForEach(muscles, id: \.self) { muscle in
            MuscleChip(muscle: muscle)
        }
    }
}

// A primary muscle has a full dot, a secondary one a ring: not told apart by the color alone.
private struct MuscleChip: View {
    let muscle: WorkedMuscle
    @ScaledMetric(relativeTo: .footnote) private var dot = 8.0

    var body: some View {
        HStack(spacing: 6) {
            switch muscle.role {
            case .primary:
                Circle()
                    .fill(Color(.musclePrimary))
                    .frame(width: dot, height: dot)
            case .secondary:
                Circle()
                    .strokeBorder(Color(.muscleSecondary), lineWidth: 2)
                    .frame(width: dot, height: dot)
            }
            Text(muscle.muscle.name)
        }
        .font(.footnote)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: Text {
        switch muscle.role {
        case .primary: Text("\(Text(muscle.muscle.name)), primary")
        case .secondary: Text("\(Text(muscle.muscle.name)), secondary")
        }
    }
}
