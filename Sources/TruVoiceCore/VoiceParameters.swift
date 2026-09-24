import Foundation

/// Translates the pitch and rate VoiceOver asks for into the numbers the
/// TruVoice engine takes.
///
/// The philosophy is the sibling port's: VoiceOver's neutral must land on the
/// voice's own defaults, so an untouched voice sounds untouched, and the full
/// VoiceOver travel must stay inside the engine's usable band.
///
/// ## Rate is words per minute
///
/// `tvtts_set_rate` takes 46 to 400 with the extensions on (the default), and
/// floors anything lower. Measured on Peter with a fixed sentence, the whole
/// band is usable and monotonic: 57420 samples at 46 wpm down to 10230 at
/// 400. VoiceOver's neutral 50 maps to the voice's own default
/// (`tvtts_voice_rate`: 150 for every voice but Grandpa Amos at 120), 0 maps
/// to the 46 floor, 100 to 400, in two straight segments meeting at neutral.
///
/// ## Pitch is absolute
///
/// `tvtts_set_pitch` takes 50 to 500 (`TVTTS_PITCH_MIN/MAX`). Measured on
/// Peter, the sentence transcribes cleanly at 50, 150 and 500 alike, so the
/// band is usable end to end — but the top is capped at 400, the furthest the
/// inline escape can reach and still clearly speech. VoiceOver's neutral 50
/// maps to the voice's own default (`tvtts_voice_pitch`: 85 for Peter, 50 to
/// 208 across the family), 0 to the 50 floor, 100 to 400, in two segments.
///
/// ## Volume is a gain, not a setting
///
/// Measured on the engine, `tvtts_set_volume` is a threshold, not a scale:
/// 0 through 75 are silent and 100 and up are full voice. A VoiceOver volume
/// cannot be expressed through it, so the engine is always left at full and
/// volume is applied as a sample gain during resampling instead. Volume 0
/// silences the piece outright.
public enum VoiceParameters {

    /// The slowest row of the engine's rate table.
    static let slowestWPM = 46
    /// The fastest the engine goes with the extensions on.
    static let fastestWPM = 400
    /// The lowest pitch the engine holds.
    static let lowestPitch = 50
    /// The highest pitch honored here; the engine reaches 500, the inline
    /// escape 400, and 400 is still clearly speech.
    static let highestPitch = 400

    /// Words per minute for a VoiceOver rate, given the voice's default.
    ///
    /// Two straight segments meeting at VoiceOver's neutral, so 0, 50 and
    /// 100 land exactly on the slowest row, the voice's default and the
    /// fastest setting.
    public static func rate(forVoiceOver rate: Double, defaultWPM: Int) -> Int {
        let fraction = normalise(rate)
        let wpm: Double
        if fraction <= 0.5 {
            wpm = Double(defaultWPM)
                - (0.5 - fraction) * 2.0 * Double(defaultWPM - slowestWPM)
        } else {
            wpm = Double(defaultWPM)
                + (fraction - 0.5) * 2.0 * Double(fastestWPM - defaultWPM)
        }
        return min(max(Int(wpm.rounded()), slowestWPM), fastestWPM)
    }

    /// Absolute pitch for a VoiceOver pitch, given the voice's default.
    ///
    /// Two segments meeting at VoiceOver's neutral for the same reason: the
    /// usable range is not centred on any one default (Peter's is 85,
    /// Sidney's 50, Alex's 203), so each half of VoiceOver's travel maps onto
    /// default-to-floor and default-to-ceiling. Neutral always lands on the
    /// voice's own default.
    public static func pitch(forVoiceOver pitch: Double, defaultPitch: Int) -> Int {
        let fraction = normalise(pitch)
        let value: Double
        if fraction <= 0.5 {
            value = Double(defaultPitch)
                - (0.5 - fraction) * 2.0 * Double(defaultPitch - lowestPitch)
        } else {
            value = Double(defaultPitch)
                + (fraction - 0.5) * 2.0 * Double(highestPitch - defaultPitch)
        }
        return min(max(Int(value.rounded()), lowestPitch), highestPitch)
    }

    /// Linear gain for a VoiceOver volume: 60 ("medium") is 0.6, 100 is full.
    /// nil means the markup named no volume, so the voice is untouched at 1.
    public static func gain(forVoiceOver volume: Int?) -> Float {
        guard let volume else { return 1.0 }
        return min(max(Float(volume) / 100.0, 0), 1)
    }

    /// VoiceOver states these values either as a fraction of the range (0-1)
    /// or as a percentage (0-100), depending on the property. Anything above
    /// 1.5 can only be the latter, so scale it down; clamped to 0-1, so an
    /// out-of-range value saturates rather than wrapping.
    static func normalise(_ value: Double) -> Double {
        let scaled = value > 1.5 ? value / 100.0 : value
        return min(max(scaled, 0), 1)
    }
}
