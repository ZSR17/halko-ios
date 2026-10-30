import SwiftUI

// The five tabs, which become a sidebar when there is room. Each tab has its own navigation stack.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Workouts", systemImage: "dumbbell") {
                NavigationStack {
                    WorkoutsView()
                }
            }
            Tab("Exercises", systemImage: "list.bullet") {
                NavigationStack {
                    ExercisesView()
                }
            }
            Tab("History", systemImage: "clock") {
                NavigationStack {
                    List {}
                        .navigationTitle("History")
                }
            }
            Tab("Tools", systemImage: "plus.forwardslash.minus") {
                NavigationStack {
                    List {}
                        .navigationTitle("Tools")
                }
            }
            Tab("Settings", systemImage: "slider.horizontal.3") {
                NavigationStack {
                    List {}
                        .navigationTitle("Settings")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
