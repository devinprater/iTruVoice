import Foundation

/// The voices the app and the provider offer: the engine's twenty-two,
/// eleven per language (Frank joined English at 10 and Francisco Spanish at
/// 21 upstream 2026-10-01).
///
/// The names come from the engine data in registration order (voice 0 is
/// Peter, voice 11 is Pedro). The identifier is the voice name after the
/// bundle prefix; the provider matches on the trailing component because the
/// system re-prefixes the identifier with the extension's bundle ID. Names
/// never renumber, so a stored identifier keeps addressing the same voice
/// whatever the engine's indices do, and Spanish voices appear under es-ES
/// in VoiceOver's Spanish voices.
public enum VoiceCatalog {
    public static let identifierPrefix = "com.devin.itruvoice."

    public struct Voice: Sendable {
        public let index: Int
        public let name: String
        public var language: String { index < 11 ? "en-US" : "es-ES" }
    }

    public static let all: [Voice] = TruVoice.voiceNames.enumerated().map { i, name in
        Voice(index: i, name: name)
    }

    public static func identifier(for index: Int) -> String {
        guard all.indices.contains(index) else { return identifierPrefix + String(index) }
        return identifierPrefix + all[index].name
    }

    /// The voice index encoded in a (possibly system re-prefixed) identifier.
    ///
    /// Identifiers carry the voice NAME, not its number, so an upstream
    /// renumber (Frank joining English at 10 moved Spanish 10-19 to 11-20)
    /// never revoices anybody: Pedro stays Pedro whatever his index is.
    /// Numeric tails are the pre-22-voice format and translate once:
    /// 0-9 are unchanged English, 10-19 were Pedro through Isabel.
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
        guard all.indices.contains(translated) else { return nil }
        return translated
    }

    public static let sampleText = "Hello world. This is TruVoice speaking."
}
