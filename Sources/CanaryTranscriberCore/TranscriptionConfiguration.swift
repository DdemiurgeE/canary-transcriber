import Foundation

public extension BatchConfig {
    enum ValidationError: Error, Equatable, LocalizedError {
        case noInputFiles
        case emptyInputPath
        case invalidChunkDuration
        case nonFiniteChunkDuration
        case invalidOverlapDuration
        case nonFiniteOverlapDuration
        case invalidSpeakerCount
        case emptyProfileID
        case emptyRuntime
        case emptyModel
        case unsupportedRuntime
        case unsupportedProfileRuntime
        case outputCollision(String)

        public var errorDescription: String? {
            switch self {
            case .noInputFiles:
                return "At least one input file is required."
            case .emptyInputPath:
                return "Input file path cannot be empty."
            case .invalidChunkDuration:
                return "Chunk duration must be greater than zero."
            case .nonFiniteChunkDuration:
                return "Chunk duration must be a finite number."
            case .invalidOverlapDuration:
                return "Overlap duration must be non-negative and smaller than chunk duration."
            case .nonFiniteOverlapDuration:
                return "Overlap duration must be a finite number."
            case .invalidSpeakerCount:
                return "Speaker count must be greater than zero."
            case .emptyProfileID:
                return "Profile ID cannot be empty."
            case .emptyRuntime:
                return "Runtime cannot be empty."
            case .emptyModel:
                return "Model ID cannot be empty."
            case .unsupportedRuntime:
                return "Runtime is not supported."
            case .unsupportedProfileRuntime:
                return "The selected profile is not supported by the selected runtime."
            case .outputCollision(let path):
                return "Multiple input files would overwrite the same output: \(path). Rename the inputs or choose separate output folders."
            }
        }
    }

    func validated() throws -> BatchConfig {
        guard !files.isEmpty else { throw ValidationError.noInputFiles }
        guard files.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ValidationError.emptyInputPath
        }
        guard !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyProfileID
        }
        guard !runtime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyRuntime
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyModel
        }

        guard Self.supportedRuntimes.contains(runtime) else {
            throw ValidationError.unsupportedRuntime
        }
        guard Self.supportedProfileRuntimes[profileID]?.contains(runtime) == true else {
            throw ValidationError.unsupportedProfileRuntime
        }

        if let chunkDuration {
            guard chunkDuration.isFinite else { throw ValidationError.nonFiniteChunkDuration }
            guard chunkDuration > 0 else { throw ValidationError.invalidChunkDuration }
            guard overlapDuration.isFinite else { throw ValidationError.nonFiniteOverlapDuration }
            guard overlapDuration >= 0, overlapDuration < chunkDuration else {
                throw ValidationError.invalidOverlapDuration
            }
        } else {
            guard overlapDuration.isFinite else { throw ValidationError.nonFiniteOverlapDuration }
            guard overlapDuration == 0 else { throw ValidationError.invalidOverlapDuration }
        }

        if let speakerCount {
            guard speakerCount > 0 else { throw ValidationError.invalidSpeakerCount }
        }

        try validateOutputDestinations()
        return self
    }

    private func validateOutputDestinations() throws {
        var destinations = Set<String>()
        for file in files {
            let paths = TranscriptionOutputPaths(
                sourceURL: URL(fileURLWithPath: (file as NSString).expandingTildeInPath),
                outputDirectory: outputDir.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) },
                writeNextToSource: writeNextToSource,
                markdownDirectory: markdownOutputDir.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            )
            for url in [paths.text, paths.json, paths.markdown] {
                // Conservative on case-sensitive volumes; safe on default macOS APFS.
                let key = url.resolvingSymlinksInPath().standardizedFileURL.path
                    .precomposedStringWithCanonicalMapping.lowercased()
                guard destinations.insert(key).inserted else {
                    throw ValidationError.outputCollision(url.path)
                }
            }
        }
    }

    private static let supportedRuntimes: Set<String> = [
        "canary_mlx",
        "gigaam",
        "mlx_audio_cli",
        "mlx_whisper"
    ]

    private static let supportedProfileRuntimes: [String: Set<String>] = [
        "fast-parakeet-v3": ["mlx_audio_cli"],
        "fast-whisper-turbo": ["mlx_whisper"],
        "accurate-whisper-large-v3": ["mlx_whisper"],
        "multilingual-canary-v2": ["mlx_audio_cli"],
        "russian-gigaam-v3": ["gigaam"],
        "realtime-voxtral-mini": ["mlx_audio_cli"]
    ]
}
