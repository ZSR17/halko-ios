import HalkoCore
import SwiftUI

// One side of the body, its muscles colored by their role. A picture only: the muscles are also said in words
// next to it.
struct BodyFigure: View {
    let side: BodySide
    let primary: Set<Muscle>
    let secondary: Set<Muscle>

    var body: some View {
        let box = BodyMap.viewBox(side)
        let fills = (Self.paths[side] ?? []).map { shape in
            (shape.path, color(BodyMap.state(of: shape.region, primary: primary, secondary: secondary)))
        }
        Canvas { context, size in
            let scale = min(size.width / box.width, size.height / box.height)
            let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -box.minX, y: -box.minY)
            for (path, color) in fills {
                context.fill(path.applying(transform), with: .color(color))
            }
        }
        .aspectRatio(box.width / box.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func color(_ state: RegionState) -> Color {
        switch state {
        case .primary: Color(.musclePrimary)
        case .secondary: Color(.muscleSecondary)
        case .idle: Color(.muscleIdle)
        case .body: Color(.silhouette)
        }
    }

    // The area of the body (`BodyMap.areas`) drawn at `point` of a figure `size` big, or nil there (head, hands…).
    // A tap a little off a small muscle still finds it.
    static func area(at point: CGPoint, in size: CGSize, side: BodySide) -> [Muscle]? {
        let box = BodyMap.viewBox(side)
        let scale = min(size.width / box.width, size.height / box.height)
        let reach = 8.0
        let offsets = [CGPoint.zero] + (0..<8).map { step in
            let angle = Double(step) * .pi / 4
            return CGPoint(x: cos(angle) * reach, y: sin(angle) * reach)
        }
        for offset in offsets {
            let outline = CGPoint(x: (point.x + offset.x) / scale + box.minX, y: (point.y + offset.y) / scale + box.minY)
            if let shape = paths[side]?.last(where: { $0.path.contains(outline) }) {
                let muscles = BodyMap.muscles(of: shape.region)
                if !muscles.isEmpty {
                    return muscles
                }
            }
        }
        return nil
    }

    // Made once.
    private static let paths: [BodySide: [(region: String, path: Path)]] = BodyMap.shapes.mapValues { shapes in
        shapes.map { ($0.region, Path($0.commands)) }
    }
}

private extension Path {
    init(_ commands: [PathCommand]) {
        self.init()
        for command in commands {
            switch command {
            case .move(let point): move(to: point)
            case .line(let point): addLine(to: point)
            case .quad(let control, let point): addQuadCurve(to: point, control: control)
            case .curve(let control1, let control2, let point): addCurve(to: point, control1: control1, control2: control2)
            case .close: closeSubpath()
            }
        }
    }
}
