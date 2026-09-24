import AVFoundation
import Foundation
import TruVoiceKit

/// Plays engine audio through the app so a voice can be auditioned.
///
/// `AVAudioPlayerNode.scheduleBuffer` raises an uncatchable Objective-C
/// exception unless the buffer format exactly matches the node's output
/// format. The engine is mono at 11025 Hz while the node runs at the hardware
/// format, so every utterance is converted with an AVAudioConverter first.
///
/// The engine starts lazily and shuts down once idle: an AVAudioEngine left
/// running holds the audio hardware open for the life of the process.
@MainActor
final class AudioManager: ObservableObject {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    @Published private(set) var isSpeaking = false
    @Published private(set) var lastError: String?
    @Published var selectedVoice: Int = 0

    let voices: [VoiceCatalog.Voice] = VoiceCatalog.all

    private var idleTimer: Task<Void, Never>?
    private var graphReady = false

    init() {
        // Tell the system to rebuild its voice list so the provider's voices
        // are enumerated without waiting for the periodic refresh.
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
    }

    func speak(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stop()
        lastError = nil

        guard let voice = TruVoice(voice: selectedVoice) else {
            lastError = "The engine did not open."
            return
        }
        guard let pcm = voice.synthesize(text), !pcm.isEmpty else {
            lastError = "The engine produced no audio for that text."
            return
        }

        do {
            try startGraphIfNeeded()
            let buffer = try converted(pcm)
            playerNode.scheduleBuffer(buffer) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isSpeaking = false
                    self?.scheduleIdleShutdown()
                }
            }
            playerNode.play()
            isSpeaking = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        idleTimer?.cancel()
        playerNode.stop()
        isSpeaking = false
    }

    // MARK: - Graph

    private func startGraphIfNeeded() throws {
        if graphReady { return }
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        try engine.start()
        graphReady = true
    }

    private func scheduleIdleShutdown() {
        idleTimer?.cancel()
        idleTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self else { return }
            self.playerNode.stop()
            self.engine.stop()
            self.graphReady = false
        }
    }

    /// Converts engine PCM to a buffer the player node accepts.
    private func converted(_ pcm: [Int16]) throws -> AVAudioPCMBuffer {
        let inFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(TruVoice.sampleRate),
            channels: 1,
            interleaved: true
        )!
        let inBuffer = AVAudioPCMBuffer(
            pcmFormat: inFormat,
            frameCapacity: AVAudioFrameCount(pcm.count)
        )!
        inBuffer.frameLength = inBuffer.frameCapacity
        pcm.withUnsafeBufferPointer { src in
            inBuffer.int16ChannelData!.pointee.update(from: src.baseAddress!, count: pcm.count)
        }

        let outFormat = playerNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "iTruVoice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not convert the audio format."])
        }
        let outBuffer = AVAudioPCMBuffer(
            pcmFormat: outFormat,
            frameCapacity: AVAudioFrameCount(Double(pcm.count) * outFormat.sampleRate / inFormat.sampleRate + 16)
        )!
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inBuffer
        }
        if let error { throw error }
        return outBuffer
    }
}
