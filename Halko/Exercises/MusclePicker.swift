import HalkoCore
import SwiftUI

// The body from the front and from the back, to pick muscles: to find the exercises working them, or to say what an
// exercise works. Small beside the muscles picked; a tap opens it large, in a sheet, where a tap on a muscle picks it
// as a primary muscle, a second tap as a secondary one, a third lets it go.
struct MusclePicker: View {
    let pick: MusclePick
    let cycle: ([Muscle]) -> Void
    // Lets every muscle picked go at once: in the sheet, and beside the small body when `clearsBeside`.
    let clear: () -> Void
    var clearsBeside = false
    @State private var picking = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var figureHeight = 114.0

    var body: some View {
        // With the largest text sizes, the words go under the body, which keeps the whole width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button {
                picking = true
            } label: {
                HStack(spacing: 10) {
                    SmallFigure(side: .front, caption: "Front", pick: pick, height: min(figureHeight, 180))
                    SmallFigure(side: .back, caption: "Back", pick: pick, height: min(figureHeight, 180))
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                        .frame(width: 26, height: 26)
                        .background(Color(.secondarySystemGroupedBackground), in: .circle)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .offset(x: 6, y: -18)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Muscles"))
            .accessibilityHint(Text("Opens the body, large, to pick muscles."))
            VStack(alignment: .leading, spacing: 6) {
                if pick.isEmpty {
                    Text("Tap one of the figures to pick a muscle.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryText))
                } else {
                    MuscleLegends(pick: pick)
                    if clearsBeside {
                        Button("Clear", action: clear)
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $picking) {
            LargeMusclePicker(pick: pick, cycle: cycle, clear: clear)
        }
    }
}

// The body seen from one side, small, with its name under it.
private struct SmallFigure: View {
    let side: BodySide
    let caption: LocalizedStringKey
    let pick: MusclePick
    let height: Double

    var body: some View {
        VStack(spacing: 2) {
            BodyFigure(side: side, primary: Set(pick.primary), secondary: Set(pick.secondary))
                .frame(height: height)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color(.secondaryText))
        }
    }
}

// "● Primary muscle: chest", then the secondary ones.
private struct MuscleLegends: View {
    let pick: MusclePick

    var body: some View {
        if !pick.primary.isEmpty {
            MuscleLegend(muscles: pick.primary, role: .primary)
        }
        if !pick.secondary.isEmpty {
            MuscleLegend(muscles: pick.secondary, role: .secondary)
        }
    }
}

// The body large, in a sheet, its muscles to tap. Each tap counts at once: ✓, or the sheet pulled down, keeps them.
// VoiceOver reads the body as the list of its areas.
private struct LargeMusclePicker: View {
    let pick: MusclePick
    let cycle: ([Muscle]) -> Void
    let clear: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var figureHeight = 340.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Both sides in the width, at most that high.
                    HStack(spacing: 14) {
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
                    Text("Tap a muscle once for a primary muscle, twice for a secondary one.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryText))
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 6) {
                        MuscleLegends(pick: pick)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Muscles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear", action: clear)
                        .disabled(pick.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        dismiss()
                    }
                    .accessibilityLabel(Text("Done"))
                }
            }
            .sensoryFeedback(.selection, trigger: pick)
        }
    }

    private func figure(_ side: BodySide, _ caption: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            BodyFigure(side: side, primary: Set(pick.primary), secondary: Set(pick.secondary))
                .frame(maxWidth: figureHeight / 2, maxHeight: figureHeight)
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
