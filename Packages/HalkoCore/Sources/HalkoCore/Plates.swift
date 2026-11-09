import Foundation

// The plates to put on a bar for a given weight, from those owned. Same as the website (`client/src/lib/plates.ts`).

// A plate owned: `count` is the total, so that a load uses them in pairs, one on each side.
public struct Plate: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var weightG: Int
    public var count: Int

    public init(id: String = UUID().uuidString, weightG: Int, count: Int) {
        self.id = id
        self.weightG = weightG
        self.count = count
    }
}

// What the plate calculator remembers, on this device.
public struct PlateSettings: Codable, Equatable, Sendable {
    public static let storageKey = "plateSettings"

    public var barG: Int?
    public var targetG: Int?
    public var plates: [Plate]

    public init(barG: Int? = nil, targetG: Int? = nil, plates: [Plate] = []) {
        self.barG = barG
        self.targetG = targetG
        self.plates = plates
    }
}

public struct PlateLoad: Equatable, Sendable {
    public struct Side: Equatable, Sendable {
        public let weightG: Int
        public let count: Int
    }

    public let totalG: Int
    public let perSideG: Int
    // On one side, the heaviest first.
    public let perSide: [Side]
}

public enum PlateResult: Equatable, Sendable {
    case exact(PlateLoad)
    // The closest ones; `above` nil without enough plates to go higher.
    case closest(below: PlateLoad, above: PlateLoad?)
}

public enum PlateCalculator {
    // In pounds, weights are counted in hundredths of a pound: plates of 45 or 2.5 lb then add up exactly, which they
    // would not in grams, rounded from pounds.
    public static func load(barG: Int, targetG: Int, plates: [Plate], unit: WeightUnit) -> PlateResult {
        guard unit == .lb else { return load(barG: barG, targetG: targetG, plates: plates) }
        let hundredths = { (grams: Int) in Int((Double(grams) / unit.grams * 100).rounded()) }
        let grams = { (hundredths: Int) in Int((Double(hundredths) / 100 * unit.grams).rounded()) }
        let inGrams = { (load: PlateLoad) in
            PlateLoad(
                totalG: grams(load.totalG),
                perSideG: grams(load.perSideG),
                perSide: load.perSide.map { PlateLoad.Side(weightG: grams($0.weightG), count: $0.count) }
            )
        }
        let counted = plates.map { Plate(id: $0.id, weightG: hundredths($0.weightG), count: $0.count) }
        switch load(barG: hundredths(barG), targetG: hundredths(targetG), plates: counted) {
        case .exact(let load): return .exact(inGrams(load))
        case .closest(let below, let above): return .closest(below: inGrams(below), above: above.map(inGrams))
        }
    }

    // The loads one side of the bar can take, each with as few plates as possible. Weights are counted in steps of the
    // greatest common divisor of the plates, so that the table stays small.
    static func load(barG: Int, targetG: Int, plates: [Plate]) -> PlateResult {
        var pairs: [Int: Int] = [:]
        for plate in plates where plate.weightG > 0 && plate.count >= 2 {
            pairs[plate.weightG, default: 0] += plate.count / 2
        }
        let kinds = pairs.sorted { $0.key > $1.key }
        let step = kinds.reduce(0) { gcd($0, $1.key) }
        let unit = step > 0 ? step : 1
        let most = kinds.reduce(0) { $0 + $1.key / unit * $1.value }

        struct Way {
            let plates: Int
            let used: [Int]
        }
        // The fewest plates making each number of steps on one side.
        var best = [Way?](repeating: nil, count: most + 1)
        best[0] = Way(plates: 0, used: kinds.map { _ in 0 })
        for (kind, plate) in kinds.enumerated() {
            let size = plate.key / unit
            for steps in stride(from: most, through: size, by: -1) {
                var count = 1
                while count <= plate.value, count * size <= steps {
                    if let from = best[steps - count * size], from.plates + count < best[steps]?.plates ?? .max {
                        var used = from.used
                        used[kind] += count
                        best[steps] = Way(plates: from.plates + count, used: used)
                    }
                    count += 1
                }
            }
        }

        let load = { (steps: Int) -> PlateLoad in
            let used = best[steps]?.used ?? []
            return PlateLoad(
                totalG: barG + 2 * steps * unit,
                perSideG: steps * unit,
                perSide: zip(kinds, used).filter { $1 > 0 }.map { PlateLoad.Side(weightG: $0.key, count: $1) }
            )
        }
        let wanted = Double(targetG - barG) / 2 / Double(unit)
        if wanted == wanted.rounded(), wanted >= 0, Int(wanted) <= most, best[Int(wanted)] != nil {
            return .exact(load(Int(wanted)))
        }
        var below = max(0, min(Int(wanted.rounded(.down)), most))
        while best[below] == nil {
            below -= 1
        }
        var above = max(Int(wanted.rounded(.up)), 0)
        while above <= most, best[above] == nil {
            above += 1
        }
        return .closest(below: load(below), above: above <= most ? load(above) : nil)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}
