import Foundation
import TruVoiceCore

/// The executable test harness: every check the SSML and parameter layers
/// carry, runnable on any host with `swift run CoreChecks`.
///
/// swift-testing would be nicer, but `swift test` builds the whole package —
/// including the C engine's assembly data image, which SwiftPM's Linux
/// driver cannot compile — while `swift run` builds only this executable and
/// its dependency-free TruVoiceCore. One runner, both hosts, no traps.
var failures = 0

@MainActor
func check(_ name: String, _ body: () -> Bool) {
    if body() {
        print("PASS \(name)")
    } else {
        failures += 1
        print("FAIL \(name)")
    }
}

func speech(_ text: String, pitch: Int? = nil, rate: Int? = nil,
            volume: Int? = nil) -> SSMLText.Piece {
    .speech(text: text, pitch: pitch, rate: rate, volume: volume)
}

// MARK: - SSML parsing

check("plain text is one speech piece") {
    SSMLText.parse("Hello world").pieces == [speech("Hello world")]
}

check("tags are boundaries, not glue") {
    let parsed = SSMLText.parse(#"Voice<break time="100ms"/>recently"#)
    return parsed.pieces.count == 3 && parsed.text == "Voice recently"
}

check("prosody applies to its span only") {
    let parsed = SSMLText.parse(
        #"<speak>Normal <prosody rate="fast" pitch="high" volume="loud">excited</prosody> again</speak>"#)
    return parsed.pieces == [
        speech("Normal"),
        speech("excited", pitch: 75, rate: 75, volume: 80),
        speech("again"),
    ]
}

check("prosody percentages center on neutral") {
    let parsed = SSMLText.parse(#"<prosody rate="200%" pitch="+10%">words</prosody>"#)
    return parsed.pieces == [speech("words", pitch: 60, rate: 100)]
}

check("break time and strengths become pauses") {
    SSMLText.parse(#"<break time="500ms"/>"#).pieces == [.pause(seconds: 0.5)]
        && SSMLText.parse(#"<break strength="strong"/>"#).pieces == [.pause(seconds: 0.5)]
        && SSMLText.parse("<break/>").pieces == [.pause(seconds: 0.25)]
}

check("marks become bookmarks in order") {
    let parsed = SSMLText.parse(#"One<mark name="a"/> two<mark name="b"/> three"#)
    return parsed.bookmarks == ["a", "b"] && parsed.text == "One two three"
}

check("sub aliases replace their content") {
    SSMLText.parse(#"<sub alias="World Health Organization">WHO</sub> met"#).text
        == "World Health Organization met"
}

check("say-as characters are spelled out") {
    SSMLText.parse(#"<say-as interpret-as="characters">HELLO</say-as>"#).text == "H E L L O"
}

check("comments never leak") {
    SSMLText.parse("Hello <!-- a > tricky --> world").text == "Hello world"
}

check("entities decode, &amp; last") {
    SSMLText.parse("Fish &amp; chips &lt;3 &amp;lt;").text == "Fish & chips <3 &lt;"
}

check("unknown elements still speak") {
    SSMLText.parse("<foo>bar</foo>").text == "bar"
}

// MARK: - Text preparation

check("invisibles are removed") {
    let lrm = String(Unicode.Scalar(0x200E)!)
    let zwsp = String(Unicode.Scalar(0x200B)!)
    return SSMLText.finish("Read " + lrm + "hello" + zwsp + " now", sayAs: nil) == "Read hello now"
}

check("the engine lead-in becomes a space") {
    SSMLText.finish("Read ~p] now", sayAs: nil) == "Read p] now"
}

check("curly quotes and dashes fold") {
    SSMLText.finish("It\u{2019}s", sayAs: nil) == "It's"
        && SSMLText.finish("a \u{2014} b", sayAs: nil) == "a - b"
        && SSMLText.finish("Wait\u{2026} what", sayAs: nil) == "Wait... what"
}

check("accents fold, degree and euro get words") {
    SSMLText.finish("caf\u{E9}", sayAs: nil) == "cafe"
        && SSMLText.finish("84\u{B0}", sayAs: nil) == "84 degree"
        && SSMLText.finish("\u{20AC}5", sayAs: nil) == "euro 5"
}

check("emoji passes through") {
    SSMLText.finish("Hello \u{1F600} world", sayAs: nil) == "Hello \u{1F600} world"
}

check("commas, dots, numbers and times are untouched") {
    SSMLText.finish("Reddit, Yesterday", sayAs: nil) == "Reddit, Yesterday"
        && SSMLText.finish("claude.ai", sayAs: nil) == "claude.ai"
        && SSMLText.finish("Version 2026.38.0", sayAs: nil) == "Version 2026.38.0"
        && SSMLText.finish("5:19 PM", sayAs: nil) == "5:19 PM"
        && SSMLText.finish("Call 555 1234", sayAs: nil) == "Call 555 1234"
}

// MARK: - The ellipsis, and the notification that found it

/// A real notification whose URL iOS truncated with `…`. Reported as "it stops
/// on the number six", because the last sound before the failure is the six of
/// `ssi26` and the ellipsis after it produced NOTHING.
///
/// Measured against the Keynote engine, which is the same class of machine:
/// `…` alone is zero samples, and it poisons everything after it, so a sentence
/// ending in one loses its whole tail. The three-dot form speaks everywhere.
check("a literal ellipsis is folded to three dots") {
    SSMLText.finish("accent-ssi26\u{2026}", sayAs: nil) == "accent-ssi26..."
        && SSMLText.finish("\u{2026}", sayAs: nil) == "..."
}

check("the notification with the truncated URL survives intact") {
    let notification =
        "MONA, 2 hours ago, Tamas G , Alright you peoples, it's here. " +
        "Accent Mini's voice, under NVDA. The real Accent voice more people " +
        "remember. eurpod.com/synths/accent-ssi26\u{2026}   button"
    let out = SSMLText.finish(notification, sayAs: nil)
    // Every word that matters must still be there, and no ellipsis may remain.
    return !out.contains("\u{2026}")
        && out.contains("accent-ssi26...")
        && out.contains("button")
        && out.contains("remember.")
        && out.contains("MONA")
}

check("the &hellip; entity is folded too") {
    SSMLText.finish("accent-ssi26&hellip; button", sayAs: nil)
        == "accent-ssi26... button"
}

// MARK: - Voice parameters

check("neutral is the voice default") {
    VoiceParameters.rate(forVoiceOver: 50, defaultWPM: 150) == 150
        && VoiceParameters.pitch(forVoiceOver: 50, defaultPitch: 85) == 85
}

check("endpoints land on the usable band") {
    VoiceParameters.rate(forVoiceOver: 0, defaultWPM: 150) == 46
        && VoiceParameters.rate(forVoiceOver: 100, defaultWPM: 150) == 195
        && VoiceParameters.pitch(forVoiceOver: 0, defaultPitch: 85) == 50
        && VoiceParameters.pitch(forVoiceOver: 100, defaultPitch: 85) == 400
}

check("fraction and percentage inputs agree") {
    VoiceParameters.rate(forVoiceOver: 0.0, defaultWPM: 150) == 46
        && VoiceParameters.rate(forVoiceOver: 1.0, defaultWPM: 150) == 195
        && VoiceParameters.pitch(forVoiceOver: 0.0, defaultPitch: 85) == 50
}

check("out-of-range saturates") {
    VoiceParameters.rate(forVoiceOver: 200, defaultWPM: 150) == 195
        && VoiceParameters.pitch(forVoiceOver: -10, defaultPitch: 85) == 50
}

check("volume is a gain, nil untouched") {
    VoiceParameters.gain(forVoiceOver: nil) == 1.0
        && VoiceParameters.gain(forVoiceOver: 60) == 0.6
        && VoiceParameters.gain(forVoiceOver: 0) == 0.0
}

// MARK: - Engine silence trim

check("the engine's lead and tail silence is trimmed") {
    // What the engine actually emits around "Accessibility": ~1320 samples
    // of zeros, speech, then ~4180 of zeros.
    var pcm = [Int16](repeating: 0, count: 1320)
    pcm += [Int16](repeating: 400, count: 100)
    pcm += [Int16](repeating: 0, count: 4180)
    let gap = Int(VoiceAudio.joinGapSeconds * 11025)
    let (range, lead) = VoiceAudio.voicedRange(pcm, gap: gap)
    // 40 ms of lead kept (441 samples), the rest dropped.
    return lead == 1320 - gap
        && range.count == gap + 100 + gap
        && range.upperBound < pcm.count
}

check("a quiet piece stays intact rather than vanishing") {
    let silence = [Int16](repeating: 0, count: 500)
    let (range, lead) = VoiceAudio.voicedRange(silence, gap: 100)
    return lead == 0 && range.count == 500
}

check("trim keeps the gap but never past the buffer") {
    // Speech right at both edges: nothing to trim, and no overrun.
    let pcm: [Int16] = [900, 0, 0, -900]
    let (range, lead) = VoiceAudio.voicedRange(pcm, gap: 400)
    return lead == 0 && range == 0..<4
}

print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECKS FAILED")
exit(failures == 0 ? 0 : 1)
