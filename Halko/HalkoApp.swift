import HalkoCore
import SwiftData
import SwiftUI

@main
struct HalkoApp: App {
    private let container: ModelContainer
    @State private var liveSession: LiveSessionStore

    init() {
        do {
            #if DEBUG
            if DemoData.isRequested {
                container = try DemoData.container()
                // The device's own session in progress is never touched either.
                _liveSession = State(initialValue: LiveSessionStore(fileURL: nil))
                return
            }
            #endif
            container = try HalkoStore.container()
            _liveSession = State(initialValue: LiveSessionStore(fileURL: LiveSessionStore.defaultFileURL))
        } catch {
            fatalError("Cannot open the local database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(liveSession)
                .task {
                    await ExerciseLibrary.install(in: container)
                }
        }
        .modelContainer(container)
    }
}
