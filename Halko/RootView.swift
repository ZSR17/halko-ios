import HalkoCore
import SwiftUI

// The five tabs, which become a sidebar when there is room. Each tab has its own navigation stack, its title large on
// the line of its buttons, so that the page starts high. The session in progress covers them, in full screen.
struct RootView: View {
    @Environment(LiveSessionStore.self) private var liveSession

    var body: some View {
        @Bindable var liveSession = liveSession
        TabView {
            Tab("Workouts", systemImage: "dumbbell") {
                NavigationStack {
                    WorkoutsView()
                        .toolbarTitleDisplayMode(.inlineLarge)
                }
            }
            Tab("Exercises", systemImage: "list.bullet") {
                NavigationStack {
                    ExercisesView()
                        .toolbarTitleDisplayMode(.inlineLarge)
                }
            }
            Tab("History", systemImage: "clock") {
                NavigationStack {
                    HistoryView()
                        .toolbarTitleDisplayMode(.inlineLarge)
                }
            }
            Tab("Tools", systemImage: "plus.forwardslash.minus") {
                NavigationStack {
                    List {}
                        .navigationTitle("Tools")
                        .toolbarTitleDisplayMode(.inlineLarge)
                }
            }
            Tab("Settings", systemImage: "slider.horizontal.3") {
                NavigationStack {
                    List {
                        Section("Session") {
                            NavigationLink("Set timer") {
                                SetTimerSettingsView()
                            }
                        }
                    }
                    .navigationTitle("Settings")
                    .toolbarTitleDisplayMode(.inlineLarge)
                }
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
