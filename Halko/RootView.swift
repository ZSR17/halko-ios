import SwiftUI

// The five tabs, which become a sidebar when there is room. Each tab has its own navigation stack.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Workouts", systemImage: "dumbbell") {
                NavigationStack {
                    List {}
                        .navigationTitle("Workouts")
                }
            }
            Tab("Exercises", systemImage: "list.bullet") {
                NavigationStack {
                    List {}
                        .navigationTitle("Exercises")
                }
            }
            Tab("History", systemImage: "clock") {
                NavigationStack {
                    List {}
                        .navigationTitle("History")
                }
            }
            Tab("Tools", systemImage: "calculator") {
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
