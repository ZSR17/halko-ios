import SwiftUI

// Shown once, at the first Start, before the session begins: why Halko asks for Health and notifications. A single
// Continue, which asks for both, then the session starts whatever the answers; it cannot be swiped away.
struct FirstWorkoutView: View {
    let proceed: () async -> Void
    @State private var asking = false
    @ScaledMetric(relativeTo: .title) private var iconSide = 48.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Before your first workout")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Two things that make Halko more useful. Your iPhone will ask for your consent to each, and you can change your mind in Settings.")
                        .foregroundStyle(Color(.secondaryText))
                }
                .padding(.bottom, 2)
                point(
                    symbol: "heart.fill",
                    color: .red,
                    title: Text("Fill your rings"),
                    text: Text("Halko saves your workouts in the Health app: they count towards your Move and Exercise rings. With your watch, Halko also shows your heart rate during the workout.")
                )
                point(
                    symbol: "bell.fill",
                    color: .blue,
                    title: Text("Get notified when your rest ends"),
                    text: Text("Even with your iPhone locked or in another app. Sound, vibration and the signal before the end are set in Settings.")
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                asking = true
                Task {
                    await proceed()
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(Color(.onAccent))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(asking)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .interactiveDismissDisabled()
    }

    private func point(symbol: String, color: Color, title: Text, text: Text) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: iconSide, height: iconSide)
                .background(color.opacity(0.15), in: .rect(cornerRadius: iconSide * 0.3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                title
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                text
                    .foregroundStyle(Color(.secondaryText))
            }
        }
    }
}
