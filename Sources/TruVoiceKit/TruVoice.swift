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
    /// The engine rate everything runs at: 16000 Hz, OpenTV's own third rate
    /// (see TVTTS_SR_16K) -- genuinely more bandwidth than the 11025 Hz
    /// desktop default, not an upsample, with the same voices. Every consumer
    /// reads this constant (the provider's resample ratio and mark mapping,
    /// the app's converter format), so the whole pipeline follows it.
    /// Synths open at it directly: `tvtts_create_lang` takes 16000.
    public static let sampleRate: UInt32 = 16000

    /// The twenty-two voices in engine order: the eleven English (voice 0 is
    /// Peter, the voice the phoneme tables were written for; the rest are
    /// parametric deviations -- Frank, from the MindMaker TextAssist build,
    /// joined at index 10 upstream 2026-10-01) then the eleven Spanish, Pedro
    /// through Isabel plus Francisco at index 21. The names come from the
    /// engine in order, measured against the linked tree -- `tvtts_voice_name`
    /// 0 through 21 (headless probe, 16 kHz).
    public static let voiceNames = [
        "Peter", "Sidney", "Eager Eddie", "Deep Douglas", "Biff",
        "Grandpa Amos", "Melvin", "Alex", "Wanda", "Julia", "Frank",
        "Pedro", "Jorge", "Ricardo", "Paco", "Luis",
        "Ezequiel", "Rogelio", "Carlos", "Josefa", "Isabel", "Francisco",
    ]

    /// The language for a voice index: the engine carries one combined list,
    /// so the index picks both the parameter row and the engine -- 0-10 run
    /// the English engine, 11-21 the Spanish. (`tvtts_set_voice` would switch
    /// the synth's language by itself, but opening the right engine first
    /// avoids building a throwaway one.)
    public static func language(forVoice index: Int) -> String {
        index < 11 ? "en" : "es"
    }

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
        guard (0..<Self.voiceNames.count).contains(voice),
              let s = tvtts_create_lang(TruVoice.sampleRate, Self.language(forVoice: voice)) else { return nil }
        synth = s
        voiceIndex = voice
        tvtts_set_voice(s, Int32(voice))
        Self.ensurePronunciationFixes()
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

    /// Pins the words the engine gets wrong to measured phonemes, in the
    /// engine's own user lexicon.
    ///
    /// This is the phonetic fix rather than an ASCII rewrite: the lexicon
    /// takes the engine's own phoneme alphabet (one character per phoneme,
    /// "1"/"2" for stress), so the entry speaks with exact phonemes and no
    /// respelling for the text layer to carry.
    ///
    /// Entries are measured against the engine, not assumed:
    /// - "Devin" natives stress the second syllable ("dev-IN": `D|Vi1N`),
    ///   while Kevin is `Ke1V|N`. "De1V|N" is Kevin with a D -- one word,
    ///   first-syllable stress, and the possessive comes along ("Devin's"
    ///   reads `De1V|NZ`). The key is case-insensitive (the engine
    ///   uppercases it), so one entry covers Devin, devin and DEVIN.
    /// - "repo" natives the short e ("REH-po": `Re1PO`), while "reepo" reads
    ///   `RE1PO` ("REE-po") -- the doubled e forces the long vowel, the way
    ///   "keep" is `KE1P` against "rep"'s `Re1P`. Speaking "repo" with the
    ///   entry is byte-identical to speaking "reepo" without it (same
    ///   samples, same hash), and the possessive comes along ("repo's" reads
    ///   `RE1POZ`). "repos" gets the same treatment against "reepos"
    ///   (`RE1POS`, byte-identical both ways).
    ///
    /// What is deliberately NOT here: "Linux". Lowercase and title-case
    /// already read identically (`Li1NvKS`), so there is nothing to pin --
    /// and an entry built from the raw `text_to_phonemes` output (with its
    /// `&`/`.` sentence markers) inserts garbage nodes and lengthens the
    /// word. All-caps spell-out (LINUX, APPLE) happens in the front-end
    /// token classifier before the lexicon ever sees the word, so no entry
    /// can reach it; that is SAPI-era convention, not a mispronunciation.
    ///
    /// Also not here: "aidb". Lowercase it reads as one word (`A1DB`), while
    /// all-caps reads as letters (`A1&I1&DE1&BE1`) -- but a lexicon entry
    /// cannot reproduce that reading: with the `&` separators it speaks
    /// different audio than the caps form (garbage nodes, as above), and
    /// without them the letters blend into one word. Acronyms like this go
    /// through the text layer instead (see `SSMLText.expandAcronyms`), which
    /// uppercases the word and lets the front end spell it.
    private static let lexiconEntries: [(word: String, phonemes: String)] = [
        ("Devin", "De1V|N"),
        // The engine reads the compound as voice + "eover" (`Vy1SEYOV3`).
        // "Vy1S%O1V3" is exactly what two-word "voice over" says, verified
        // byte-identical (same samples, same hash) on every casing.
        ("VoiceOver", "Vy1S%O1V3"),
        // "repo" natives the short e; "RE1PO" is what "reepo" says,
        // byte-identical both ways (see above).
        ("repo", "RE1PO"),
        ("repos", "RE1POS"),
        // "dyson" natives "dih-sun" (`Di1S@N`); "Die son" splits the stress
        // ("DYE SUN", the star). "DI1S@N" keeps dye stressed and the second
        // syllable reduced -- trace shows it in-sentence, ASR hears Dyson.
        ("dyson", "DI1S@N"),
        // App and brand names as single stressed words: the text
        // respelling splits the stress ("DYE SUN", "pay PAL") or drops
        // sounds (Gmail's G, hub's H after t). Each value is the
        // prescription's own `text_to_phonemes` output, installed and
        // verified in-sentence; see the batch notes below.
        // "Gee mail" as one word (native drops the G entirely).
        ("gmail", "JzE1MA1j"),
        // "eye oh ess" as one word (native "I uh").
        ("ios", "I1O1e1S"),
        // "Wall mart" as one word (native "Walm ert").
        ("walmart", "Ww1jMr1Tp"),
        // "Pay Pal" as one word (native "paple").
        ("paypal", "PA1Pa1j"),
        // "Local Dev VPN" as one word (native "low call dvn").
        ("localdevvpn", "LO1K@jDe1FVE1PE1e1N"),
        // "You Nuh Fye" as one word (native "oo nee fee"; "Nigh Fye"
        // runs together as "knife").
        ("unifi", "%YbNv1FI1"),
        // "Scribe Me" as one word (native "scree beam").
        ("scribeme", "SKRI1B%ME"),
        // "ah met ah" as one word (native "mayda").
        ("ameta", "o1Me1to1"),
        // "You Tube" as one word (native "yow tib").
        ("youtube", "%YbTb1Bp"),
        // The name Ira ("eye-ruh"; native "air").
        ("aira", "I1R@"),
        // "lee-ray" in one token (native one syllable; "leeray"
        // re-syllabifies to "littery").
        ("lire", "LE1RA1"),
        // "Door Dash" as one word (native "door dish").
        ("doordash", "Dg1Da1s"),
        // "Pay tree on" as one word (native "pat ree in").
        ("patreon", "PA1CsRE1%oN"),
        // "Whats App" as one word (native "wats up").
        ("whatsapp", "Wv1TSa1Pp"),
        // "mee oh" as one word (native "mee uv").
        ("meow", "ME1O1"),
        // "Side Store" as one word (native "side-storee").
        ("sidestore", "SI1DSDg1"),
        // "Sync Train" as one word (unstressed "train" reduces to "trun").
        ("synctrain", "Si1~KCsRA1N"),
        // Dictionary respellings (IBM TTS dictionary, community profile)
        // whose single-word prescriptions verify byte-identical through the
        // lexicon: speaking the key with the entry is the same samples,
        // same hash as speaking the respelling without it. Each value is
        // the engine's own `text_to_phonemes` output for the respelling,
        // sentence markers stripped. Longer words go through the text layer
        // instead (`SSMLText.applyDictionary`): same phonemes through the
        // lexicon render slightly different audio than the natural word
        // (boundary context), while the text substitution speaks the
        // dictionary's audio exactly. Measured per entry; see
        // tools/dict_audit/README.md.
        ("govt", "Gv1V3M|NTp"),
        ("avg", "a1VR|Jz"),
        ("incl", "|~KLb1t|~p"),
        // "January" natives stress on "NY"; kept as the engine's own
        // reading (byte-identical to it), which still beats "jan".
        ("jan", "Jza1NYbkE"),
        ("inorg", "i2NgGa1N|Kp"),
        ("qty", "KWo1NT|tE"),
        ("esc", "|SGA1Pp"),
        ("oceanog", "o2SENo1GR|FE"),
        ("cnet", "SE1N|Tp"),
        ("xi", "sE1"),
        ("suu", "Sb1"),
        ("kyi", "CsE1"),
        ("uni", "Yb1NE"),
        ("jos", "Jzw1S"),
        ("vypr", "VI1P3"),
    ]

    /// Installs `lexiconEntries` once per process.
    ///
    /// `tvtts_add_lexicon` is process-global (the engine keeps one static
    /// user table), so one install covers every voice's synth in this
    /// process -- the app and the provider extension each install their own,
    /// as separate processes. That table is shared across languages too:
    /// the entries stand on Spanish synths, where the keys are English
    /// words read with English phonemes -- correct for those words, and
    /// Spanish words never match the keys.
    ///
    /// Guarded by `lexiconLock`; `nonisolated(unsafe)` silences Swift 6's
    /// shared-mutable-state error, which is exact here -- every access holds
    /// the lock.
    nonisolated(unsafe) private static var lexiconInstalled = false
    private static let lexiconLock = NSLock()

    private static func ensurePronunciationFixes() {
        lexiconLock.lock()
        defer { lexiconLock.unlock() }
        guard !lexiconInstalled else { return }
        lexiconInstalled = true
        // Hand entries first, then machine-verified stress fixes (disjoint
        // keys, checked at generation). Together they stay under the
        // engine's 5,000-entry user-lexicon cap.
        for entry in lexiconEntries + generatedLexiconEntries {
            entry.word.withCString { wordCString in
                entry.phonemes.withCString { phonemesCString in
                    _ = tvtts_add_lexicon(wordCString, phonemesCString)
                }
            }
        }
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
