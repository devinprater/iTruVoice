import Foundation

/// Trimming the silence the engine wraps around every utterance.
///
/// The engine pads each synthesized utterance with pure digital silence:
/// measured on Peter at 150 wpm, about 120–180 ms at the head and 379 ms at
/// the tail, and the same fixed amounts at every rate (the padding is not
/// spoken, so it does not scale). Rendering one VoiceOver string as several
/// pieces therefore inserted roughly half a second of dead air at each
/// junction — heard as a long pause in "Accessibility, back button".
///
/// A single utterance's padding is harmless; it is only the junctions that
/// matter. So each piece keeps a short gap of its own (`joinGapSeconds`) and
/// the rest goes, which leaves a junction close to the engine's own
/// inter-word gap (90–180 ms measured).
public enum VoiceAudio {

    /// Below this a sample counts as silence. The padding is exactly zero and
    /// speech runs to hundreds, so the exact value is not delicate.
    private static let silenceThreshold: Int16 = 100

    /// Silence kept on each side of a piece, in seconds. Enough that speech
    /// does not start clipped, short enough not to be heard as a pause.
    public static let joinGapSeconds: Double = 0.040

    /// The range of `pcm` that holds speech, widened by `gap` samples of
    /// quiet on each side, plus how many leading samples that range dropped.
    ///
    /// Returns the whole buffer with a zero lead when nothing rises above the
    /// threshold: a piece of pure silence must stay silent rather than being
    /// trimmed to nothing.
    public static func voicedRange(_ pcm: [Int16],
                                   gap: Int) -> (range: Range<Int>, lead: Int) {
        guard !pcm.isEmpty else { return (0..<0, 0) }
        let margin = max(0, gap)

        var first = -1
        var last = -1
        for (i, sample) in pcm.enumerated() {
            if sample > silenceThreshold || sample < -silenceThreshold {
                if first < 0 { first = i }
                last = i
            }
        }
        guard first >= 0 else { return (0..<pcm.count, 0) }   // all quiet

        let start = max(0, first - margin)
        let end = min(pcm.count, last + 1 + margin)
        guard start < end else { return (0..<pcm.count, 0) }
        return (start..<end, start)
    }
}
