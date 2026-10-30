import HalkoCore
import SwiftData
import SwiftUI

// A planned workout: its name, number of exercises, when it was last done and the muscles it works most. The whole
// card opens the workout's page, where it starts: its Start is not a button of its own.
struct WorkoutCard: View {
    let workout: Workout
    @Query private var items: [WorkoutItem]
    @Query private var lastSessions: [Session]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(workout: Workout) {
        self.workout = workout
        let id = workout.id
        let sessionWorkoutID: String? = workout.id
        _items = Query(filter: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == id }, sort: \WorkoutItem.position)
        var last = FetchDescriptor<Session>(
            predicate: #Predicate { !$0.removed && $0.workoutID == sessionWorkoutID && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        last.fetchLimit = 1
        _lastSessions = Query(last)
    }

    var body: some View {
        // With the largest text sizes, Start goes under the name, which keeps the whole width.
        let header = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        VStack(alignment: .leading, spacing: 10) {
            header {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.name)
                        .font(.headline)
                    details
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryText))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Start")
                    .font(.headline)
                    .foregroundStyle(Color(.onAccent))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(.tint, in: .capsule)
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
            FlowLayout(spacing: 14, lineSpacing: 6) {
                ForEach(muscles, id: \.self) { muscle in
                    MuscleChip(muscle: muscle)
                }
            }
        }
    }
}

// A muscle and the color of its role; VoiceOver says the role.
private struct MuscleChip: View {
    let muscle: WorkedMuscle
    @ScaledMetric(relativeTo: .footnote) private var dot = 8.0

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(muscle.role == .primary ? Color(.musclePrimary) : Color(.muscleSecondary))
                .frame(width: dot, height: dot)
                .accessibilityHidden(true)
            Text(muscle.muscle.name)
                .accessibilityLabel(label)
        }
        .font(.footnote)
    }

    private var label: Text {
        switch muscle.role {
        case .primary: Text("\(Text(muscle.muscle.name)), primary")
        case .secondary: Text("\(Text(muscle.muscle.name)), secondary")
        }
    }
}
