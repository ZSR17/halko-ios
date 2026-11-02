import HealthKit
import HealthKitUI
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
