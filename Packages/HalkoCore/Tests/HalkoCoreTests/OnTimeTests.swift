import Foundation
import HalkoCore
import Testing

struct OnTimeTests {
    @Test("Waits until the date, and not at all for one gone")
    func sleepUntil() async throws {
        let start = Date.now
        try await Task.sleep(until: start - 5)
        #expect(Date.now.timeIntervalSince(start) < 0.1)
        let end = Date.now + 0.3
        try await Task.sleep(until: end)
        #expect(Date.now >= end - 0.01)
    }
}
