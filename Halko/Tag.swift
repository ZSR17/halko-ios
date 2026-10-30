import SwiftUI

// A short word in a color, next to a name: "Superset", "One side at a time", "your version"…
struct Tag: View {
    let text: Text
    let color: Color

    init(_ text: Text, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        text
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .rect(cornerRadius: 6))
    }
}
