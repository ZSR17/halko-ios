import HalkoCore
import SwiftUI

// The body from the front and from the back, to pick muscles: to find the exercises working them, or to say what an
// exercise works. A tap on a muscle picks it as a primary muscle, a second tap as a secondary one, a third lets it
// go. VoiceOver reads the body as the list of its areas.
struct MusclePicker: View {
    let pick: MusclePick
    let cycle: ([Muscle]) -> Void
    // To let every muscle picked go at once, in the filter of the exercises.
    var clear: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var figureHeight = 114.0

    var body: some View {
        // With the largest text sizes, the words go under the body, which keeps the whole width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 10) {
                figure(.front, "Front")
                figure(.back, "Back")
            }
            .accessibilityRepresentation {
                VStack {
                    ForEach(BodyMap.areas, id: \.self) { area in
                        Button(area.map { String(localized: $0.name) }.joined(separator: ", ")) {
                            cycle(area)
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
                    if let clear {
                        Button("Clear", action: clear)
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    } else {
                        Text("1 tap: primary · 2: secondary · 3: removed")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryText))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.selection, trigger: pick)
    }

    private func figure(_ side: BodySide, _ caption: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            BodyFigure(side: side, primary: Set(pick.primary), secondary: Set(pick.secondary))
                .frame(height: min(figureHeight, 180))
                .overlay {
                    GeometryReader { geometry in
                        Color.clear
                            .contentShape(.rect)
                            .gesture(SpatialTapGesture().onEnded { tap in
                                if let area = BodyFigure.area(at: tap.location, in: geometry.size, side: side) {
                                    cycle(area)
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
