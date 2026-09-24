import AVFoundation
import AudioToolbox
import Foundation
import TruVoiceKit
import TruVoiceCore

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
/// Each SSML speech piece is synthesized on its own with the prosody in force
/// over it: VoiceOver's rate and pitch sliders arrive as `prosody` elements,
/// and they are honored per piece through the engine's rate (words per
/// minute) and absolute pitch. `mark` elements become engine index marks
/// embedded ahead of the word they precede, so bookmarks report the exact
/// sample where synthesis reached them. Pauses become silence. A piece at
/// volume 0 is skipped outright — the engine's own volume is a threshold,
/// not a scale, so quiet is done as a sample gain instead.
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
        guard let voiceIndex = VoiceCatalog.index(from: speechRequest.voice.identifier) else {
            clearState()
            return
        }

        if engineVoice != voiceIndex {
            engine = TruVoice(voice: voiceIndex)
            engineVoice = voiceIndex
        }
        guard let voice = engine else {
            clearState()
            return
        }

        let parsed = SSMLText.parse(speechRequest.ssmlRepresentation)
        guard !parsed.pieces.isEmpty else {
            clearState()
            return
        }

        // VoiceOver's neutral is the voice's own defaults, so an untouched
        // voice sounds untouched.
        let neutralRate = VoiceParameters.rate(forVoiceOver: 50,
                                               defaultWPM: voice.defaultRateWPM)
        let neutralPitch = VoiceParameters.pitch(forVoiceOver: 50,
                                                 defaultPitch: voice.defaultPitch)

        var samples: [Float] = []
        var markers: [AVSpeechSynthesisMarker] = []
        // Bookmarks wait here for the next sounding piece; a mark is embedded
        // ahead of the word it precedes, never after the last word.
        var pendingBookmarks: [String] = []
        var nextMarkID: UInt32 = 1
        var markNames: [UInt32: String] = [:]

        for piece in parsed.pieces {
            switch piece {
            case .speech(let text, let pitch, let rate, let volume):
                guard !text.isEmpty else { continue }

                let gain = VoiceParameters.gain(forVoiceOver: volume)
                guard gain > 0 else { continue }   // volume 0: silence

                // Both settings are set every time, so a prosody element that
                // adjusts only one of them does not inherit the other's
                // previous value. The engine's settings persist across
                // utterances, as SAPI's did.
                voice.setRate(wpm: rate.map {
                    VoiceParameters.rate(forVoiceOver: Double($0),
                                         defaultWPM: voice.defaultRateWPM)
                } ?? neutralRate)
                voice.setPitch(pitch.map {
                    VoiceParameters.pitch(forVoiceOver: Double($0),
                                          defaultPitch: voice.defaultPitch)
                } ?? neutralPitch)

                // Bookmarks ride ahead of this piece's text as index marks.
                var markedText = ""
                var pieceMarkIDs: [UInt32] = []
                for name in pendingBookmarks {
                    if let escape = TruVoice.markEscape(id: nextMarkID) {
                        markedText += escape
                        markNames[nextMarkID] = name
                        pieceMarkIDs.append(nextMarkID)
                        nextMarkID &+= 1
                    }
                }
                pendingBookmarks.removeAll()
                markedText += text

                guard let uttered = voice.synthesize(markedText),
                      !uttered.samples.isEmpty else { continue }

                if speechSynthesisOutputMetadataBlock != nil {
                    let pieceStartBytes = samples.count * 4
                    markers.append(contentsOf: Self.wordMarkers(in: text,
                                                                atByteOffset: pieceStartBytes))
                    for mark in uttered.marks {
                        guard let name = markNames[mark.id] else { continue }
                        let outIndex = Self.resampledIndex(engineIndex: mark.samplePosition)
                        markers.append(AVSpeechSynthesisMarker(
                            bookmarkName: name,
                            atByteSampleOffset: pieceStartBytes + outIndex * 4))
                    }
                }
                for id in pieceMarkIDs { markNames.removeValue(forKey: id) }
                samples.append(contentsOf: Self.resample(uttered.samples,
                                                         from: Double(TruVoice.sampleRate),
                                                         gain: gain))

            case .pause(let seconds):
                // Silence is the only pause available: the engine renders one
                // utterance at a time and offers no rest primitive.
                let frames = Int(seconds * kOutputSampleRate)
                if frames > 0 { samples.append(contentsOf: repeatElement(0, count: frames)) }

            case .bookmark(let name):
                pendingBookmarks.append(name)
            }
        }

        // Bookmarks with no sounding text after them point at the end.
        if speechSynthesisOutputMetadataBlock != nil {
            for name in pendingBookmarks {
                markers.append(AVSpeechSynthesisMarker(bookmarkName: name,
                                                       atByteSampleOffset: samples.count * 4))
            }
        }

        guard !samples.isEmpty else {
            clearState()
            return
        }

        // Markers describe positions in the audio, so the host gets them once
        // the audio they refer to exists.
        if let block = speechSynthesisOutputMetadataBlock, !markers.isEmpty {
            block(markers, speechRequest)
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

    /// An engine-sample position as an output-sample index. The resample is
    /// linear at a fixed ratio, so the mapping is exact: each engine sample
    /// lands exactly `kOutputSampleRate / TruVoice.sampleRate` outputs on.
    static func resampledIndex(engineIndex: UInt32) -> Int {
        Int((Double(engineIndex) * kOutputSampleRate / Double(TruVoice.sampleRate)).rounded())
    }

    /// Word markers across `text`, so the host can highlight as it speaks.
    ///
    /// The range is into the text itself, which the system maps back to the
    /// original markup. The byte offset is where the piece's audio starts —
    /// the engine reports no per-word timing of its own, so `mark` bookmarks
    /// (which do carry exact positions) sit alongside these, not instead.
    /// The host is documented to accept markers that reference audio not yet
    /// delivered, so this is within the contract.
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

    /// Linear resample from the engine rate to the output rate, with a gain
    /// for the piece's VoiceOver volume. Done once here rather than per frame
    /// in the render block. Linear interpolation is adequate for speech at
    /// these rates and leaves the audio thread doing nothing but a copy.
    static func resample(_ pcm: [Int16], from sourceRate: Double, gain: Float = 1.0) -> [Float] {
        guard !pcm.isEmpty, sourceRate > 0 else { return [] }

        let step = sourceRate / kOutputSampleRate
        if step == 1.0 { return pcm.map { Float($0) / 32768.0 * gain } }

        let outputCount = Int(Double(pcm.count) / step)
        guard outputCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputCount)
        let lastIndex = pcm.count - 1
        for i in 0..<outputCount {
            let position = Double(i) * step
            let index = Int(position)
            if index >= lastIndex {
                output[i] = Float(pcm[lastIndex]) / 32768.0 * gain
                continue
            }
            let fraction = Float(position - Double(index))
            let a = Float(pcm[index]) / 32768.0
            let b = Float(pcm[index + 1]) / 32768.0
            output[i] = (a + (b - a) * fraction) * gain
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
