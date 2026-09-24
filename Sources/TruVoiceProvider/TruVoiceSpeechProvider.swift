import AVFoundation
import AudioToolbox
import Foundation
import TruVoiceKit

/// The rate this provider declares to the host.
///
/// The engine runs at 11025 Hz. Declaring a fixed rate here and resampling
/// during synthesis keeps playback at the right pitch; 22050 is the
/// conventional choice for speech providers.
private let kOutputSampleRate: Double = 22050.0

/// The system-wide voice provider behind iTruVoice.
///
/// VoiceOver loads this as a speech synthesis provider extension. The audio
/// unit pulls samples on a real-time thread while `synthesizeSpeechRequest`
/// runs on another, so the render path never allocates, locks, or blocks:
/// synthesis and resampling happen up front, and the render block is a copy.
///
/// Version 1 speaks the request's plain text at each voice's default rate and
/// pitch. VoiceOver's rate and pitch sliders, and SSML prosody, are not
/// honored yet.
public final class TruVoiceSpeechProvider: AVSpeechSynthesisProviderAudioUnit {

    // MARK: - Render state

    /// One synthesized utterance, already resampled to the output rate.
    /// `position` is advanced only by the render thread, so no lock is needed.
    private final class SpeechState {
        let samples: [Float]
        var position: Int = 0

        init(samples: [Float]) { self.samples = samples }

        var isDrained: Bool { position >= samples.count }
    }

    private var state: SpeechState?
    private let stateLock = NSLock()   // guards swaps only; never taken in render

    /// The engine is kept between requests: one handle per voice index.
    private var engine: TruVoice?
    private var engineVoice: Int?

    // MARK: - Audio unit plumbing

    private var _outputBusses: AUAudioUnitBusArray!
    private var outputBus: AUAudioUnitBus!

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: kOutputSampleRate,
                                         channels: 1) else {
            throw NSError(domain: NSOSStatusErrorDomain,
                          code: Int(kAudioUnitErr_FormatNotSupported))
        }
        outputBus = try AUAudioUnitBus(format: format)
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    // MARK: - Voice registration

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            VoiceCatalog.all.map { voice in
                AVSpeechSynthesisProviderVoice(
                    name: voice.name,
                    identifier: VoiceCatalog.identifier(for: voice.index),
                    primaryLanguages: [voice.language],
                    supportedLanguages: [voice.language]
                )
            }
        }
        set { /* The host may try to set this; the list is derived, not stored. */ }
    }

    // MARK: - Requests

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        guard let voiceIndex = VoiceCatalog.index(from: speechRequest.voice.identifier),
              let text = Self.plainText(from: speechRequest.ssmlRepresentation),
              !text.isEmpty
        else {
            clearState()
            return
        }

        if engineVoice != voiceIndex {
            engine = TruVoice(voice: voiceIndex)
            engineVoice = voiceIndex
        }
        guard let voice = engine,
              let pcm = voice.synthesize(text), !pcm.isEmpty
        else {
            clearState()
            return
        }

        var samples = Self.resample(pcm, from: Double(TruVoice.sampleRate))
        guard !samples.isEmpty else {
            clearState()
            return
        }

        if let block = speechSynthesisOutputMetadataBlock {
            block(Self.wordMarkers(in: text, atByteOffset: 0), speechRequest)
        }

        let newState = SpeechState(samples: samples)
        stateLock.lock()
        state = newState
        stateLock.unlock()
    }

    public override func cancelSpeechRequest() {
        clearState()
    }

    private func clearState() {
        stateLock.lock()
        state = nil
        stateLock.unlock()
    }

    /// The request's text with its SSML markup removed.
    ///
    /// VoiceOver hands the provider SSML; the engine reads plain text. Tags
    /// become spaces (so words on either side do not join) and entities are
    /// decoded, in that order.
    static func plainText(from ssml: String) -> String? {
        var text = ssml.replacingOccurrences(of: "<[^>]+>", with: " ",
                                             options: .regularExpression)
        text = text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "\\s+", with: " ",
                                         options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Word markers across `text`, so the host can highlight as it speaks.
    ///
    /// The range is into the text itself, which the system maps back to the
    /// original markup. The byte offset is where the utterance's audio starts:
    /// the engine reports no per-word timing, so a more precise number would
    /// be invented rather than measured.
    static func wordMarkers(in text: String,
                            atByteOffset startOffset: Int) -> [AVSpeechSynthesisMarker] {
        var markers: [AVSpeechSynthesisMarker] = []
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            guard let range = text.range(of: word) else { continue }
            let location = text.utf16.distance(from: text.utf16.startIndex,
                                               to: range.lowerBound.samePosition(in: text.utf16)
                                               ?? text.utf16.startIndex)
            markers.append(AVSpeechSynthesisMarker(
                wordRange: NSRange(location: location, length: word.utf16.count),
                atByteSampleOffset: startOffset))
        }
        return markers
    }

    // MARK: - Resampling

    /// Linear resample from the engine rate to the output rate, done once here
    /// rather than per frame in the render block.
    static func resample(_ pcm: [Int16], from sourceRate: Double) -> [Float] {
        guard !pcm.isEmpty, sourceRate > 0 else { return [] }

        let step = sourceRate / kOutputSampleRate
        if step == 1.0 { return pcm.map { Float($0) / 32768.0 } }

        let outputCount = Int(Double(pcm.count) / step)
        guard outputCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputCount)
        let lastIndex = pcm.count - 1
        for i in 0..<outputCount {
            let position = Double(i) * step
            let index = Int(position)
            if index >= lastIndex {
                output[i] = Float(pcm[lastIndex]) / 32768.0
                continue
            }
            let fraction = Float(position - Double(index))
            let a = Float(pcm[index]) / 32768.0
            let b = Float(pcm[index + 1]) / 32768.0
            output[i] = a + (b - a) * fraction
        }
        return output
    }

    // MARK: - Real-time render path

    public override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] actionFlags, _, frameCount, _, outputData, _, _ in
            guard let self else { return noErr }

            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard buffers.count > 0,
                  let raw = buffers[0].mData,
                  buffers[0].mDataByteSize >= frameCount * UInt32(MemoryLayout<Float>.size)
            else { return noErr }

            let out = raw.assumingMemoryBound(to: Float.self)
            let written = self.fillBuffer(out, frames: Int(frameCount))

            // Tell the host this request is spent so it stops pulling.
            if written < Int(frameCount), self.currentRequestIsDrained {
                actionFlags.pointee.insert(.offlineUnitRenderAction_Complete)
            }
            return noErr
        }
    }

    /// True when a request exists and has been fully read out.
    private var currentRequestIsDrained: Bool {
        guard let s = state else { return false }
        return s.isDrained
    }

    /// Copies already-resampled samples out, silencing the remainder.
    /// Runs on the audio thread: no allocation, no locks.
    func fillBuffer(_ buffer: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        guard frames > 0, let s = state else {
            buffer.update(repeating: 0, count: frames)
            return 0
        }

        let count = min(frames, s.samples.count - s.position)
        if count > 0 {
            s.samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                buffer.update(from: base + s.position, count: count)
            }
            s.position += count
        }
        if count < frames {
            (buffer + count).update(repeating: 0, count: frames - count)
        }
        return count
    }
}
