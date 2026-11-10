import HalkoCore
import SwiftUI

// The Settings tab: the language and units, then how a session works. What the watch needs of it goes to the watch.
struct SettingsView: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.system
    @AppStorage(Units.weightKey) private var weight: WeightUnit?
    @AppStorage(Units.distanceKey) private var distance: DistanceUnit?
    @Environment(\.units) private var units
    // The two units side by side, wide enough to touch each one easily, growing with the text as far as the row allows.
    @ScaledMetric(relativeTo: .body) private var unitsWidth = 150.0

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LanguageView()
                } label: {
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
                NavigationLink("Set timer") {
                    SetTimerSettingsView()
                }
            } header: {
                Text("Session")
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .navigationTitle("Settings")
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
                    Button {
                        choice.save(to: .standard)
                    } label: {
                        HStack {
                            choice.name
                                .foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if choice == language {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(choice == language ? .isSelected : [])
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
