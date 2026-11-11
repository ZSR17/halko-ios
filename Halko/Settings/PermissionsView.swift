import SwiftUI
import UIKit

// What Health and the notifications allow, written in full, and where to change it. Never asked yet, they are asked
// here, without waiting for the first workout.
struct PermissionsView: View {
    @Environment(Permissions.self) private var permissions
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                LabeledContent("Save the workouts") {
                    AccessText(access: permissions.healthAccess)
                }
                if permissions.healthAccess == .notAsked {
                    Button("Allow") {
                        Task { await permissions.requestHealth() }
                    }
                } else {
                    OutsideLink(title: "Change in Health") {
                        // The Health app; its page for Halko is in Sharing › Apps.
                        if let url = URL(string: "x-apple-health://") {
                            openURL(url)
                        }
                    }
                }
            } header: {
                // In a darker grey than the system's, for a contrast of 4.5:1.
                Text("Health")
                    .foregroundStyle(Color(.secondaryText))
            } footer: {
                Text("Health › Sharing › Apps › Halko. What Halko reads in Health stays on your iPhone.")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                LabeledContent("Rest end as a fallback") {
                    AccessText(access: permissions.notificationAccess)
                }
                if permissions.notificationAccess == .notAsked {
                    Button("Allow") {
                        Task { await permissions.requestNotifications() }
                    }
                } else {
                    OutsideLink(title: permissions.notificationAccess == .refused ? "Allow in Settings" : "Change in Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            } header: {
                Text("Notifications")
                    .foregroundStyle(Color(.secondaryText))
            } footer: {
                Text("Only used if Halko no longer runs during a session. Without them, the end of a rest still sounds.")
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        // Changed in Health or in Settings, they show as they are on coming back.
        .task(id: scenePhase) {
            await permissions.refresh()
        }
    }
}

// An access in words, with a dot of its colour.
private struct AccessText: View {
    let access: Permissions.Access

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            access.name
        }
    }

    private var color: Color {
        switch access {
        case .allowed: .green
        case .refused: .red
        case .notAsked: Color(.secondaryText)
        }
    }
}

// A row that leaves Halko for another app.
private struct OutsideLink: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.secondaryText))
                    .accessibilityHidden(true)
            }
        }
    }
}

extension Permissions.Access {
    var name: Text {
        switch self {
        case .allowed: Text("Allowed")
        case .refused: Text("Refused")
        case .notAsked: Text("Not asked yet")
        }
    }
}
