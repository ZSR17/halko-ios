import HalkoCore
import SwiftUI

// The five tabs, which become a sidebar when there is room. Each tab has its own navigation stack, its title large on
// the line of its buttons, so that the page starts high; with room (the iPhone Duo open), two columns: its list, and the
// page chosen in it. The session in progress covers them, in full screen.
struct RootView: View {
    @Environment(LiveSessionStore.self) private var liveSession

    var body: some View {
        @Bindable var liveSession = liveSession
        TabView {
            Tab("Workouts", systemImage: "dumbbell") {
                WorkoutsTab()
            }
            Tab("Exercises", systemImage: "list.bullet") {
                ExercisesTab()
            }
            Tab("History", systemImage: "clock") {
                HistoryTab()
            }
            Tab("Tools", systemImage: "plus.forwardslash.minus") {
                ToolsTab()
            }
            Tab("Settings", systemImage: "slider.horizontal.3") {
                SettingsTab()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(isPresented: $liveSession.isPresented, onDismiss: { liveSession.finishedElsewhere = nil }) {
            SessionCover()
        }
        // A tap on the session outside the app (lock screen, Dynamic Island).
        .onOpenURL { url in
            if url == SessionActivityAttributes.sessionURL, liveSession.state != nil {
                liveSession.isPresented = true
            }
        }
    }
}
