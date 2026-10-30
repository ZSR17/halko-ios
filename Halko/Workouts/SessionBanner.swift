import HalkoCore
import SwiftData
import SwiftUI

// The session in progress, on this device or another one: its name, how long it has lasted and where it is.
struct SessionBanner: View {
    let session: Session
    @Query private var items: [WorkoutItem]
    @Query private var sets: [SetLog]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(session: Session) {
        self.session = session
        // No row has an empty id: a session without a workout has no planned exercises.
        let workoutID = session.workoutID ?? ""
        let sessionID = session.id
        _items = Query(filter: #Predicate<WorkoutItem> { !$0.removed && $0.workoutID == workoutID }, sort: \WorkoutItem.position)
        _sets = Query(filter: #Predicate<SetLog> { !$0.removed && $0.sessionID == sessionID })
    }

    var body: some View {
        // With the largest text sizes, the icon goes above the text, which keeps the whole width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Image(systemName: "dumbbell")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.name) · in progress")
                    .font(.headline)
                details
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .foregroundStyle(Color(.onAccent))
        .background(.tint, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var details: Text {
        let elapsed = Text(timerInterval: session.startedAt...Date.distantFuture, countsDown: false)
        guard let progress = SessionProgress(items: items, sets: sets) else { return elapsed }
        return Text("\(elapsed) · exercise \(progress.exercise) of \(progress.exerciseCount)")
    }
}
