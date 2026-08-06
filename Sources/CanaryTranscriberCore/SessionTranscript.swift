import Foundation

public struct SessionTranscriptSegment: Codable, Equatable {
    public let index: Int?
    public let start: Double
    public let end: Double
    public let speaker: String?
    public let chars: Int?
    public let text: String
}

public struct SessionTranscriptSpeakerSummary: Codable, Equatable {
    public let speaker: String
    public let segments: Int
    public let seconds: Double
    public let chars: Int
    public let alias: String
}

public struct SessionTranscript: Codable, Equatable {
    public let audio: String
    public let profile: String
    public let runtime: String
    public let model: String
    public let language: String
    public let diarization: Bool
    public let text: String
    public let chunks: [SessionTranscriptSegment]
    public let transcriptionSegments: [SessionTranscriptSegment]?
    public let speakerSummary: [SessionTranscriptSpeakerSummary]?
    public let speakerAliases: [String: String]?

    enum CodingKeys: String, CodingKey {
        case audio, profile, runtime, model, language, diarization, text, chunks
        case transcriptionSegments = "transcription_segments"
        case speakerSummary = "speaker_summary"
        case speakerAliases = "speaker_aliases"
    }

    /// Segments to render in a transcript view: speaker-attributed segments when diarization
    /// produced them, otherwise the plain chunk-by-chunk breakdown.
    public var displaySegments: [SessionTranscriptSegment] {
        if let transcriptionSegments, !transcriptionSegments.isEmpty {
            return transcriptionSegments
        }
        return chunks
    }

    public static func load(from url: URL) throws -> SessionTranscript {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SessionTranscript.self, from: data)
    }
}
