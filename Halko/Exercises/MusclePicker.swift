import HalkoCore
import SwiftUI

// The body from the front and from the back, to find the exercises working some muscles: a tap on a muscle picks
// it as a primary muscle, a second tap as a secondary one, a third lets it go. VoiceOver reads the body as the list
// of its areas.
struct MusclePicker: View {
    @Binding var filter: ExerciseFilter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var figureHeight = 114.0

    var body: some View {
        let pick = filter.pick
        // With the largest text sizes, the words go under the body, which keeps the whole width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 10) {
                figure(.front, "Front", pick: pick)
                figure(.back, "Back", pick: pick)
            }
            .accessibilityRepresentation {
                VStack {
                    ForEach(BodyMap.areas, id: \.self) { area in
                        Button(area.map { String(localized: $0.name) }.joined(separator: ", ")) {
                            filter.cycle(area)
                        }
                        .accessibilityValue(value(pick.role(of: area)))
                        .accessibilityIdentifier("muscle-" + area.map(\.rawValue).joined(separator: "-"))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if pick.isEmpty {
                    Text("Tap a muscle once for a primary muscle, twice for a secondary one.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryText))
                } else {
                    if !pick.primary.isEmpty {
                        MuscleLegend(muscles: pick.primary, role: .primary)
                    }
                    if !pick.secondary.isEmpty {
                        MuscleLegend(muscles: pick.secondary, role: .secondary)
                    }
                    Button("Clear") {
                        filter.clearPick()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.selection, trigger: pick)
    }

    private func figure(_ side: BodySide, _ caption: LocalizedStringKey, pick: MusclePick) -> some View {
        VStack(spacing: 2) {
            BodyFigure(side: side, primary: Set(pick.primary), secondary: Set(pick.secondary))
                .frame(height: min(figureHeight, 180))
                .overlay {
                    GeometryReader { geometry in
                        Color.clear
                            .contentShape(.rect)
                            .gesture(SpatialTapGesture().onEnded { tap in
                                if let area = BodyFigure.area(at: tap.location, in: geometry.size, side: side) {
                                    filter.cycle(area)
                                }
                            })
                    }
                }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color(.secondaryText))
        }
    }

    private func value(_ role: MuscleRole?) -> Text {
        switch role {
        case .primary: Text("Primary")
        case .secondary: Text("Secondary")
        case nil: Text("Not picked")
        }
    }
}
