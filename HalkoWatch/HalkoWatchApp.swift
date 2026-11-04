import HalkoCore
import SwiftData
import SwiftUI

@main
struct HalkoWatchApp: App {
    private let container: ModelContainer
    @State private var thumbnails: Thumbnails
    // Keeps what the iPhone sends, for as long as the app runs.
    private let phone: PhoneLink?

    init() {
        let thumbnails = Thumbnails()
        _thumbnails = State(initialValue: thumbnails)
        do {
            #if DEBUG
            if DemoData.isRequested {
                // Nothing from the iPhone either.
                container = try DemoData.container()
                phone = nil
                return
            }
            #endif
            container = try HalkoStore.container()
        } catch {
            fatalError("Cannot open the local database: \(error)")
        }
        phone = PhoneLink(container: container, thumbnails: thumbnails)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WorkoutsView()
            }
            .environment(thumbnails)
            .task {
                await ExerciseLibrary.install(in: container)
            }
        }
        .modelContainer(container)
    }
}
