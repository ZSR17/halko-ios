import HalkoCore
import SwiftData
import SwiftUI

@main
struct HalkoApp: App {
    private let container: ModelContainer

    init() {
        do {
            #if DEBUG
            if DemoData.isRequested {
                container = try DemoData.container()
                return
            }
            #endif
            container = try HalkoStore.container()
        } catch {
            fatalError("Cannot open the local database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    await ExerciseLibrary.install(in: container)
                }
        }
        .modelContainer(container)
    }
}
