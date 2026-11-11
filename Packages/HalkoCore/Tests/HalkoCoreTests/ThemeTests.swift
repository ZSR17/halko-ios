import Testing
@testable import HalkoCore

struct ThemeTests {
    @Test func hex() {
        #expect(RGB(hex: "#FF7A45") == RGB(red: 1, green: 122.0 / 255, blue: 69.0 / 255))
        #expect(RGB(hex: "#ff7a45")?.hex == "#FF7A45")
        #expect(RGB(hex: "FF7A45") == nil)
        #expect(RGB(hex: "#FF7A4") == nil)
        #expect(RGB(hex: "#GG0000") == nil)
    }

    @Test func contrast() {
        #expect(abs(RGB.black.contrast(with: .white) - 21) < 0.001)
        #expect(abs(RGB.white.contrast(with: .white) - 1) < 0.001)
        #expect(RGB(hex: "#D4FF3A")!.text == .black)
        #expect(RGB(hex: "#1F3A93")!.text == .white)
    }

    @Test func readable() {
        let background = RGB(hex: "#F2F2F7")!
        // Already readable: unchanged.
        let navy = RGB(hex: "#1F3A93")!
        #expect(navy.readable(on: background, ratio: 4.5) == navy)
        // Darkened just enough.
        let yellow = RGB(hex: "#FFD84D")!
        let shade = yellow.readable(on: background, ratio: 4.5)
        #expect(shade.contrast(with: background) >= 4.5)
        #expect(shade.contrast(with: background) < 4.6)
        #expect(shade.luminance < yellow.luminance)
        // Lightened on a dark background.
        let dark = RGB(hex: "#2C2C2E")!
        let light = navy.readable(on: dark, ratio: 7)
        #expect(light.contrast(with: dark) >= 7)
        #expect(light.luminance > navy.luminance)
    }

    @Test(arguments: ThemeColor.presets + [.custom(RGB(hex: "#FFFFFF")!), .custom(RGB(hex: "#000000")!), .custom(RGB(hex: "#808080")!)])
    func shades(color: ThemeColor) {
        for dark in [false, true] {
            for highContrast in [false, true] {
                let shade = color.shade(dark: dark, highContrast: highContrast)
                let background = dark ? ThemeColor.darkBackground : ThemeColor.lightBackground
                let ratio = highContrast ? 7.0 : 4.5
                #expect(shade.contrast(with: background) >= ratio)
                // The text on it reads as well.
                #expect(shade.contrast(with: shade.text) >= ratio)
            }
        }
    }

    @Test func rawValue() {
        for color in ThemeColor.presets {
            #expect(ThemeColor(rawValue: color.rawValue) == color)
        }
        #expect(ThemeColor(rawValue: "#123456") == .custom(RGB(hex: "#123456")!))
        #expect(ThemeColor.custom(RGB(hex: "#123456")!).rawValue == "#123456")
        #expect(ThemeColor(rawValue: "teal") == nil)
        #expect(Appearance(rawValue: "dark") == .dark)
    }
}
