import HealthKit
import HealthKitUI
import os
import SwiftUI

// Today's rings, drawn by Apple's own view: empty when Health has nothing to show.
struct ActivityRings: UIViewRepresentable {
    let summary: HKActivitySummary?

    func makeUIView(context: Context) -> HKActivityRingView {
        HKActivityRingView()
    }

    func updateUIView(_ view: HKActivityRingView, context: Context) {
        view.setActivitySummary(summary, animated: true)
    }
}

private nonisolated let ringsLogger = Logger(subsystem: "com.zsr.halko", category: "health")

extension WorkoutRecorder {
    // Today's rings, as Health has them.
    func todayActivity() async -> HKActivitySummary? {
        guard let health else { return nil }
        let calendar = Calendar.current
        var day = calendar.dateComponents([.era, .year, .month, .day], from: .now)
        day.calendar = calendar
        let predicate = HKQuery.predicateForActivitySummary(with: day)
        let found = await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { @Sendable _, summaries, error in
                if let error {
                    ringsLogger.error("Cannot read today's rings: \(String(describing: error))")
                }
                continuation.resume(returning: Handoff(value: summaries?.first))
            }
            health.execute(query)
        }
        return found.value
    }
}
