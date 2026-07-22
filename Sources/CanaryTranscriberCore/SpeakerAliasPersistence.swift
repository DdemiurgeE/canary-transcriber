import Foundation

/// Single owner for the local speaker-alias preference format and storage.
/// The UI owns only the editable text; all UserDefaults access stays here.
public final class SpeakerAliasPersistence {
    public static let storageKey = speakerAliasesStorageKey

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadText() -> String {
        defaults.string(forKey: Self.storageKey) ?? ""
    }

    public func saveText(_ text: String) {
        defaults.set(text, forKey: Self.storageKey)
    }

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
