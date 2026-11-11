import AudioToolbox
import AVFAudio
import HalkoCore
import os
import SwiftUI

// How the end of a rest is told: where, the sound, the vibration, the countdown before it. The watch gets a copy.
struct RestAlertSettingsView: View {
    @AppStorage(RestAlertSettings.placeKey) private var place = RestAlertSettings.Place.watch
    @AppStorage(RestAlertSettings.soundKey) private var sound = true
    @AppStorage(RestAlertSettings.toneKey) private var tone = RestAlertSettings.Tone.halko
    @AppStorage(RestAlertSettings.volumeKey) private var volume = 1.0
    @AppStorage(RestAlertSettings.vibrationKey) private var vibration = true
    @AppStorage(RestAlertSettings.watchHapticKey) private var watchHaptic = RestAlertSettings.WatchHaptic.strong
    @AppStorage(RestAlertSettings.countdownKey) private var countdown = RestAlertSettings.Countdown.none
    @State private var preview = TonePreview()

    var body: some View {
        List {
            Section {
                Picker("Where to alert", selection: $place) {
                    ForEach(RestAlertSettings.Place.allCases, id: \.self) { place in
                        place.name
                            .tag(place)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                // In a darker grey than the system's, for a contrast of 4.5:1.
                Text("Where to alert")
                    .foregroundStyle(Color(.secondaryText))
            } footer: {
                Text("Without the watch on the wrist, the iPhone alerts.")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                Toggle("Sound", isOn: $sound)
                if sound {
                    NavigationLink {
                        ToneView(tone: $tone, volume: volume, preview: preview)
                    } label: {
                        LabeledContent("Ringtone") {
                            tone.name
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(Color(.secondaryText))
                            .accessibilityHidden(true)
                        Slider(value: $volume, in: 0...1) {
                            Text("Volume")
                        } onEditingChanged: { editing in
                            if !editing {
                                preview.play(tone, volume: volume)
                            }
                        }
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(Color(.secondaryText))
                            .accessibilityHidden(true)
                    }
                }
            } header: {
                Text("Sound")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                Toggle("Vibration", isOn: $vibration)
                if vibration {
                    NavigationLink {
                        WatchHapticView(haptic: $watchHaptic)
                    } label: {
                        LabeledContent("On the watch") {
                            watchHaptic.name
                        }
                    }
                }
            } header: {
                Text("Vibration")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                // The choices alone, without the card of a row.
                Picker("Signal before the end", selection: $countdown) {
                    ForEach(RestAlertSettings.Countdown.allCases, id: \.self) { countdown in
                        countdown.name
                            .tag(countdown)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Signal before the end")
                    .foregroundStyle(Color(.secondaryText))
            } footer: {
                Text("Short beeps, or taps when the sound is off.")
                    .foregroundStyle(Color(.secondaryText))
            }
            Section {
                Button(action: tryAlert) {
                    Text("Try the alert")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Rest end")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Where it will be told: the watch when its app is open to feel it, the iPhone otherwise or as well.
    private func tryAlert() {
        let alert = RestAlertSettings(defaults: .standard)
        let onWatch = alert.place != .iPhone && alert.vibration && WatchLink.play(alert.watchHaptic)
        guard alert.place != .watch || !onWatch else { return }
        if alert.sound {
            preview.play(alert.tone, volume: alert.volume)
        }
        if alert.vibration {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}

// The sounds, each heard when touched.
private struct ToneView: View {
    @Binding var tone: RestAlertSettings.Tone
    let volume: Double
    let preview: TonePreview

    var body: some View {
        List {
            ForEach(RestAlertSettings.Tone.allCases, id: \.self) { choice in
                CheckRow(label: choice.name, checked: choice == tone) {
                    tone = choice
                    preview.play(choice, volume: volume)
                }
            }
        }
        .navigationTitle("Ringtone")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// The vibrations of the watch, each felt on it when touched, when its app is open.
private struct WatchHapticView: View {
    @Binding var haptic: RestAlertSettings.WatchHaptic

    var body: some View {
        List {
            ForEach(RestAlertSettings.WatchHaptic.allCases, id: \.self) { choice in
                CheckRow(label: choice.name, checked: choice == haptic) {
                    haptic = choice
                    WatchLink.play(choice)
                }
            }
        }
        .navigationTitle("On the watch")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// A choice of a list, ticked when it is the one chosen.
struct CheckRow: View {
    let label: Text
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                label
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

// A sound heard at once, over the music as at the end of a rest.
@MainActor
final class TonePreview {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "settings")
    private var player: AVAudioPlayer?

    func play(_ tone: RestAlertSettings.Tone, volume: Double) {
        guard let url = Bundle.main.url(forResource: tone.fileName, withExtension: "wav") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(volume)
            player.play()
            self.player = player
        } catch {
            Self.logger.error("Cannot play the sound: \(String(describing: error))")
        }
    }
}

extension RestAlertSettings.Place {
    var name: Text {
        switch self {
        case .watch: Text("The watch, when it is on the wrist")
        case .iPhone: Text("The iPhone")
        case .both: Text("Both")
        }
    }

    // In the row of the settings.
    var shortName: String {
        switch self {
        case .watch: String(localized: "Watch")
        case .iPhone: String(localized: "iPhone")
        case .both: String(localized: "Watch and iPhone")
        }
    }
}

extension RestAlertSettings.Tone {
    var name: Text {
        switch self {
        case .halko: Text(verbatim: "Halko")
        case .gong: Text("Gong")
        case .whistle: Text("Whistle")
        case .beep: Text("Beep")
        }
    }
}

extension RestAlertSettings.WatchHaptic {
    var name: Text {
        switch self {
        case .strong: Text("Strong")
        case .rising: Text("Rising")
        case .notification: Text("Notification")
        }
    }
}

extension RestAlertSettings.Countdown {
    var name: Text {
        switch self {
        case .none: Text("None")
        case .threeTwoOne: Text(verbatim: "3, 2, 1")
        case .ten: Text(verbatim: "10 s")
        }
    }
}
