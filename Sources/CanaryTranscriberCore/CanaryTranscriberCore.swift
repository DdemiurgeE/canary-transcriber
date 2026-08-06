import Foundation

public let speakerAliasesStorageKey = "canary.speakerAliasesText"

public struct BatchConfig: Codable {
    public let files: [String]
    public let outputDir: String?
    public let markdownOutputDir: String?
    public let writeNextToSource: Bool
    public let profileID: String
    public let runtime: String
    public let model: String
    public let language: String
    public let timestamps: Bool
    public let chunkDuration: Double?
    public let overlapDuration: Double
    public let diarization: Bool
    public let speakerCount: Int?
    public let speakerAliases: [String: String]

    public init(
        files: [String],
        outputDir: String?,
        markdownOutputDir: String? = nil,
        writeNextToSource: Bool,
        profileID: String,
        runtime: String,
        model: String,
        language: String,
        timestamps: Bool,
        chunkDuration: Double?,
        overlapDuration: Double,
        diarization: Bool,
        speakerCount: Int?,
        speakerAliases: [String: String]
    ) {
        self.files = files
        self.outputDir = outputDir
        self.markdownOutputDir = markdownOutputDir
        self.writeNextToSource = writeNextToSource
        self.profileID = profileID
        self.runtime = runtime
        self.model = model
        self.language = language
        self.timestamps = timestamps
        self.chunkDuration = chunkDuration
        self.overlapDuration = overlapDuration
        self.diarization = diarization
        self.speakerCount = speakerCount
        self.speakerAliases = speakerAliases
    }
}

public func parseSpeakerAliasesText(_ text: String) -> [String: String] {
    var aliases: [String: String] = [:]
    for rawLine in text.split(whereSeparator: { $0.isNewline }) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        let separators = ["=", ":", "\t"]
        var key: String?
        var value: String?
        for separator in separators {
            if let range = line.range(of: separator) {
                key = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        guard let key, let value, !key.isEmpty, !value.isEmpty else { continue }
        aliases[key] = value
    }
    return aliases
}
