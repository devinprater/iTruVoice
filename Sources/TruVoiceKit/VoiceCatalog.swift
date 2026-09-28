import Foundation

/// The voices the app and the provider offer: the engine's twenty, ten
/// per language.
///
/// The names come from the engine data in registration order (voice 0 is
/// Peter, voice 10 is Pedro). The identifier is the index after the bundle
/// prefix; the provider matches on the trailing component because the system
/// re-prefixes the identifier with the extension's bundle ID. Indices stay
/// plain integers 0-19, so existing English identifiers are unchanged and
/// Spanish voices appear under es-ES in VoiceOver's Spanish voices.
public enum VoiceCatalog {
    public static let identifierPrefix = "com.devin.itruvoice."

    public struct Voice: Sendable {
        public let index: Int
        public let name: String
        public var language: String { index < 10 ? "en-US" : "es-ES" }
    }

    public static let all: [Voice] = TruVoice.voiceNames.enumerated().map { i, name in
        Voice(index: i, name: name)
    }

    public static func identifier(for index: Int) -> String {
        identifierPrefix + String(index)
    }

    /// The voice index encoded in a (possibly system re-prefixed) identifier.
    public static func index(from identifier: String) -> Int? {
        guard let range = identifier.range(of: identifierPrefix, options: .backwards) else {
            return nil
        }
        let tail = String(identifier[range.upperBound...])
        guard let index = Int(tail), all.indices.contains(index) else { return nil }
        return index
    }

    public static let sampleText = "Hello world. This is TruVoice speaking."
}
