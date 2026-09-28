import Testing

@testable import TruVoiceCore

// MARK: - SSML parsing

@Suite("SSML parsing")
struct SSMLParsingTests {

    @Test("Plain text is one speech piece with no parameters")
    func plainText() {
        let parsed = SSMLText.parse("Hello world")
        #expect(parsed.pieces == [.speech(text: "Hello world", pitch: nil, rate: nil, volume: nil)])
    }

    @Test("Tags are boundaries, not glue")
    func tagBoundaries() {
        let parsed = SSMLText.parse(#"Voice<break time="100ms"/>recently"#)
        #expect(parsed.pieces.count == 3)
        #expect(parsed.text == "Voice recently")
    }

    @Test("Prosody sets rate, pitch and volume on its span only")
    func prosody() {
        let parsed = SSMLText.parse(
            #"<speak>Normal <prosody rate="fast" pitch="high" volume="loud">excited</prosody> again</speak>"#)
        #expect(parsed.pieces == [
            .speech(text: "Normal", pitch: nil, rate: nil, volume: nil),
            .speech(text: "excited", pitch: 75, rate: 75, volume: 80),
            .speech(text: "again", pitch: nil, rate: nil, volume: nil),
        ])
    }

    @Test("Prosody percentages land on the 0-100 scale around neutral")
    func prosodyPercentages() {
        let parsed = SSMLText.parse(#"<prosody rate="200%" pitch="+10%">words</prosody>"#)
        // 200% rate spreads half past neutral; +10% pitch shifts from neutral.
        #expect(parsed.pieces == [.speech(text: "words", pitch: 60, rate: 100, volume: nil)])
    }

    @Test("Break time and strengths become pauses")
    func breaks() {
        #expect(SSMLText.parse(#"<break time="500ms"/>"#).pieces == [.pause(seconds: 0.5)])
        #expect(SSMLText.parse(#"<break strength="strong"/>"#).pieces == [.pause(seconds: 0.5)])
        #expect(SSMLText.parse("<break/>").pieces == [.pause(seconds: 0.25)])
    }

    @Test("Marks become bookmarks in order")
    func marks() {
        let parsed = SSMLText.parse(#"One<mark name="a"/> two<mark name="b"/> three"#)
        #expect(parsed.bookmarks == ["a", "b"])
        #expect(parsed.text == "One two three")
    }

    @Test("Sub aliases replace their content")
    func sub() {
        let parsed = SSMLText.parse(#"<sub alias="World Health Organization">WHO</sub> met"#)
        #expect(parsed.text == "World Health Organization met")
    }

    @Test("Say-as characters are spelled out")
    func sayAsCharacters() {
        let parsed = SSMLText.parse(#"<say-as interpret-as="characters">HELLO</say-as>"#)
        #expect(parsed.text == "H E L L O")
    }

    @Test("Comments never leak into the text")
    func comments() {
        let parsed = SSMLText.parse("Hello <!-- a > tricky --> world")
        #expect(parsed.text == "Hello world")
    }

    @Test("Entities decode, with &amp; last")
    func entities() {
        let parsed = SSMLText.parse("Fish &amp; chips &lt;3 &amp;lt;")
        #expect(parsed.text == "Fish & chips <3 &lt;")
    }

    @Test("Unknown elements still speak their text")
    func unknownElements() {
        let parsed = SSMLText.parse("<foo>bar</foo>")
        #expect(parsed.text == "bar")
    }
}

// MARK: - Text preparation

@Suite("Text preparation")
struct TextPreparationTests {

    @Test("Invisible characters are removed")
    func invisibles() {
        let lrm = String(Unicode.Scalar(0x200E)!)
        let zwsp = String(Unicode.Scalar(0x200B)!)
        #expect(SSMLText.finish("Read" + lrm + "hello" + zwsp + " now", sayAs: nil)
                == "Read hello now")
    }

    @Test("The engine lead-in becomes a space, not a command")
    func tilde() {
        #expect(SSMLText.finish("Read ~p] now", sayAs: nil) == "Read p] now")
    }

    @Test("Curly quotes and dashes fold to ASCII")
    func typographic() {
        #expect(SSMLText.finish("It’" + "s", sayAs: nil) == "It's")
        #expect(SSMLText.finish("a — b", sayAs: nil) == "a - b")
        #expect(SSMLText.finish("Wait… what", sayAs: nil) == "Wait... what")
    }

    @Test("Accents fold, and the degree and euro get words")
    func foldsAndWords() {
        #expect(SSMLText.finish("café", sayAs: nil) == "cafe")
        #expect(SSMLText.finish("84°", sayAs: nil) == "84 degree")
        #expect(SSMLText.finish("€5", sayAs: nil) == "euro 5")
    }

    @Test("Emoji passes through; the engine skips what it cannot read")
    func emoji() {
        #expect(SSMLText.finish("Hello 😀 world", sayAs: nil) == "Hello 😀 world")
    }

    @Test("Commas, numbers and times are left alone; dots say dot")
    func engineReadsItself() {
        #expect(SSMLText.finish("Reddit, Yesterday", sayAs: nil) == "Reddit, Yesterday")
        #expect(SSMLText.finish("Version 2026.38.0", sayAs: nil) == "Version 2026.38.0")
        #expect(SSMLText.finish("5:19 PM", sayAs: nil) == "5:19 PM")
        #expect(SSMLText.finish("Call 555 1234", sayAs: nil) == "Call 555 1234")
        // The engine drops dots with no sound of their own ("claude.ai"
        // reads "claude aye"), so letter dots become the word -- while
        // digit dots, abbreviations and URL hosts already read correctly.
        #expect(SSMLText.finish("claude.ai", sayAs: nil) == "claude dot aigh igh")
        #expect(SSMLText.finish("visit google.com today", sayAs: nil) == "visit google dot com today")
        #expect(SSMLText.finish("Visit example.com.", sayAs: nil) == "Visit example dot com.")
        #expect(SSMLText.finish("e.g.", sayAs: nil) == "e.g.")
        #expect(SSMLText.finish("U.S.", sayAs: nil) == "U.S.")
        #expect(SSMLText.finish("http://x.com", sayAs: nil) == "http://x.com")
        #expect(SSMLText.finish("https://mail.example.com", sayAs: nil) == "https://mail.example.com")
        #expect(SSMLText.finish("files/report.txt", sayAs: nil) == "files/report dot txt")
    }

    @Test("Addresses are heard complete, acronyms as letters")
    func addresses() {
        #expect(SSMLText.finish("prater.devin@aidb.org 107 Unread Messages", sayAs: nil)
                == "prater dot devin at AIDB dot org 107 Unread Messages")
        #expect(SSMLText.finish("devin@aidb.org", sayAs: nil) == "devin at AIDB dot org")
        #expect(SSMLText.finish("write to bob@example.com today", sayAs: nil)
                == "write to bob at example dot com today")
        // The front end spells all-caps runs; lowercase would read as words.
        #expect(SSMLText.finish("aidb", sayAs: nil) == "AIDB")
        #expect(SSMLText.finish("said the aid to air", sayAs: nil) == "said the aid to air")
        // "repo" keeps its spelling here: its fix is exact phonemes in the
        // engine's user lexicon, measured against the engine.
        #expect(SSMLText.finish("about the repo", sayAs: nil) == "about the repo")
    }

    @Test("Dictionary respellings replace the engine's guesses")
    func dictionary() {
        // Abbreviations, brands, units and numerals from the IBM TTS
        // dictionary (community profile): the replacement is the
        // dictionary's own prescription, verified to speak on the engine.
        #expect(SSMLText.finish("Fwiw", sayAs: nil) == "for what it's worth")
        #expect(SSMLText.finish("fwiw", sayAs: nil) == "for what it's worth")
        #expect(SSMLText.finish("Airbnb", sayAs: nil) == "Air bea en bea")
        #expect(SSMLText.finish("my Mbps plan", sayAs: nil) == "my megabits per second plan")
        #expect(SSMLText.finish("set a tabindex", sayAs: nil) == "set a Tab Index")
        #expect(SSMLText.finish("omg", sayAs: nil) == "oe em jee")
        #expect(SSMLText.finish("Ai", sayAs: nil) == "ay igh")
        #expect(SSMLText.finish("ai", sayAs: nil) == "aigh igh")
        #expect(SSMLText.finish("the Sen voted", sayAs: nil) == "the senator voted")
        #expect(SSMLText.finish("VIII's", sayAs: nil) == "eight's")
        // The dictionary is explicit about casing: an all-caps form keeps
        // the front end's letter-by-letter reading, and a lexicon word keeps
        // its spelling here (its fix is engine phonemes, not text).
        #expect(SSMLText.finish("FWIW", sayAs: nil) == "FWIW")
        #expect(SSMLText.finish("SUV", sayAs: nil) == "SUV")
        #expect(SSMLText.finish("Govt", sayAs: nil) == "Govt")
        #expect(SSMLText.finish("open the Statusbar", sayAs: nil) == "open the Status Bar")
        // Glued camelCase the LTS reads as one mangled word: "SideStore"
        // traces SIDSDg1RE ("side-storee", the story rime), "TruVoice"
        // CsRb1VyS; split, both speak clean.
        #expect(SSMLText.finish("open SideStore", sayAs: nil) == "open Side Store")
        #expect(SSMLText.finish("Meet TruVoice", sayAs: nil) == "Meet True Voice")
    }
}

// MARK: - Voice parameters

@Suite("Voice parameters")
struct VoiceParametersTests {

    @Test("Neutral is the voice's own default")
    func neutral() {
        #expect(VoiceParameters.rate(forVoiceOver: 50, defaultWPM: 150) == 150)
        #expect(VoiceParameters.pitch(forVoiceOver: 50, defaultPitch: 85) == 85)
    }

    @Test("Endpoints land on the engine's usable band")
    func endpoints() {
        #expect(VoiceParameters.rate(forVoiceOver: 0, defaultWPM: 150) == 46)
        #expect(VoiceParameters.rate(forVoiceOver: 100, defaultWPM: 150) == 195)
        #expect(VoiceParameters.pitch(forVoiceOver: 0, defaultPitch: 85) == 50)
        #expect(VoiceParameters.pitch(forVoiceOver: 100, defaultPitch: 85) == 400)
    }

    @Test("Fraction and percentage inputs agree")
    func scales() {
        #expect(VoiceParameters.rate(forVoiceOver: 0.0, defaultWPM: 150) == 46)
        #expect(VoiceParameters.rate(forVoiceOver: 1.0, defaultWPM: 150) == 195)
        #expect(VoiceParameters.pitch(forVoiceOver: 0.0, defaultPitch: 85) == 50)
    }

    @Test("Out-of-range values saturate")
    func clamping() {
        #expect(VoiceParameters.rate(forVoiceOver: 200, defaultWPM: 150) == 195)
        #expect(VoiceParameters.pitch(forVoiceOver: -10, defaultPitch: 85) == 50)
    }

    @Test("Volume is a gain, with nil untouched")
    func gain() {
        #expect(VoiceParameters.gain(forVoiceOver: nil) == 1.0)
        #expect(VoiceParameters.gain(forVoiceOver: 60) == 0.6)
        #expect(VoiceParameters.gain(forVoiceOver: 0) == 0.0)
    }
}
