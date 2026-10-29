import SwiftUI

@main
struct HalkoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {}
                    .navigationTitle("Workouts")
            }
        }
    }
}
