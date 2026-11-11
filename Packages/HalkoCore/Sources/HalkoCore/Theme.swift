import Foundation

// Light or dark, as the device is or always the same.
public enum Appearance: String, CaseIterable, Sendable {
    case auto
    case light
    case dark

    public static let key = "theme.appearance"
}

// A color in sRGB, each component from 0 to 1.
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public static let black = RGB(red: 0, green: 0, blue: 0)
    public static let white = RGB(red: 1, green: 1, blue: 1)

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    // "#RRGGBB".
    public init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else {
            return nil
        }
        self.init(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    public var hex: String {
        let value = [red, green, blue].reduce(0) { $0 << 8 | Int(($1 * 255).rounded()) }
        return "#" + String(format: "%06X", value)
    }

    // The relative luminance of WCAG.
    public var luminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    // From 1 to 21.
    public func contrast(with other: RGB) -> Double {
        let (lighter, darker) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    // Black or white, whichever reads better on it.
    public var text: RGB {
        contrast(with: .black) >= contrast(with: .white) ? .black : .white
    }

    // The nearest to it that reads with this contrast on the background: darker on a light one, lighter on a dark one.
    public func readable(on background: RGB, ratio: Double) -> RGB {
        guard contrast(with: background) < ratio else {
            return self
        }
        let toward = background.luminance > 0.18 ? RGB.black : RGB.white
        var (low, high) = (0.0, 1.0)
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if mixed(with: toward, by: middle).contrast(with: background) >= ratio {
                high = middle
            } else {
                low = middle
            }
        }
        return mixed(with: toward, by: high)
    }

    private func mixed(with other: RGB, by amount: Double) -> RGB {
        RGB(red: red + (other.red - red) * amount, green: green + (other.green - green) * amount, blue: blue + (other.blue - blue) * amount)
    }
}

// The color of the app: one of its own, or any other chosen, each shown in a shade that reads on the background.
public enum ThemeColor: Hashable, Sendable, RawRepresentable {
    case lime
    case orange
    case blue
    case purple
    case pink
    case custom(RGB)

    public static let key = "theme.color"
    public static let presets: [ThemeColor] = [.lime, .orange, .blue, .purple, .pink]

    // The backgrounds the color is read on: the darkest of the light look's, the lightest of the dark look's.
    static let lightBackground = RGB(hex: "#F2F2F7")!
    static let darkBackground = RGB(hex: "#2C2C2E")!

    public init?(rawValue: String) {
        if let preset = Self.presets.first(where: { $0.rawValue == rawValue }) {
            self = preset
        } else if let color = RGB(hex: rawValue) {
            self = .custom(color)
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .lime: "lime"
        case .orange: "orange"
        case .blue: "blue"
        case .purple: "purple"
        case .pink: "pink"
        case .custom(let color): color.hex
        }
    }

    // As chosen, before being made readable.
    public var base: RGB {
        switch self {
        case .lime: RGB(hex: "#D4FF3A")!
        case .orange: RGB(hex: "#FF7A45")!
        case .blue: RGB(hex: "#5AC8FA")!
        case .purple: RGB(hex: "#BF5AF2")!
        case .pink: RGB(hex: "#FF6FA8")!
        case .custom(let color): color
        }
    }

    // The shade for a look: 4.5:1 on its background, 7:1 with the contrast increased.
    public func shade(dark: Bool, highContrast: Bool) -> RGB {
        base.readable(on: dark ? Self.darkBackground : Self.lightBackground, ratio: highContrast ? 7 : 4.5)
    }
}
