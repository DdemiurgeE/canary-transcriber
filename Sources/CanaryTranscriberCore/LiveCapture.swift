import Foundation

public struct LiveCaptureConfig: Codable, Equatable, Sendable {
    public let windowDuration: TimeInterval
    public let overlapDuration: TimeInterval
    public let profileID: String
    public let runtime: String
    public let model: String
    public let language: String
    public let includeMicrophone: Bool
    public let outputDirectory: String

    public init(
        windowDuration: TimeInterval = 5,
        overlapDuration: TimeInterval = 0,
        profileID: String,
        runtime: String,
        model: String,
        language: String,
        includeMicrophone: Bool,
        outputDirectory: String
    ) {
        self.windowDuration = windowDuration
        self.overlapDuration = overlapDuration
        self.profileID = profileID
        self.runtime = runtime
        self.model = model
        self.language = language
        self.includeMicrophone = includeMicrophone
        self.outputDirectory = outputDirectory
    }

    public enum ValidationError: Error, Equatable, LocalizedError {
        case invalidWindowDuration
        case invalidOverlapDuration
        case emptyProfile
        case unsupportedRuntime(String)
        case emptyModel
        case emptyOutputDirectory

        public var errorDescription: String? {
            switch self {
            case .invalidWindowDuration: return "Live capture window duration must be finite and positive."
            case .invalidOverlapDuration: return "Live capture overlap must be finite, non-negative, and smaller than the window."
            case .emptyProfile: return "Live capture profile is empty."
            case .unsupportedRuntime(let runtime): return "Unsupported live capture runtime: \(runtime)"
            case .emptyModel: return "Live capture model is empty."
            case .emptyOutputDirectory: return "Live capture output directory is empty."
            }
        }
    }

    public func validated() throws -> LiveCaptureConfig {
        guard windowDuration.isFinite, windowDuration > 0 else { throw ValidationError.invalidWindowDuration }
        guard overlapDuration.isFinite, overlapDuration >= 0, overlapDuration < windowDuration else {
            throw ValidationError.invalidOverlapDuration
        }
        guard !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.emptyProfile }
        guard ["canary_mlx", "mlx_audio_cli", "mlx_whisper"].contains(runtime) else {
            throw ValidationError.unsupportedRuntime(runtime)
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.emptyModel }
        guard !outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyOutputDirectory
        }
        return self
    }
}

public struct LiveCaptureWindow: Equatable, Sendable {
    public let index: Int
    public let start: TimeInterval
    public let end: TimeInterval

    public init(index: Int, start: TimeInterval, end: TimeInterval) {
        self.index = index
        self.start = start
        self.end = end
    }
}

public enum LiveCaptureWindowPlanner {
    public static func plan(
        duration: TimeInterval,
        windowDuration: TimeInterval,
        overlap: TimeInterval = 0
    ) -> [LiveCaptureWindow] {
        guard duration > 0, windowDuration > 0, overlap >= 0, overlap < windowDuration else { return [] }

        let step = windowDuration - overlap
        var windows: [LiveCaptureWindow] = []
        var start: TimeInterval = 0
        var index = 0
        while start < duration {
            let end = min(start + windowDuration, duration)
            windows.append(LiveCaptureWindow(index: index, start: start, end: end))
            index += 1
            if end >= duration { break }
            start += step
        }
        return windows
    }
}

public struct LiveTranscriptSegment: Equatable, Sendable {
    public let index: Int
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(index: Int, start: TimeInterval, end: TimeInterval, text: String) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct LiveTranscriptAccumulator: Sendable {
    public private(set) var segments: [LiveTranscriptSegment] = []

    public init() {}

    @discardableResult
    public mutating func append(_ segment: LiveTranscriptSegment) -> Bool {
        let cleaned = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, segment.end > segment.start else { return false }

        let normalized = cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if segments.contains(where: {
            $0.index == segment.index ||
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == normalized &&
            abs($0.start - segment.start) < 0.01 && abs($0.end - segment.end) < 0.01
        }) {
            return false
        }

        segments.append(LiveTranscriptSegment(index: segment.index, start: segment.start, end: segment.end, text: cleaned))
        segments.sort { $0.start == $1.start ? $0.index < $1.index : $0.start < $1.start }
        return true
    }

    public var text: String {
        segments.map(\ .text).joined(separator: "\n")
    }

    public func renderTimestamped() -> String {
        segments.map { "[\(Self.timestamp($0.start))–\(Self.timestamp($0.end))] \($0.text)" }.joined(separator: "\n")
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
