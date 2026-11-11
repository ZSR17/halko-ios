import Foundation

extension Task where Success == Never, Failure == Never {
    // Until `date`, on time. Without a tolerance of its own, a wait may end late by up to a tenth of its length (9 s
    // for a rest of 90 s): the vibration at the end of a rest would come long after its sound.
    public static func sleep(until date: Date) async throws {
        try await sleep(for: .seconds(max(0, date.timeIntervalSinceNow)), tolerance: .milliseconds(10))
    }
}
