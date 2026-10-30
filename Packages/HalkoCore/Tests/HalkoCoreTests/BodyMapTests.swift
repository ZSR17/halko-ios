import CoreGraphics
import Testing
@testable import HalkoCore

struct BodyMapTests {
    @Test("Reads every outline of both sides")
    func outlines() throws {
        let shapes = try BodyMap.load()
        #expect(shapes[.front]?.count == 89)
        #expect(shapes[.back]?.count == 70)
        #expect(BodyMap.shapes[.front]?.count == 89)
        // Every muscle can be shown.
        let regions = Set(shapes.values.joined().map(\.region))
        let shown = Set(regions.compactMap { BodyMap.regionMuscles[$0] }.joined())
        #expect(shown == Set(Muscle.allCases))
        // The back is drawn right of the front.
        let backX = shapes[.back]?.flatMap(\.commands).compactMap { command -> CGFloat? in
            if case .move(let point) = command { point.x } else { nil }
        }
        #expect(backX?.allSatisfy { $0 > BodyMap.viewBox(.back).minX } == true)
    }

    @Test("Colors a region by the role of its muscles")
    func states() {
        #expect(BodyMap.state(of: "upper-back", primary: [.lats], secondary: []) == .primary)
        #expect(BodyMap.state(of: "upper-back", primary: [.quads], secondary: [.middleback]) == .secondary)
        #expect(BodyMap.state(of: "chest", primary: [.quads], secondary: []) == .idle)
        #expect(BodyMap.state(of: "head", primary: [.quads], secondary: []) == .body)
    }

    @Test("Reads absolute and relative commands, implicit lines and arcs")
    func pathData() throws {
        let commands = try SVGPath.commands("M10 20l5-5 1.5.5q1 1 2 2c1 1 2 2 3 3a.5.5 0 01.5.5zm1 1L0 0Z")
        #expect(commands == [
            .move(CGPoint(x: 10, y: 20)),
            .line(CGPoint(x: 15, y: 15)),
            .line(CGPoint(x: 16.5, y: 15.5)),
            .quad(control: CGPoint(x: 17.5, y: 16.5), to: CGPoint(x: 18.5, y: 17.5)),
            .curve(control1: CGPoint(x: 19.5, y: 18.5), control2: CGPoint(x: 20.5, y: 19.5), to: CGPoint(x: 21.5, y: 20.5)),
            .line(CGPoint(x: 22, y: 21)),
            .close,
            .move(CGPoint(x: 11, y: 21)),
            .line(CGPoint(x: 0, y: 0)),
            .close,
        ])
        #expect(throws: SVGPath.SyntaxError.self) {
            try SVGPath.commands("10 20")
        }
        #expect(throws: SVGPath.SyntaxError.self) {
            try SVGPath.commands("M0 0H10")
        }
    }
}
