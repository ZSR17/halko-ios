import HalkoCore
import SwiftUI
import UIKit

extension Appearance {
    var scheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// Gives the views below the look and the color chosen in the settings.
struct ChosenTheme: ViewModifier {
    @AppStorage(Appearance.key) private var appearance = Appearance.auto
    @AppStorage(ThemeColor.key) private var color = ThemeColor.lime

    func body(content: Content) -> some View {
        content
            .tint(color.color)
            .environment(\.accent, color.color)
            .environment(\.onAccent, color.onColor)
            .preferredColorScheme(appearance.scheme)
            // The alerts, shown by the system, take the color of the window: that of a text, as their Cancel is gray and
            // iOS gives all the buttons of an alert one color. The app's own views: none.
            .background(WindowTint())
    }
}

private struct WindowTint: UIViewRepresentable {
    func makeUIView(context: Context) -> TintingView {
        TintingView()
    }

    func updateUIView(_ view: TintingView, context: Context) {}
}

private final class TintingView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        window?.tintColor = .label
    }
}
