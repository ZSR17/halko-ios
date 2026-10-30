import CoreGraphics
import Foundation
import os

// The body seen from the front and from the back, its muscles colored by the role they play. Anatomical outlines
// from react-native-body-highlighter (MIT, see NOTICE), the same as on the website.
public enum BodySide: String, Sendable, CaseIterable {
    case front, back
}

public enum RegionState: Sendable {
    case primary, secondary, idle, body
}

// A region of the outline (a muscle, the head…) drawn as one shape.
public struct BodyShape: Sendable {
    public let region: String
    public let commands: [PathCommand]
}

// In the coordinates of the outlines (`BodyMap.viewBox`).
public enum PathCommand: Equatable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(control: CGPoint, to: CGPoint)
    case curve(control1: CGPoint, control2: CGPoint, to: CGPoint)
    case close
}

public enum BodyMap {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "body map")

    // Regions -> muscles. The regions not listed (head, hands, knees…) are drawn as plain body.
    static let regionMuscles: [String: [Muscle]] = [
        "chest": [.chest],
        "abs": [.abs],
        "obliques": [.abs],
        "biceps": [.biceps],
        "triceps": [.triceps],
        "forearm": [.forearms],
        "deltoids": [.shoulders],
        "trapezius": [.traps],
        "neck": [.neck],
        "upper-back": [.lats, .middleback],
        "lower-back": [.lowerback],
        "gluteal": [.glutes, .abductors],
        "adductors": [.adductors],
        "quadriceps": [.quads],
        "hamstring": [.hamstrings],
        "calves": [.calves],
        "tibialis": [],
    ]

    public static func state(of region: String, primary: Set<Muscle>, secondary: Set<Muscle>) -> RegionState {
        guard let muscles = regionMuscles[region] else { return .body }
        if muscles.contains(where: primary.contains) {
            return .primary
        }
        if muscles.contains(where: secondary.contains) {
            return .secondary
        }
        return .idle
    }

    // The part of the outlines' plane where each side is drawn.
    public static func viewBox(_ side: BodySide) -> CGRect {
        switch side {
        case .front: CGRect(x: 0, y: 0, width: 724, height: 1448)
        case .back: CGRect(x: 724, y: 0, width: 724, height: 1448)
        }
    }

    // Read once, on first use.
    public static let shapes: [BodySide: [BodyShape]] = {
        do {
            return try load()
        } catch {
            logger.error("Cannot read the body outlines: \(String(describing: error))")
            return [:]
        }
    }()

    private struct OutlineFile: Decodable {
        struct Path: Decodable {
            let r: String
            let d: String
        }

        let front: [Path]
        let back: [Path]
    }

    static func load() throws -> [BodySide: [BodyShape]] {
        guard let url = Bundle.module.url(forResource: "body-paths", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let file = try JSONDecoder().decode(OutlineFile.self, from: Data(contentsOf: url))
        let shapes = { (paths: [OutlineFile.Path]) in
            try paths.map { BodyShape(region: $0.r, commands: try SVGPath.commands($0.d)) }
        }
        return [.front: try shapes(file.front), .back: try shapes(file.back)]
    }
}

// The path data of an SVG `<path>` (`d`), with the commands the outlines use.
enum SVGPath {
    struct SyntaxError: Error {
        let offset: Int
    }

    static func commands(_ data: String) throws -> [PathCommand] {
        var reader = Reader(Array(data.utf8))
        var commands: [PathCommand] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: UInt8 = 0
        while true {
            reader.skipSeparators()
            guard !reader.isAtEnd else { break }
            if let letter = reader.letter() {
                command = letter
            } else if command == 0 {
                throw SyntaxError(offset: reader.offset)
            }
            let relative = command >= UInt8(ascii: "a")
            let origin = relative ? current : .zero
            func point() throws -> CGPoint {
                let x = try reader.number()
                let y = try reader.number()
                return CGPoint(x: origin.x + x, y: origin.y + y)
            }
            switch command | 0x20 {
            case UInt8(ascii: "m"):
                current = try point()
                start = current
                commands.append(.move(current))
                // Coordinates after a move are lines.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "l"):
                current = try point()
                commands.append(.line(current))
            case UInt8(ascii: "q"):
                let control = try point()
                current = try point()
                commands.append(.quad(control: control, to: current))
            case UInt8(ascii: "c"):
                let control1 = try point()
                let control2 = try point()
                current = try point()
                commands.append(.curve(control1: control1, control2: control2, to: current))
            case UInt8(ascii: "a"):
                // The arcs of the outlines are a couple of units across, out of 1448 for the height of the body:
                // a line to their end is the same once drawn.
                for _ in 0..<3 {
                    _ = try reader.number()
                }
                _ = try reader.flag()
                _ = try reader.flag()
                current = try point()
                commands.append(.line(current))
            case UInt8(ascii: "z"):
                commands.append(.close)
                current = start
                command = 0
            default:
                throw SyntaxError(offset: reader.offset)
            }
        }
        return commands
    }

    private struct Reader {
        let bytes: [UInt8]
        private(set) var offset = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        var isAtEnd: Bool {
            offset == bytes.count
        }

        mutating func skipSeparators() {
            while offset < bytes.count, [UInt8(ascii: " "), UInt8(ascii: ","), UInt8(ascii: "\n")].contains(bytes[offset]) {
                offset += 1
            }
        }

        mutating func letter() -> UInt8? {
            let byte = bytes[offset]
            guard (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) else {
                return nil
            }
            offset += 1
            return byte
        }

        // "-.5", "12.25"; "1.5.5" is two numbers, 1.5 and .5.
        mutating func number() throws -> Double {
            skipSeparators()
            let begin = offset
            if offset < bytes.count, bytes[offset] == UInt8(ascii: "-") || bytes[offset] == UInt8(ascii: "+") {
                offset += 1
            }
            var dot = false
            while offset < bytes.count {
                let byte = bytes[offset]
                if byte == UInt8(ascii: "."), !dot {
                    dot = true
                } else if !(UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                    break
                }
                offset += 1
            }
            guard let number = Double(String(decoding: bytes[begin..<offset], as: UTF8.self)) else {
                throw SyntaxError(offset: begin)
            }
            return number
        }

        // An arc flag is a single digit, often written next to the following number ("01.5").
        mutating func flag() throws -> Bool {
            skipSeparators()
            guard offset < bytes.count, bytes[offset] == UInt8(ascii: "0") || bytes[offset] == UInt8(ascii: "1") else {
                throw SyntaxError(offset: offset)
            }
            offset += 1
            return bytes[offset - 1] == UInt8(ascii: "1")
        }
    }
}
