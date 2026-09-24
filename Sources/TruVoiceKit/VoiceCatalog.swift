import Foundation

/// The voices the app and the provider offer: the engine's ten, all en-US.
///
/// The names come from the engine data in registration order (voice 0 is
/// Peter). The identifier is the index after the bundle prefix; the provider
/// matches on the trailing component because the system re-prefixes the
/// identifier with the extension's bundle ID.
public enum VoiceCatalog {
    public static let identifierPrefix = "com.devin.itruvoice."

    public struct Voice: Sendable {
        public let index: Int
        public let name: String
        public let language = "en-US"
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
