import HalkoCore
import SwiftUI

// How the timer of a set works, the same for every exercise, on the iPhone and on the watch.
struct SetTimerSettingsView: View {
    @AppStorage(SetTimerSettings.stopsAtTargetKey) private var stopsAtTarget = false
    @AppStorage(SetTimerSettings.getsInPositionKey) private var getsInPosition = true
    @AppStorage(SetTimerSettings.positionKey) private var positionS = SetTimerSettings.defaultPositionS
    @AppStorage(SetTimerSettings.startsRightKey) private var startsRight = false
    @State private var choosing = false

    var body: some View {
        List {
            Section {
                Picker("At the target", selection: $stopsAtTarget) {
                    Text("Go on until I stop").tag(false)
                    Text("Stop by itself and validate").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("At the target")
                    .foregroundStyle(Color(.secondaryText))
            } footer: {
                Text("Going on, you can hold longer than the target and stop yourself. Stopping by itself, there is nothing to touch: the target is recorded and the rest starts.")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                Toggle("Before the timer", isOn: $getsInPosition)
                if getsInPosition {
                    HStack {
                        Text("Duration")
                            .accessibilityHidden(true)
                        Spacer(minLength: 8)
                        Button {
                            choosing = true
                        } label: {
                            Text(verbatim: FieldText.clock(positionS))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .frame(minWidth: 64, minHeight: 44)
                                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Duration"))
                        .accessibilityValue(Text(verbatim: DurationWheels.spoken(positionS)))
                    }
                }
            } header: {
                Text("Getting in position")
                    .foregroundStyle(Color(.secondaryText))
            } footer: {
                Text("Turned off, the timer starts as soon as you press Start.")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start with")
                    Picker("Start with", selection: $startsRight) {
                        Text("Left").tag(false)
                        Text("Right").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            } header: {
                Text("One side at a time")
                    .foregroundStyle(Color(.secondaryText))
            } footer: {
                Text("For exercises working one side at a time: the side each set starts with, on the iPhone and on the watch.")
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .navigationTitle("Set timer")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $choosing) {
            DurationPicker(title: String(localized: "Getting in position"), subtitle: String(localized: "Set timer"), seconds: positionS) { seconds in
                positionS = seconds
            }
        }
    }
}
