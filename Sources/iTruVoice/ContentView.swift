import SwiftUI
import TruVoiceKit

/// The app's single screen: a test bench for the engine.
///
/// Installing the app is what registers the voices with the system. The
/// provider extension's voices (Peter, Deep Douglas, Julia and the rest)
/// then appear as English voices for VoiceOver and Spoken Content.
struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var text: String = VoiceCatalog.sampleText
    @State private var rate: Double = 50
    @State private var pitch: Double = 50

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Text to speak", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Text to speak")
                } header: {
                    Text("Preview text")
                        .textCase(nil)
                }

                Section {
                    Picker("Voice", selection: $audioManager.selectedVoice) {
                        ForEach(audioManager.voices, id: \.index) { voice in
                            Text(voice.name).tag(voice.index)
                        }
                    }
                    .accessibilityLabel("Voice")

                    Button {
                        audioManager.speak(text: text, rate: rate, pitch: pitch)
                    } label: {
                        Label("Speak", systemImage: "play.circle.fill")
                            .frame(minHeight: 44)
                    }

                    Button(role: .destructive) {
                        audioManager.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .frame(minHeight: 44)
                    }
                    .disabled(!audioManager.isSpeaking)
                } header: {
                    Text("Test the engine")
                        .textCase(nil)
                }

                Section {
                    Slider(value: $rate, in: 0...100, step: 1) {
                        Text("Rate")
                    } minimumValueLabel: {
                        Text("Slow")
                    } maximumValueLabel: {
                        Text("Fast")
                    }
                    .accessibilityLabel("Rate")
                    Slider(value: $pitch, in: 0...100, step: 1) {
                        Text("Pitch")
                    } minimumValueLabel: {
                        Text("Low")
                    } maximumValueLabel: {
                        Text("High")
                    }
                    .accessibilityLabel("Pitch")
                } header: {
                    Text("Voice settings")
                        .textCase(nil)
                }

                if let error = audioManager.lastError {
                    Section {
                        Text(error)
                    } header: {
                        Text("Problem")
                            .textCase(nil)
                    }
                }

                Section {
                    Text("Install this app, then find Peter, Sidney, Eager Eddie, Deep Douglas, Biff, Grandpa Amos, Melvin, Alex, Wanda and Julia among the English voices in VoiceOver or Spoken Content settings.")
                } header: {
                    Text("System voices")
                        .textCase(nil)
                }

                Section {
                    Text(Self.versionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Self.versionText)
                } header: {
                    Text("About")
                        .textCase(nil)
                }
            }
            .navigationTitle("iTruVoice")
        }
    }

    /// What this copy of the app is, so a bug report can name the build.
    ///
    /// Read from the bundle rather than written here: a version hard-coded in a
    /// view goes stale the first time a release is cut, and a wrong version in a
    /// bug report is worse than none.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "Version \(version), build \(build)"
    }
}
