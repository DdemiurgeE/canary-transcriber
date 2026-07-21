import Foundation

public struct TranscriptionOutputPaths: Equatable {
    public let text: URL
    public let json: URL
    public let markdown: URL

    public init(sourceURL: URL, outputDirectory: URL?, writeNextToSource: Bool) {
        let directory = writeNextToSource ? sourceURL.deletingLastPathComponent() : (outputDirectory ?? sourceURL.deletingLastPathComponent())
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let base = directory.appendingPathComponent("\(stem).canary")
        self.text = base.appendingPathExtension("txt")
        self.json = base.appendingPathExtension("json")
        self.markdown = base.appendingPathExtension("md")
    }
}

public struct TranscriptionFrontMatter: Equatable {
    public let source: String
    public let profile: String
    public let runtime: String
    public let model: String
    public let language: String
    public let date: String

    public init(source: String, profile: String, runtime: String, model: String, language: String, date: String) {
        self.source = source
        self.profile = profile
        self.runtime = runtime
        self.model = model
        self.language = language
        self.date = date
    }

    public func render() -> String {
        let fields = [
            ("source", source),
            ("profile", profile),
            ("runtime", runtime),
            ("model", model),
            ("language", language),
            ("date", date)
        ]
        let body = fields.map { key, value in "\(key): \(yamlScalar(value))" }.joined(separator: "\n")
        return "---\n\(body)\n---\n"
    }

    private func yamlScalar(_ value: String) -> String {
        let safeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:/"))
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
