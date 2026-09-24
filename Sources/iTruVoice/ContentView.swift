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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Text to speak", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Text to speak")
                } header: {
                    Text("Preview text")
                }

                Section {
                    Picker("Voice", selection: $audioManager.selectedVoice) {
                        ForEach(audioManager.voices, id: \.index) { voice in
                            Text(voice.name).tag(voice.index)
                        }
                    }
                    .accessibilityLabel("Voice")

                    Button {
                        audioManager.speak(text: text)
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
                }

                if let error = audioManager.lastError {
                    Section {
                        Text(error)
                    } header: {
                        Text("Problem")
                    }
                }

                Section {
                    Text("Install this app, then find Peter, Sidney, Eager Eddie, Deep Douglas, Biff, Grandpa Amos, Melvin, Alex, Wanda and Julia among the English voices in VoiceOver or Spoken Content settings.")
                } header: {
                    Text("System voices")
                }
            }
            .navigationTitle("iTruVoice")
        }
    }
}
