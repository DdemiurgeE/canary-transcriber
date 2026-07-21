import Foundation

/// A speaker-labelled interval returned by a diarization provider.
public struct DiarizationSegment: Codable, Equatable, Sendable {
    public let speaker: String
    public let start: Double
    public let end: Double

    public init(speaker: String, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }

    public var duration: Double { end - start }
}

public enum DiarizationValidationIssue: Equatable, Error, CustomStringConvertible {
    case emptySpeaker(index: Int)
    case nonFiniteTime(index: Int)
    case negativeStart(index: Int)
    case endBeforeStart(index: Int)
    case unsorted(index: Int)

    public var description: String {
        switch self {
        case .emptySpeaker(let index): return "segment \(index) has an empty speaker label"
        case .nonFiniteTime(let index): return "segment \(index) has a non-finite time"
        case .negativeStart(let index): return "segment \(index) starts before zero"
        case .endBeforeStart(let index): return "segment \(index) ends before it starts"
        case .unsorted(let index): return "segment \(index) is out of chronological order"
        }
    }
}

public enum DiarizationFallbackReason: Equatable, Sendable {
    case disabled
    case missingToken
    case missingConsent
    case shortAudio
    case providerError(String)
}

/// Result of an optional diarization stage. `speakerless` is an intentional,
/// recoverable result and must never be treated as a failed transcription.
public enum DiarizationResult: Equatable, Sendable {
    case segments([DiarizationSegment])
    case speakerless(reason: DiarizationFallbackReason, warning: String)

    public var segments: [DiarizationSegment] {
        if case .segments(let value) = self { return value }
        return []
    }

    public var isFallback: Bool {
        if case .speakerless = self { return true }
        return false
    }
}

public protocol DiarizationAdapter: Sendable {
    func diarize(audioPath: URL) throws -> DiarizationResult
}

public enum DiarizationValidator {
    /// Validates provider output without imposing a no-overlap policy: pyannote
    /// can legitimately return overlapping speech. Consumers may choose to
    /// merge or split overlaps, but malformed timing is rejected here.
    public static func validate(_ segments: [DiarizationSegment]) -> Result<Void, DiarizationValidationIssue> {
        var previousStart = 0.0
        for (index, segment) in segments.enumerated() {
            guard !segment.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.emptySpeaker(index: index))
            }
            guard segment.start.isFinite, segment.end.isFinite else {
                return .failure(.nonFiniteTime(index: index))
            }
            guard segment.start >= 0 else { return .failure(.negativeStart(index: index)) }
            guard segment.end >= segment.start else { return .failure(.endBeforeStart(index: index)) }
            if index > 0, segment.start < previousStart {
                return .failure(.unsorted(index: index))
            }
            previousStart = segment.start
        }
        return .success(())
    }

    public static func validated(_ segments: [DiarizationSegment]) throws -> [DiarizationSegment] {
        switch validate(segments) {
        case .success: return segments
        case .failure(let issue): throw issue
        }
    }
}
