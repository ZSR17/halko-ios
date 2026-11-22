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
            // The alerts and their text fields, shown by the system, take the color of the window. The app's own: none.
            .background(WindowTint(color: color == .lime ? nil : UIColor(color.color)))
    }
}

extension ChosenTheme {
    // Before the window is made: until the views set its color, the system draws in it with the app's own, a moment
    // in another color at launch.
    static func tintWindows(from defaults: UserDefaults) {
        let color = ThemeColor(stored: defaults.string(forKey: ThemeColor.key))
        guard color != .lime else { return }
        UIWindow.appearance().tintColor = UIColor(color.color)
    }
}

private struct WindowTint: UIViewRepresentable {
    let color: UIColor?

    func makeUIView(context: Context) -> TintingView {
        TintingView()
    }

    func updateUIView(_ view: TintingView, context: Context) {
        view.color = color
    }
}

private final class TintingView: UIView {
    var color: UIColor? {
        didSet {
            window?.tintColor = color
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window?.tintColor = color
    }
}
