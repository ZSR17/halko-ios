import SwiftUI

// Shown once, at the first Start, before the session begins: what the watch is about to ask for. A single Continue, which
// asks for Health and notifications, then the session starts whatever the answers; there is no other way out of it.
struct FirstWorkoutView: View {
    let proceed: () async -> Void
    @State private var asking = false
    @ScaledMetric(relativeTo: .headline) private var iconSide = 24.0

    var body: some View {
        // Continue under the text, not fixed over it: nothing of what is asked for stays hidden.
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Before your first workout")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("The watch will ask for your consent for:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                point(symbol: "heart.fill", color: .red, title: Text("Health"), text: Text("filling your rings"))
                point(symbol: "bell.fill", color: Color(.rest), title: Text("Notifications"), text: Text("telling you when your rest ends"))
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
                // A button of the watch stays narrower than the page.
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
