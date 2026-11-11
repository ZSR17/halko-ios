import HalkoCore
import SwiftUI
import UIKit

// Light, dark or as the device is, and the color of the app: one of its own or any other, made readable in each look.
// The colors of the muscles and of the plates stay.
struct ThemeSettingsView: View {
    @AppStorage(Appearance.key) private var appearance = Appearance.auto
    @AppStorage(ThemeColor.key) private var color = ThemeColor.lime
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            Section {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    ForEach(Appearance.allCases, id: \.self) { choice in
                        AppearanceCard(appearance: choice, chosen: choice == appearance) {
                            appearance = choice
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                // In a darker grey than the system's, for a contrast of 4.5:1.
                Text("Theme")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                HStack(spacing: 0) {
                    ForEach(ThemeColor.presets, id: \.self) { preset in
                        ColorSwatch(color: preset, chosen: preset == color) {
                            color = preset
                        }
                        .frame(maxWidth: .infinity)
                    }
                    otherColor
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Color")
                    .foregroundStyle(Color(.secondaryText))
            } footer: {
                Text("The app's theme color.")
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .navigationTitle("Theme and color")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Any color, from the system's picker, ringed once chosen.
    private var otherColor: some View {
        let chosen = if case .custom = color { true } else { false }
        return ColorPicker(selection: Binding {
            Color(red: color.base.red, green: color.base.green, blue: color.base.blue)
        } set: { picked in
            var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            if UIColor(picked).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                color = .custom(RGB(red: red, green: green, blue: blue))
            }
        }, supportsOpacity: false) {
            Text("Other color")
        }
        .labelsHidden()
        .frame(width: 44, height: 44)
        .overlay {
            if chosen {
                Ring()
            }
        }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

// The circle around the color chosen.
private struct Ring: View {
    var body: some View {
        Circle()
            .strokeBorder(Color.primary, lineWidth: 2)
            .frame(width: 44, height: 44)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// One of the app's colors, in the shade it takes here, with a check and a ring once chosen.
private struct ColorSwatch: View {
    let color: ThemeColor
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .frame(width: 34, height: 34)
                .overlay {
                    if chosen {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(color.onColor)
                    }
                }
                .overlay {
                    if chosen {
                        Ring()
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

// A small screen in the look, with its name.
private struct AppearanceCard: View {
    private static let light = Color(red: 0.95, green: 0.95, blue: 0.97)
    private static let dark = Color(red: 0.07, green: 0.07, blue: 0.08)

    let appearance: Appearance
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .frame(width: 44, height: 8)
                    Capsule()
                        .frame(width: 30, height: 8)
                }
                .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .padding(12)
                .background(background, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.separator)), lineWidth: chosen ? 2 : 1)
                }
                HStack(spacing: 4) {
                    appearance.name
                        .font(.subheadline.weight(chosen ? .semibold : .regular))
                    if chosen {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(Color.primary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var background: AnyShapeStyle {
        switch appearance {
        case .auto: AnyShapeStyle(LinearGradient(stops: [.init(color: Self.light, location: 0.5), .init(color: Self.dark, location: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .light: AnyShapeStyle(Self.light)
        case .dark: AnyShapeStyle(Self.dark)
        }
    }
}

extension Appearance {
    var name: Text {
        switch self {
        case .auto: Text("Auto")
        case .light: Text("Light")
        case .dark: Text("Dark")
        }
    }
}

extension ThemeColor {
    var name: Text {
        switch self {
        case .lime: Text("Lime")
        case .orange: Text("Orange")
        case .blue: Text("Blue")
        case .purple: Text("Purple")
        case .pink: Text("Pink")
        case .custom: Text("Other color")
        }
    }
}
