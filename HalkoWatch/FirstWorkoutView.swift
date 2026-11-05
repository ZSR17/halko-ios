import SwiftUI

// Shown once, at the first Start, before the session begins: what the watch is about to ask for. A single Continue, which
// asks for Health and notifications, then the session starts whatever the answers; there is no other way out of it.
struct FirstWorkoutView: View {
    let proceed: () async -> Void
    @State private var asking = false
    @ScaledMetric(relativeTo: .headline) private var iconSide = 24.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Before your first workout")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("The watch will ask for your consent for:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                point(symbol: "heart.fill", color: .red, title: Text("Health"), text: Text("filling your rings"))
                point(symbol: "bell.fill", color: Color(.rest), title: Text("Notifications"), text: Text("telling you when your rest ends"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .bottomButton {
            Button {
                asking = true
                Task {
                    await proceed()
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(Color(.onAccent))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(asking)
        }
        .navigationBarBackButtonHidden()
    }

    private func point(symbol: String, color: Color, title: Text, text: Text) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: iconSide, height: iconSide)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                title
                    .font(.footnote.weight(.semibold))
                text
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
