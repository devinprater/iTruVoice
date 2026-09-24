import CTruVoice
import Foundation

/// The TruVoice engine, as a Swift object.
///
/// The C library is synchronous and callback-driven: `tvtts_speak_utf8`
/// blocks until the utterance finishes, delivering 16-bit mono samples
/// through the callback. This class accumulates them into one array, which
/// is what both the app's audition path and the provider extension need.
public final class TruVoice {
    /// The engine's native rate. `tvtts_create` takes 11025 or 8000.
    public static let sampleRate: UInt32 = 11025

    /// The ten voices, in engine order. Voice 0 is Peter, the voice the
    /// phoneme tables were written for; the rest are parametric deviations.
    public static let voiceNames = [
        "Peter", "Sidney", "Eager Eddie", "Deep Douglas", "Biff",
        "Grandpa Amos", "Melvin", "Alex", "Wanda", "Julia",
    ]

    private var synth: OpaquePointer?

    public init?(voice: Int) {
        guard let s = tvtts_create(TruVoice.sampleRate) else { return nil }
        synth = s
        tvtts_set_voice(s, Int32(voice))
    }

    deinit {
        if let s = synth { tvtts_destroy(s) }
    }

    /// Speech rate in words per minute. The engine takes 46 to 400.
    public func setRate(wpm: Int) {
        guard let s = synth else { return }
        tvtts_set_rate(s, Int32(wpm))
    }

    /// Synthesizes `text` (UTF-8) into 16-bit mono samples at `sampleRate`.
    /// Returns nil for empty text, text with an embedded NUL, or engine error.
    public func synthesize(_ text: String) -> [Int16]? {
        guard let s = synth, !text.isEmpty else { return nil }
        return text.withCString { cString -> [Int16]? in
            guard strlen(cString) == text.utf8.count else { return nil }
            let acc = Accumulator()
            let user = Unmanaged.passUnretained(acc).toOpaque()
            let rc = tvtts_speak_utf8(s, cString, bridgeCallback, user)
            guard rc >= 0, !acc.samples.isEmpty else { return nil }
            return acc.samples
        }
    }

    /// True when the engine produces non-silent audio for `text`.
    public func producesSpeech(for text: String) -> Bool {
        guard let samples = synthesize(text), !samples.isEmpty else { return false }
        return samples.contains { $0 != 0 }
    }
}

/// Box for the samples the C callback appends to.
private final class Accumulator {
    var samples: [Int16] = []
}

/// The C callback. Returns 0 to keep going; the engine calls it with audio,
/// mark and end events in stream order, and only audio appends.
private func bridgeCallback(
    _ event: UnsafePointer<tvtts_event>?,
    _ user: UnsafeMutableRawPointer?
) -> Int32 {
    guard let event, let user else { return 0 }
    let ev = event.pointee
    guard ev.type == TVTTS_AUDIO, ev.count > 0, let src = ev.samples else { return 0 }
    let acc = Unmanaged<Accumulator>.fromOpaque(user).takeUnretainedValue()
    acc.samples.append(contentsOf: UnsafeBufferPointer(start: src, count: Int(ev.count)))
    return 0
}
