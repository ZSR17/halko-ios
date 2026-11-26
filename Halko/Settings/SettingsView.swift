import HalkoCore
import SwiftUI

// The Settings tab: the language and units, how a session works, Health and the notifications, the look of the app and its data.
// What the watch needs of it goes to the watch. With room (the iPhone Duo open), the page chosen beside the list.
struct SettingsTab: View {
    var body: some View {
        TabColumns(first: SettingsPage.language) { chosen in
            SettingsView(chosen: chosen)
        } detail: { page in
            page.view
        } stack: {
            SettingsView(chosen: nil)
        }
    }
}

private enum SettingsPage {
    case language, restEnd, setTimer, permissions, theme, data

    @ViewBuilder var view: some View {
        switch self {
        case .language: LanguageView()
        case .restEnd: RestAlertSettingsView()
        case .setTimer: SetTimerSettingsView()
        case .permissions: PermissionsView()
        case .theme: ThemeSettingsView()
        case .data: DataSettingsView()
        }
    }
}

private struct SettingsView: View {
    // Beside the list, the page shown; nil when a page opens over the list.
    let chosen: Binding<SettingsPage?>?
    @AppStorage(AppLanguage.key) private var language = AppLanguage.system
    @AppStorage(Units.weightKey) private var weight: WeightUnit?
    @AppStorage(Units.distanceKey) private var distance: DistanceUnit?
    @AppStorage(RestAlertSettings.placeKey) private var alertPlace = RestAlertSettings.Place.watch
    @AppStorage(RestAlertSettings.soundKey) private var alertSound = true
    @AppStorage(RestAlertSettings.vibrationKey) private var alertVibration = true
    @AppStorage(HealthSaving.key) private var savesInHealth = true
    @AppStorage(Appearance.key) private var appearance = Appearance.auto
    @Environment(Permissions.self) private var permissions
    @Environment(\.units) private var units
    @Environment(\.scenePhase) private var scenePhase
    // The two units side by side, wide enough to touch each one easily, growing with the text as far as the row allows.
    @ScaledMetric(relativeTo: .body) private var unitsWidth = 150.0

    var body: some View {
        Group {
            if let chosen {
                List(selection: chosen) {
                    sections
                }
            } else {
                List {
                    sections
                }
            }
        }
        .navigationTitle("Settings")
        .task(id: scenePhase) {
            await permissions.refresh()
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            link(.language) {
                LabeledContent("Language") {
                    language.name
                }
            }
            HStack {
                Text("Weight")
                Spacer(minLength: 8)
                Picker("Weight", selection: Binding { weight ?? units.weight } set: { weight = $0 }) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(verbatim: unit.rawValue)
                            .tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                .frame(maxWidth: unitsWidth)
            }
            HStack {
                Text("Distance")
                Spacer(minLength: 8)
                Picker("Distance", selection: Binding { distance ?? units.distance } set: { distance = $0 }) {
                    ForEach(DistanceUnit.allCases, id: \.self) { unit in
                        Text(verbatim: unit.rawValue)
                            .tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                .frame(maxWidth: unitsWidth)
            }
        } header: {
            // In a darker grey than the system's, for a contrast of 4.5:1.
            Text("Language and units")
                .foregroundStyle(Color(.secondaryText))
        }
        Section {
            link(.restEnd) {
                LabeledContent("Rest end") {
                    Text(verbatim: restAlert)
                }
            }
            link(.setTimer) {
                Text("Set timer")
            }
        } header: {
            Text("Session")
                .foregroundStyle(Color(.secondaryText))
        }
        Section {
            Toggle("Save in Health", isOn: $savesInHealth)
            link(.permissions) {
                LabeledContent("Permissions") {
                    permissionsSummary
                }
            }
        } header: {
            Text("Health and notifications")
                .foregroundStyle(Color(.secondaryText))
        }
        Section {
            link(.theme) {
                LabeledContent("Theme and color") {
                    appearance.name
                }
            }
            link(.data) {
                LabeledContent("My data") {
                    Text("Export, import")
                }
            }
        } header: {
            Text("Appearance and data")
                .foregroundStyle(Color(.secondaryText))
        }
    }

    // A line that opens its page: over the list, or beside it, marked while shown.
    @ViewBuilder private func link<Label: View>(_ page: SettingsPage, @ViewBuilder label: () -> Label) -> some View {
        if chosen != nil {
            label()
                .tag(page)
        } else {
            NavigationLink {
                page.view
            } label: {
                label()
            }
        }
    }

    private var permissionsSummary: Text {
        let accesses = [permissions.healthAccess, permissions.notificationAccess]
        if accesses.contains(.refused) {
            return Text("Some refused")
        }
        if accesses.contains(.notAsked) {
            return Text("To allow")
        }
        return Text("All allowed")
    }

    // "Watch · sound, vibration".
    private var restAlert: String {
        let told = [alertSound ? String(localized: "sound") : nil, alertVibration ? String(localized: "vibration") : nil].compactMap(\.self)
        return "\(alertPlace.shortName) · \(told.isEmpty ? String(localized: "silent") : told.joined(separator: ", "))"
    }
}

// The language of the app, applied the next time it opens: the system reads it only then.
private struct LanguageView: View {
    // The one the app runs in, until it opens again.
    private static let running = AppLanguage(defaults: .standard)

    @AppStorage(AppLanguage.key) private var language = AppLanguage.system

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases, id: \.self) { choice in
                    CheckRow(label: choice.name, checked: choice == language) {
                        choice.save(to: .standard)
                    }
                }
            } footer: {
                if language != Self.running {
                    Text("Halko will be in this language the next time it opens, on the iPhone and on the watch.")
                        .foregroundStyle(Color(.secondaryText))
                }
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension AppLanguage {
    // Each language in itself, as the system writes them.
    var name: Text {
        switch self {
        case .system: Text("Same as the iPhone")
        case .fr: Text(verbatim: "Français")
        case .en: Text(verbatim: "English")
        }
    }
}
