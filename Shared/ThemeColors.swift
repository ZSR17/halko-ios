import HalkoCore
import SwiftUI
#if !os(watchOS)
import UIKit
#endif

// The color of the app, and that of a text on it, readable from any thread like the styles that use them: by the names
// of their assets. In the app, the Live Activity and the watch, each given the color chosen on the iPhone.
private nonisolated struct AccentKey: EnvironmentKey {
    static let defaultValue = Color("AccentColor")
}

private nonisolated struct OnAccentKey: EnvironmentKey {
    static let defaultValue = Color("OnAccent")
}

extension EnvironmentValues {
    nonisolated var accent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }

    nonisolated var onAccent: Color {
        get { self[OnAccentKey.self] }
        set { self[OnAccentKey.self] = newValue }
    }
}

// A text on the color of the app.
nonisolated struct OnAccentStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        environment.onAccent
    }
}

extension ShapeStyle where Self == OnAccentStyle {
    static var onTint: OnAccentStyle { OnAccentStyle() }
}

extension ThemeColor {
    // In the shade of the look it is shown in, light or dark, with the contrast increased or not. The system asks for it
    // on any thread. The watch is always dark.
    nonisolated var color: Color {
        self == .lime ? AccentKey.defaultValue : Self.adaptive { shade(dark: $0, highContrast: $1) }
    }

    nonisolated var onColor: Color {
        self == .lime ? OnAccentKey.defaultValue : Self.adaptive { shade(dark: $0, highContrast: $1).text }
    }

    // The color stored in the settings, or the app's own.
    nonisolated init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .lime
    }

    #if os(watchOS)
    private nonisolated static func adaptive(_ shade: (Bool, Bool) -> RGB) -> Color {
        let rgb = shade(true, false)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
    #else
    private nonisolated static func adaptive(_ shade: @escaping @Sendable (Bool, Bool) -> RGB) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = shade(traits.userInterfaceStyle == .dark, traits.accessibilityContrast == .high)
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }
    #endif
}
