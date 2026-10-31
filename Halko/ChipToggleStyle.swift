import SwiftUI

// A capsule, filled with the accent color when on.
struct ChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.subheadline.weight(.medium))
                .foregroundStyle(configuration.isOn ? Color(.onAccent) : Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(configuration.isOn ? Color.accentColor : Color(.secondarySystemFill), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
