import HalkoCore
import SwiftUI

// The muscles a workout works: on the body seen from the front and from the back, and in words.
struct WorkedMusclesCard: View {
    let muscles: [WorkedMuscle]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var figureHeight = 84.0

    var body: some View {
        let primary = muscles.filter { $0.role == .primary }.map(\.muscle)
        let secondary = muscles.filter { $0.role == .secondary }.map(\.muscle)
        // With the largest text sizes, the words go under the body, which keeps the whole width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            HStack(spacing: 6) {
                figure(.front, "Front", primary: primary, secondary: secondary)
                figure(.back, "Back", primary: primary, secondary: secondary)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                if !primary.isEmpty {
                    legend(primary.count == 1 ? "Primary muscle: \(names(primary))" : "Primary muscles: \(names(primary))", color: Color(.musclePrimary))
                }
                if !secondary.isEmpty {
                    legend(secondary.count == 1 ? "Secondary muscle: \(names(secondary))" : "Secondary muscles: \(names(secondary))", color: Color(.muscleSecondary))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func figure(_ side: BodySide, _ caption: LocalizedStringKey, primary: [Muscle], secondary: [Muscle]) -> some View {
        VStack(spacing: 2) {
            BodyFigure(side: side, primary: Set(primary), secondary: Set(secondary))
                .frame(height: min(figureHeight, 160))
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color(.secondaryText))
        }
    }

    private func legend(_ text: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.subheadline)
        }
    }

    // "shoulders, triceps"
    private func names(_ muscles: [Muscle]) -> String {
        muscles.map { String(localized: $0.name).localizedLowercase }.formatted(.list(type: .and, width: .narrow))
    }
}
