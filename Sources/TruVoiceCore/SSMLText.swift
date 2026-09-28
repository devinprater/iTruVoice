import Foundation

/// Turns the SSML a speech provider is handed into the pieces the TruVoice
/// engine can actually render.
///
/// The system sends SSML, not text — Apple's own headers cite the reference
/// at https://www.w3.org/TR/speech-synthesis11/. Everything the engine cannot
/// act on has to be resolved here, and every way of getting it wrong is
/// **silent**: nothing errors, the voice still speaks, it just says the wrong
/// thing or nothing at all.
///
/// Two failures this exists to prevent, both observed while building the
/// sibling Keynote engine port:
///
/// - Deleting a tag rather than replacing it with a space joins the words it
///   sat between. `Voice<break time="100ms"/>recently` becomes
///   "Voicerecently", one nonsense word. A tag must become whitespace.
/// - The engine's `~` lead-in character obeys text commands: a literal tilde
///   in the text can change the voice's rate for the rest of the utterance
///   instead of being read. It becomes a space.
///
/// What this deliberately does NOT carry over from that port: the comma,
/// number, version and clock-time surgery. Every one of those was measured
/// against TruVoice first, and none is needed -- "Reddit, Yesterday, Version
/// 2026.38.0" speaks in full, "555 1234" speaks, "5:19 PM" reads as a time.
/// Rewriting them would only risk what already works.
///
/// Dots and "@" are the exception, and for a different reason than over
/// there: nothing goes silent here, but the structure goes unheard. The
/// engine drops dots with no sound of their own ("claude.ai" reads "claude
/// aye"), so "prater.devin@aidb.org" arrives as "prater devin at aidb org".
/// Letter dots become the word "dot" and "@" becomes "at" (see
/// `expandDotsAndAt`); digit dots, abbreviation chains and "://" hosts
/// already read correctly and are left alone. Acronyms the engine would
/// read as one word ("aidb" as `A1DB`, "ai" as "aye") are uppercased for
/// the front end's all-caps spell-out (see `expandAcronyms`); per-word
/// mispronunciations that need exact phonemes ("repo" as "REH-po") live in
/// the engine's user lexicon instead (see `TruVoice.ensurePronunciationFixes`).
///
/// What TruVoice does need is the fold: it reads a
/// single-byte code page, so curly quotes, emoji-adjacent punctuation and
/// accented letters come out as glyphs ("It's" as "Beta s", "café" as "Cash
/// for copier"), and bidi marks corrupt the word they touch. Those are
/// folded to ASCII before the engine ever sees them.
///
/// A single-language engine: TruVoice has one English voice family, so there
/// is no language detection and no build switching. Text in another language
/// is spoken with English rules, the way the 1997 engine always did.
public enum SSMLText {

    // MARK: - Result

    /// One thing to render, in order.
    public enum Piece: Equatable {
        /// Text, with the speech parameters in force over it. `pitch`, `rate`
        /// and `volume` are on VoiceOver's 0-100 scales; nil means the voice's
        /// normal setting.
        case speech(text: String, pitch: Int?, rate: Int?, volume: Int?)
        /// A pause the markup asked for.
        case pause(seconds: Double)
        /// A `mark` the markup placed, to be reported back as a marker.
        case bookmark(name: String)
    }

    public struct Parsed: Equatable {
        public var pieces: [Piece]

        /// All spoken text joined with single spaces.
        public var text: String {
            pieces.compactMap {
                if case .speech(let text, _, _, _) = $0 { return text }
                return nil
            }.joined(separator: " ")
        }

        /// VoiceOver-scale pitch from the first spoken piece.
        public var firstPitch: Int? {
            pieces.compactMap {
                if case .speech(_, let pitch, _, _) = $0 { return pitch }
                return nil
            }.first
        }

        /// VoiceOver-scale rate from the first spoken piece.
        public var firstRate: Int? {
            pieces.compactMap {
                if case .speech(_, _, let rate, _) = $0 { return rate }
                return nil
            }.first
        }

        /// Total silence the markup asked for, in seconds.
        public var totalPause: Double {
            pieces.reduce(0) {
                if case .pause(let seconds) = $1 { return $0 + seconds }
                return $0
            }
        }

        /// `mark` names in the order they appear.
        public var bookmarks: [String] {
            pieces.compactMap {
                if case .bookmark(let name) = $0 { return name }
                return nil
            }
        }
    }

    // MARK: - Parsing

    /// Walks the markup, tracking the parameters in force where it stands.
    ///
    /// A stack rather than a flat scan because elements nest: `prosody`
    /// inside `voice` inside `speak` all apply at once, and the innermost
    /// wins.
    public static func parse(_ ssml: String) -> Parsed {
        struct Context {
            var pitch: Int?
            var rate: Int?
            var volume: Int?
            var sayAs: String?
        }

        // `<sub>` is resolved over the whole document before the walk, because
        // the walk consumes tags: once `<sub alias="...">` has been seen, the
        // alias is gone and the enclosed text would be spoken as the
        // abbreviation instead.
        let document = resolveSubstitutions(ssml)

        var pieces: [Piece] = []
        var context = Context()
        var stack: [Context] = []
        var buffer = ""

        func flush() {
            let raw = buffer
            buffer = ""
            let text = finish(raw, sayAs: context.sayAs)
            guard !text.isEmpty else { return }
            pieces.append(.speech(text: text,
                                  pitch: context.pitch,
                                  rate: context.rate,
                                  volume: context.volume))
        }

        var index = document.startIndex
        while index < document.endIndex {
            guard let tagStart = document[index...].firstIndex(of: "<") else {
                buffer += document[index...]
                break
            }
            buffer += document[index..<tagStart]

            // Comments are removed before anything else: one containing ">"
            // would otherwise end a tag match early and leave fragments as
            // text.
            if document[tagStart...].hasPrefix("<!--") {
                guard let end = document.range(of: "-->", range: tagStart..<document.endIndex) else {
                    break   // unterminated comment: drop the remainder
                }
                index = end.upperBound
                continue
            }

            guard let tagEnd = document[tagStart...].firstIndex(of: ">") else {
                break   // unterminated tag: drop the remainder
            }
            let tag = String(document[document.index(after: tagStart)..<tagEnd])
            index = document.index(after: tagEnd)

            let isClosing = tag.hasPrefix("/")
            let body = isClosing ? String(tag.dropFirst()) : tag
            let name = body.prefix { !$0.isWhitespace && $0 != "/" }.lowercased()

            switch name {
            case "speak", "p", "s", "w", "voice", "emphasis", "lang", "desc":
                // Structure and emphasis carry nothing the engine can act on,
                // but each is still a word boundary.
                if isClosing {
                    flush()
                    context = stack.popLast() ?? context
                } else {
                    flush()
                    stack.append(context)
                }

            case "prosody":
                if isClosing {
                    flush()
                    context = stack.popLast() ?? context
                } else {
                    flush()
                    stack.append(context)
                    if let value = attribute("pitch", in: body), let pitch = pitchValue(from: value) {
                        context.pitch = pitch
                    }
                    if let value = attribute("rate", in: body), let rate = rateValue(from: value) {
                        context.rate = rate
                    }
                    if let value = attribute("volume", in: body), let volume = volumeValue(from: value) {
                        context.volume = volume
                    }
                    // `contour` describes a pitch curve over time. An engine
                    // with one pitch setting per utterance cannot follow it,
                    // so the baseline is used and the curve ignored.
                }

            case "say-as":
                if isClosing {
                    flush()
                    context = stack.popLast() ?? context
                } else {
                    flush()
                    stack.append(context)
                    context.sayAs = attribute("interpret-as", in: body)?.lowercased()
                }

            case "sub":
                if isClosing {
                    flush()
                    context = stack.popLast() ?? context
                } else {
                    // Resolved as a whole before the walk, so the alias
                    // replaces the enclosed text rather than being spoken as
                    // itself.
                    flush()
                    stack.append(context)
                }

            case "phoneme":
                // The enclosed text is spoken with its ordinary
                // pronunciation. `alphabet` and `ph` are ignored rather than
                // approximated: SSML phonemes arrive in an alphabet the
                // engine does not speak (usually IPA), while the engine's
                // own alphabet is one character per phoneme ("hello" is
                // "HeLO1") -- mapping one to the other by hand is a wrong
                // pronunciation waiting to happen, which is worse than the
                // normal one. Per-word phonetic fixes live in the engine's
                // user lexicon instead (see TruVoice.ensurePronunciationFixes,
                // via `tvtts_add_lexicon`), where they are engine phonemes
                // measured against the engine, not transcriptions.
                if isClosing { flush() }

            case "lexicon", "lookup", "meta", "metadata":
                // Pronunciation dictionaries and document metadata. Nothing
                // here is for speaking.
                break

            case "break":
                flush()
                pieces.append(.pause(seconds: breakSeconds(body)))

            case "mark":
                flush()
                if let name = attribute("name", in: body) {
                    pieces.append(.bookmark(name: name))
                }

            case "audio":
                // An audio file the system would play itself. The engine
                // cannot load it; the element's text content is the fallback,
                // and is what ends up spoken.
                if isClosing { flush() }

            default:
                // Unknown element: treated as a boundary, so its text is
                // still spoken — the best available guess.
                if isClosing {
                    flush()
                    context = stack.popLast() ?? context
                } else {
                    flush()
                    stack.append(context)
                }
            }
        }

        flush()
        return Parsed(pieces: pieces)
    }

    // MARK: - Element values

    /// Seconds for a `break`, from `time` if given and `strength` otherwise.
    public static func breakSeconds(_ body: String) -> Double {
        if let time = attribute("time", in: body), let seconds = seconds(from: time) {
            // Capped: a malformed value should not stall the speech queue.
            return min(max(seconds, 0), 10)
        }
        switch attribute("strength", in: body)?.lowercased() {
        case "none":     return 0
        case "x-weak":   return 0.05
        case "weak":     return 0.1
        case "medium":   return 0.25
        case "strong":   return 0.5
        case "x-strong": return 1.0
        default:         return 0.25   // the SSML default is a medium break
        }
    }

    /// "1s", "500ms", "1.5s", or a bare number, which SSML reads as
    /// milliseconds.
    public static func seconds(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("ms") { return Double(trimmed.dropLast(2)).map { $0 / 1000.0 } }
        if trimmed.hasSuffix("s")  { return Double(trimmed.dropLast()) }
        return Double(trimmed).map { $0 / 1000.0 }
    }

    /// A `prosody` pitch onto VoiceOver's 0-100 scale, where 50 is neutral.
    public static func pitchValue(from text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "x-low":   return 15
        case "low":     return 25
        case "medium":  return 50
        case "high":    return 75
        case "x-high":  return 90
        default: break
        }
        // A percentage is relative to the voice's own pitch, so it shifts
        // from neutral. Values in hertz are absolute and cannot be mapped
        // without knowing the voice's range, so they are ignored rather than
        // guessed at.
        if value.hasSuffix("%"), let percent = Double(value.dropLast()) {
            return clamp(Int((50.0 + percent).rounded()))
        }
        if let mark = value.range(of: "st") {
            return Double(value[..<mark.lowerBound])
                .map { clamp(Int((50.0 + $0 * 6.0).rounded())) }
        }
        return nil
    }

    /// A `prosody` rate onto VoiceOver's 0-100 scale, where 50 is neutral.
    public static func rateValue(from text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "x-slow":  return 10
        case "slow":    return 25
        case "medium":  return 50
        case "fast":    return 75
        case "x-fast":  return 90
        default: break
        }
        // 100% is the voice's normal rate, so it sits at neutral and the
        // adjustment spreads either side. Halved because VoiceOver's own range
        // is much narrower than SSML's: 200% must stay inside the engine's
        // usable band rather than running to its extreme.
        if value.hasSuffix("%"), let percent = Double(value.dropLast()) {
            return clamp(Int((50.0 + (percent - 100.0) * 0.5).rounded()))
        }
        return nil
    }

    /// A `prosody` volume onto VoiceOver's 0-100 scale.
    public static func volumeValue(from text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "silent", "none": return 0
        case "x-soft":         return 20
        case "soft":           return 40
        case "medium":         return 60
        case "loud":           return 80
        case "x-loud":         return 100
        default: break
        }
        if value.hasSuffix("%"), let percent = Double(value.dropLast()) {
            return clamp(Int(percent.rounded()))
        }
        // Decibels are relative to full scale; +6 dB is about double.
        if value.hasSuffix("db"), let decibels = Double(value.dropLast(2)) {
            return clamp(Int((pow(10.0, decibels / 20.0) * 60.0).rounded()))
        }
        if let fraction = Double(value), fraction <= 1.0 {
            return clamp(Int((fraction * 100).rounded()))
        }
        return nil
    }

    private static func clamp(_ value: Int) -> Int { min(max(value, 0), 100) }

    /// Reads an attribute out of a tag body, decoding entities in its value.
    public static func attribute(_ name: String, in body: String) -> String? {
        let quoted = "\(name)\\s*=\\s*\"([^\"]*)\""
        let bare = "\(name)\\s*=\\s*'([^']*)'"
        for pattern in [quoted, bare] {
            guard let match = body.range(of: pattern,
                                         options: [.regularExpression, .caseInsensitive])
            else { continue }
            let raw = body[match]
            guard let first = raw.firstIndex(where: { $0 == "\"" || $0 == "'" }),
                  let last = raw.lastIndex(where: { $0 == "\"" || $0 == "'" }),
                  first < last
            else { continue }
            return decodeEntities(String(raw[raw.index(after: first)..<last]))
        }
        return nil
    }

    // MARK: - Text preparation

    /// Turns accumulated raw text into what the engine should be given.
    public static func finish(_ raw: String, sayAs: String?) -> String {
        var text = decodeEntities(raw)
        // Invisibles before the fold: the fold would keep them (they have no
        // ASCII form) and the engine would read the corruption.
        text = removeInvisibleCharacters(text)
        // The engine's own lead-in character, before anything else can move
        // it next to a word: text can switch the parser into command mode for
        // the rest of the utterance instead of being read.
        text = text.replacingOccurrences(of: "~", with: " ")
        text = foldForEngine(text)
        text = collapseWhitespace(text)
        text = closeGapsBeforePunctuation(text)
        text = applySayAs(text, mode: sayAs)
        // After `say-as`, so a word it spelled out is never rewritten: its
        // spaces would not match a whole word anyway, and its lowercase
        // letters must keep their names.
        text = expandAcronyms(text)
        // After acronyms, so an uppercased domain label ("AIDB.org") still
        // gets its dot said.
        text = expandDotsAndAt(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Folds characters the engine cannot read into what it can.
    ///
    /// The engine reads a single-byte code page, so anything outside ASCII
    /// comes out as a glyph: measured, a curly-quoted "test" reads as "Beta
    /// s a tester", "café" as "Cash for copier", and a degree sign as the
    /// letter A. Three groups are handled, in this order:
    ///
    /// - **Invisible formatting characters** are already gone (see above).
    /// - **Typographic punctuation** has an ASCII form but no diacritic to
    ///   decompose, so it is named explicitly: curly quotes, dashes, the
    ///   ellipsis.
    /// - **Anything else outside ASCII** is decomposed and its diacritics
    ///   dropped: "café" is handed over as "cafe". "cafe au lait" is no
    ///   French lesson, but it is words rather than glyphs.
    ///
    /// Two symbols get words rather than folds: "84°" reads the degree sign
    /// as "A", and "€5" as "A five", so they become "degree" and "euro"
    /// ("84 degree", "5 euro" both verified). The engine skips emoji on its
    /// own ("Hello 😀 world" reads "Hello world"), so no description tables
    /// are needed.
    public static func foldForEngine(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        for character in text {
            if let replacement = typographicReplacements[character] {
                output += replacement
                continue
            }
            if let word = wordReplacements[character] {
                output += " \(word) "
                continue
            }
            if character.isASCII {
                output.append(character)
                continue
            }
            let folded = String(character)
                .folding(options: .diacriticInsensitive, locale: nil)
            if folded == String(character) {
                // Nothing to fold: a character with no ASCII form. The engine
                // skips what it cannot read (emoji vanish rather than
                // corrupting), so it is passed through unchanged.
                output.append(character)
            } else {
                output += folded.filter { $0.isASCII }
            }
        }
        return output
    }

    /// Typographic characters with an ASCII equivalent the engine can read.
    /// The folded forms are verified: "well-known" reads correctly with a
    /// bare hyphen, and "..." reads as a pause ("Wait... what" as
    /// "Wait what").
    private static let typographicReplacements: [Character: String] = [
        "\u{2018}": "'",  "\u{2019}": "'",   // single quotation marks
        "\u{201A}": ",",  "\u{201B}": "'",   // single low quote, reversed
        "\u{201C}": "\"", "\u{201D}": "\"",  // double quotation marks
        "\u{201E}": "\"", "\u{201F}": "\"",  // double low quote, reversed
        "\u{2013}": "-",  "\u{2014}": "-",   // en dash, em dash
        "\u{2015}": "-",                     // horizontal bar
        "\u{2026}": "...",                   // ellipsis
        "\u{2032}": "'",  "\u{2033}": "\"",  // prime, double prime
    ]

    /// Symbols that need words, not folds.
    private static let wordReplacements: [Character: String] = [
        "\u{00B0}": "degree",   // "84°" reads the sign as "A"
        "\u{20AC}": "euro",     // "€5" reads it as "A" too
    ]

    /// Characters that carry no sound but corrupt the reading, so they are
    /// removed. Measured: a left-to-right mark turns "Read hello" into
    /// "Re- hello". Bidi marks and isolates, zero width spaces, the soft
    /// hyphen, the word joiner and the byte order mark.
    public static func removeInvisibleCharacters(_ text: String) -> String {
        text.filter { !invisibleCharacters.contains($0) }
    }

    private static let invisibleCharacters: Set<Character> = [
        "\u{00AD}",                                     // soft hyphen
        "\u{200B}", "\u{200C}", "\u{200D}",             // zero width space, non-joiner, joiner
        "\u{200E}", "\u{200F}",                         // left-to-right / right-to-left mark
        "\u{202A}", "\u{202B}", "\u{202C}",             // bidi embedding and pop
        "\u{202D}", "\u{202E}",                         // bidi overrides
        "\u{2060}",                                     // word joiner
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", // bidi isolates
        "\u{FEFF}",                                     // byte order mark
    ]

    /// `say-as` handling.
    ///
    /// Two modes change the text. `characters` wants a word spelled out
    /// letter by letter, and `digits` wants each digit named: the engine
    /// already reads space-separated letters as their names (measured "H E L
    /// L O" as letter names), so separating them is what does it.
    ///
    /// The rest are left alone. The engine normalizes numbers, currency and
    /// times itself — "$1,234.56", "3.5 percent", "5:19 PM" and "2026.38.0"
    /// all read correctly — so passing them through is not a gap. Only
    /// spelling a word out cannot be inferred from the text.
    public static func applySayAs(_ text: String, mode: String?) -> String {
        switch mode {
        case "characters", "character", "char", "digits":
            return text
                .filter { !$0.isWhitespace }
                .map(String.init)
                .joined(separator: " ")
        default:
            return text
        }
    }

    /// Says acronyms the engine would read as one word.
    ///
    /// The front end spells an ALL-CAPS run letter by letter -- measured,
    /// "AIDB" reads `A1&I1&DE1&BE1` and "AI" reads `A1&I1` -- while the
    /// lowercase forms read as words ("aidb" is `A1DB`, "ai" is `A1`,
    /// "aye"). Uppercasing the word therefore hands the engine a reading it
    /// already gets right, with no phoneme strings to carry. Whole-word and
    /// case-insensitive, longest first, so "AIDBS" settles before "AIDB" and
    /// neither fires inside a longer word ("said", "air" and "aid" are
    /// untouched).
    ///
    /// A lexicon entry cannot do this instead: the caps reading's `&`
    /// separators speak different audio through the lexicon (garbage nodes),
    /// and without them the letters blend into one word. Both measured; see
    /// `TruVoice.lexiconEntries`.
    public static func expandAcronyms(_ text: String) -> String {
        var result = text
        for (term, replacement) in acronyms {
            guard result.range(of: term, options: .caseInsensitive) != nil else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [],
                                                    range: range, withTemplate: replacement)
        }
        return result
    }

    /// Words read as letters, longest first.
    private static let acronyms: [(term: String, replacement: String)] = [
        ("aidbs", "AIDBS"),
        ("aidb", "AIDB"),
        ("ai", "AI"),
    ]

    /// Says email addresses and domains the way they are written.
    ///
    /// The engine drops dots silently -- measured, "claude.ai" reads
    /// "claude aye" (`KLw1T&A1`), the dot with no sound of its own -- so an
    /// address arrives with its structure half missing:
    /// "prater.devin@aidb.org" is heard as "prater devin at aidb org".
    /// Dots between letters become the word "dot" and "@" becomes "at", so
    /// the address is heard complete.
    ///
    /// Untouched, because the engine already reads them: digit dots
    /// ("Version 2026.38.0", "3.5"), abbreviation chains ("e.g.", "U.S.",
    /// spotted by the single-letter run meeting another dot), and "://"
    /// URL hosts ("http://x.com" reads its colon and slashes). Everything
    /// else says "dot" wherever it sits -- unlike the sibling engine there
    /// is no silence to cure, only unheard structure, so a mid-piece dot
    /// ("visit google.com today") and a trailing period ("Visit
    /// example.com.") both want the word.
    public static func expandDotsAndAt(_ text: String) -> String {
        // "@" first: it is never a word character, and spelling it out keeps
        // the dot pass to dots alone.
        let atMarked = text.replacingOccurrences(of: "@", with: " at ")
        let characters = Array(atMarked)
        var output = ""
        output.reserveCapacity(atMarked.count + 8)
        for (index, character) in characters.enumerated() {
            guard character == ".",
                  index > 0, index + 1 < characters.count,
                  characters[index - 1].isLetter,
                  characters[index + 1].isLetter
            else { output.append(character); continue }
            // An abbreviation chain ("e.g.", "U.S.", "Ph.D."): a
            // single-letter run meeting another dot. Longer runs meeting a
            // dot ("example.com.") still want theirs heard.
            var next = index + 1
            while next < characters.count, characters[next].isLetter { next += 1 }
            if next - (index + 1) == 1, next < characters.count,
               characters[next] == "." {
                output.append(character); continue
            }
            // A URL host ("http://x.com") reads its punctuation already, so
            // a dot inside a "://" run is left alone. Only the scheme form
            // counts: a path ("files/report.txt") still needs its dot.
            var token = index - 1
            while token >= 0, characters[token].isLetter || characters[token].isNumber
                || "./:@-_".contains(characters[token]) {
                token -= 1
            }
            if String(characters[(token + 1)..<index]).contains("://") {
                output.append(character); continue
            }
            output.append(" dot ")
        }
        return collapseWhitespace(output)
    }

    /// Resolves `<sub alias="...">` to its alias.
    public static func resolveSubstitutions(_ text: String) -> String {
        replacing(text, pattern: #"<sub\s+alias\s*=\s*["']([^"']*)["'][^>]*>[^<]*</sub>"#) { $0[1] }
    }

    public static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    public static func closeGapsBeforePunctuation(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
    }

    // MARK: - Entities

    /// Named entities worth handling.
    private static let namedEntities: [(String, String)] = [
        ("&nbsp;", " "),
        ("&ensp;", " "),
        ("&emsp;", " "),
        ("&thinsp;", " "),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&ldquo;", "\""), ("&rdquo;", "\""),
        ("&lsquo;", "'"), ("&rsquo;", "'"),
        ("&mdash;", "-"), ("&ndash;", "-"),
        ("&hellip;", "..."),
        // Decoded last: doing it earlier would let "&amp;lt;" become "<".
        ("&amp;", "&"),
    ]

    public static func decodeEntities(_ input: String) -> String {
        var text = input

        text = replacing(text, pattern: "&#[xX]([0-9A-Fa-f]+);") { groups in
            UInt32(groups[1], radix: 16).flatMap { Unicode.Scalar($0) }.map(String.init)
        }
        text = replacing(text, pattern: "&#([0-9]+);") { groups in
            UInt32(groups[1]).flatMap { Unicode.Scalar($0) }.map(String.init)
        }

        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
    }

    /// Replaces every match of `pattern` using `transform`, which receives
    /// the capture groups (index 0 is the whole match).
    ///
    /// Written because `replacingOccurrences(of:with:options:)` can only
    /// insert a fixed template, and these replacements need to reinterpret
    /// the match.
    private static func replacing(_ input: String,
                                  pattern: String,
                                  transform: ([String]) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators])
        else { return input }

        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        guard !matches.isEmpty else { return input }

        var output = ""
        var cursor = input.startIndex
        for match in matches {
            guard let range = Range(match.range, in: input) else { continue }
            output += input[cursor..<range.lowerBound]

            var groups: [String] = []
            for index in 0..<match.numberOfRanges {
                if let groupRange = Range(match.range(at: index), in: input) {
                    groups.append(String(input[groupRange]))
                } else {
                    groups.append("")
                }
            }
            output += transform(groups) ?? String(input[range])
            cursor = range.upperBound
        }
        output += input[cursor...]
        return output
    }

    // MARK: - Convenience

    /// The words to speak, with markup resolved.
    public static func plainText(from ssml: String) -> String {
        parse(ssml).text
    }

    /// VoiceOver-scale pitch and rate from the first spoken piece.
    public static func speechParameters(from ssml: String) -> (pitch: Int?, rate: Int?) {
        let parsed = parse(ssml)
        return (parsed.firstPitch, parsed.firstRate)
    }

    /// The words to speak together with the pitch and rate that came with
    /// them.
    public static func textAndParameters(from ssml: String) -> (text: String, pitch: Int?, rate: Int?) {
        let parsed = parse(ssml)
        return (parsed.text, parsed.firstPitch, parsed.firstRate)
    }
}
