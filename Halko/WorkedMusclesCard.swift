import HalkoCore
import SwiftUI

// The muscles a workout or an exercise works: on the body seen from the front and from the back, across the card,
// and in words under it.
struct WorkedMusclesCard: View {
    let muscles: [WorkedMuscle]
    @ScaledMetric(relativeTo: .body) private var figureHeight = 200.0

    var body: some View {
        let primary = muscles.filter { $0.role == .primary }.map(\.muscle)
        let secondary = muscles.filter { $0.role == .secondary }.map(\.muscle)
        VStack(alignment: .leading, spacing: 10) {
            // Both sides in the width, at most that high.
            HStack(spacing: 24) {
                figure(.front, "Front", primary: primary, secondary: secondary)
                figure(.back, "Back", primary: primary, secondary: secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                if !primary.isEmpty {
                    MuscleLegend(muscles: primary, role: .primary)
                }
                if !secondary.isEmpty {
                    MuscleLegend(muscles: secondary, role: .secondary)
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
                .frame(maxWidth: figureHeight / 2, maxHeight: figureHeight)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color(.secondaryText))
        }
    }
}

// "● Primary muscles: shoulders, triceps"
struct MuscleLegend: View {
    let muscles: [Muscle]
    let role: MuscleRole

    var body: some View {
        // The dot in front of the first line, growing with the text.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "circle.fill")
                .imageScale(.small)
                .foregroundStyle(role == .primary ? Color(.musclePrimary) : Color(.muscleSecondary))
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.subheadline)
    }

    private var text: LocalizedStringKey {
        let names = muscles.map { String(localized: $0.name).localizedLowercase }.formatted(.list(type: .and, width: .narrow))
        return switch role {
        case .primary: muscles.count == 1 ? "Primary muscle: \(names)" : "Primary muscles: \(names)"
        case .secondary: muscles.count == 1 ? "Secondary muscle: \(names)" : "Secondary muscles: \(names)"
        }
    }
}
