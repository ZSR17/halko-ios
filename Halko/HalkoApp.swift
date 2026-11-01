import HalkoCore
import SwiftData
import SwiftUI
import UIKit

@main
struct HalkoApp: App {
    private let container: ModelContainer

    init() {
        #if DEBUG
        // The interface tests, without animations: no step waits for one to end.
        if ProcessInfo.processInfo.arguments.contains("-noAnimations") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
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
