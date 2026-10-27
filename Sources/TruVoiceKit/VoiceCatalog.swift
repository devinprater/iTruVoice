import Foundation

/// The voices the app and the provider offer: the engine's thirty-three --
/// eleven American English, eleven Spanish, eleven British English.
///
/// The engine numbers voices in one run across every language, and the
/// numbers are not positions here: English is 0 through 10, Spanish 11
/// through 21, Japanese 22 through 31 (compiled, not offered), British
/// English 32 through 42. The identifier is the voice name after the bundle
/// prefix; the provider matches on the trailing component because the system
/// re-prefixes the identifier with the extension's bundle ID. Names never
/// renumber, so a stored identifier keeps addressing the same voice whatever
/// the engine's indices do -- which is why the British voices arriving at 32
/// take nothing away from an English or Spanish choice already saved. British
/// voices appear under en-GB, so VoiceOver's English (United Kingdom) list
/// carries them.
public enum VoiceCatalog {
    public static let identifierPrefix = "com.devin.itruvoice."

    public struct Voice: Sendable {
        public let index: Int
        public let name: String
        public let language: String
    }

    public static let all: [Voice] = TruVoice.voices.map {
        Voice(index: $0.index, name: $0.name, language: $0.locale)
    }

    public static func voice(at index: Int) -> Voice? {
        all.first { $0.index == index }
    }

    public static func identifier(for index: Int) -> String {
        identifierPrefix + (voice(at: index)?.name ?? String(index))
    }

    /// The voice index encoded in a (possibly system re-prefixed) identifier.
    ///
    /// Identifiers carry the voice NAME, not its number, so an upstream
    /// renumber (Frank joining English at 10, British English arriving after
    /// Japanese) never revoices anybody: Nigel stays Nigel, Pedro stays Pedro.
    /// Numeric tails are the pre-22-voice format and translate once: 0-9 are
    /// unchanged English, 10-19 were Pedro through Isabel.
    public static func index(from identifier: String) -> Int? {
        guard let range = identifier.range(of: identifierPrefix, options: .backwards) else {
            return nil
        }
        let tail = String(identifier[range.upperBound...])
        if let voice = all.first(where: { $0.name == tail }) {
            return voice.index
        }
        guard let legacy = Int(tail) else { return nil }
        let translated: Int
        switch legacy {
        case 0...9: translated = legacy
        case 10...19: translated = legacy + 1
        default: return nil
        }
        return voice(at: translated)?.index
    }

    public static let sampleText = "Hello world. This is TruVoice speaking."

    /// Sample text in the voice's own language, for the app's audition field.
    public static func sampleText(for index: Int) -> String {
        if voice(at: index)?.language.hasPrefix("es") == true {
            return "Hola mundo. Esta es la voz TruVoice."
        }
        return sampleText
    }
}
