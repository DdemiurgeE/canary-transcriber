import Foundation

/// Single owner for the local speaker-alias preference format.
/// The UI may bind this value through @AppStorage using `storageKey`.
public enum SpeakerAliasPersistence {
    public static let storageKey = speakerAliasesStorageKey

    public static func sanitize(_ aliases: [String: String]) -> [String: String] {
        aliases.reduce(into: [:]) { result, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            result[key] = value
        }
    }

    public static func encode(_ aliases: [String: String]) -> String {
        sanitize(aliases)
            .sorted { $0.key < $1.key }
            .map { "\($0.key) = \($0.value)" }
            .joined(separator: "\n")
    }

    public static func decode(_ text: String) -> [String: String] {
        sanitize(parseSpeakerAliasesText(text))
    }
}
