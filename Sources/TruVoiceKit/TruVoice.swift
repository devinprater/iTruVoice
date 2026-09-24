import CTruVoice
import Foundation

/// The TruVoice engine, as a Swift object.
///
/// The C library is synchronous and callback-driven: `tvtts_speak_utf8`
/// blocks until the utterance finishes, delivering 16-bit mono samples and
/// index marks through the callback in stream order. This class accumulates
/// both into one result, which is what the app's audition path and the
/// provider extension need.
///
/// A `tvtts_synth` is not thread safe. One `TruVoice` speaks on one thread;
/// the provider keeps one per voice and only ever touches it from the request
/// thread, while the audio thread reads nothing but the finished samples.
public final class TruVoice {
    /// The engine's native rate. `tvtts_create` takes 11025 or 8000.
    public static let sampleRate: UInt32 = 11025

    /// The ten voices, in engine order. Voice 0 is Peter, the voice the
    /// phoneme tables were written for; the rest are parametric deviations.
    public static let voiceNames = [
        "Peter", "Sidney", "Eager Eddie", "Deep Douglas", "Biff",
        "Grandpa Amos", "Melvin", "Alex", "Wanda", "Julia",
    ]

    /// One finished utterance: mono samples at `sampleRate`, plus the index
    /// marks the engine passed, each with the engine-sample position where
    /// synthesis reached it.
    public struct Utterance {
        public var samples: [Int16]
        public var marks: [(id: UInt32, samplePosition: UInt32)]
    }

    private var synth: OpaquePointer?
    private let voiceIndex: Int

    public init?(voice: Int) {
        guard let s = tvtts_create(TruVoice.sampleRate) else { return nil }
        synth = s
        voiceIndex = voice
        tvtts_set_voice(s, Int32(voice))
    }

    deinit {
        if let s = synth { tvtts_destroy(s) }
    }

    /// The voice's own default rate in words per minute.
    public var defaultRateWPM: Int { Int(tvtts_voice_rate(Int32(voiceIndex))) }

    /// The voice's own default absolute pitch.
    public var defaultPitch: Int { Int(tvtts_voice_pitch(Int32(voiceIndex))) }

    /// Speech rate in words per minute. The engine takes 46 to 400 and floors
    /// anything lower; that floor is load-bearing, because below 46 the rate
    /// table index wraps and reads wildly.
    public func setRate(wpm: Int) {
        guard let s = synth else { return }
        tvtts_set_rate(s, Int32(wpm))
    }

    /// Absolute pitch. The engine holds 50 to 500.
    public func setPitch(_ pitch: Int) {
        guard let s = synth else { return }
        tvtts_set_pitch(s, Int32(pitch))
    }

    /// The inline escape that raises an index mark, to be placed in the text
    /// *before* the word it belongs to. A mark after the last word changes
    /// how the engine reads that word (a lone "a" becomes the article rather
    /// than the letter's name), so trailing marks are never embedded — the
    /// caller reports them once the audio exists.
    public static func markEscape(id: UInt32) -> String? {
        var buffer = [CChar](repeating: 0, count: 32)
        let needed = tvtts_mark_sequence(&buffer, buffer.count, id)
        guard needed > 0, needed < buffer.count else { return nil }
        return String(cString: buffer)
    }

    /// Synthesizes `text` (UTF-8) at the current settings. Returns nil for
    /// empty text, text with an embedded NUL, or engine error.
    public func synthesize(_ text: String) -> Utterance? {
        guard let s = synth, !text.isEmpty else { return nil }
        return text.withCString { cString -> Utterance? in
            guard strlen(cString) == text.utf8.count else { return nil }
            let acc = Accumulator()
            let user = Unmanaged.passUnretained(acc).toOpaque()
            let rc = tvtts_speak_utf8(s, cString, bridgeCallback, user)
            guard rc >= 0, !acc.samples.isEmpty else { return nil }
            return Utterance(samples: acc.samples, marks: acc.marks)
        }
    }

    /// True when the engine produces non-silent audio for `text`.
    public func producesSpeech(for text: String) -> Bool {
        guard let uttered = synthesize(text), !uttered.samples.isEmpty else { return false }
        return uttered.samples.contains { $0 != 0 }
    }
}

/// Box for what the C callback accumulates.
private final class Accumulator {
    var samples: [Int16] = []
    var marks: [(id: UInt32, samplePosition: UInt32)] = []
}

/// The C callback. Returns 0 to keep going; audio appends, marks are
/// remembered with their positions, anything else is ignored.
private func bridgeCallback(
    _ event: UnsafePointer<tvtts_event>?,
    _ user: UnsafeMutableRawPointer?
) -> Int32 {
    guard let event, let user else { return 0 }
    let ev = event.pointee
    let acc = Unmanaged<Accumulator>.fromOpaque(user).takeUnretainedValue()
    // The event type is a 32-bit C enum; the enumerators import as Int.
    switch Int(ev.type) {
    case TVTTS_AUDIO:
        guard ev.count > 0, let src = ev.samples else { return 0 }
        acc.samples.append(contentsOf: UnsafeBufferPointer(start: src, count: Int(ev.count)))
    case TVTTS_MARK:
        acc.marks.append((id: ev.mark, samplePosition: ev.sample_pos))
    default:
        break
    }
    return 0
}
