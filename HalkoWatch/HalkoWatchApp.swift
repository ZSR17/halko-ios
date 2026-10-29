import HalkoCore
import SwiftData
import SwiftUI

@main
struct HalkoWatchApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try HalkoStore.container()
        } catch {
            fatalError("Cannot open the local database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {}
                    .navigationTitle("Workouts")
            }
        }
        .modelContainer(container)
    }
}
