import Foundation

public extension BatchConfig {
    enum ValidationError: Error, Equatable, LocalizedError {
        case noInputFiles
        case emptyInputPath
        case invalidChunkDuration
        case invalidOverlapDuration
        case invalidSpeakerCount
        case emptyProfileID
        case emptyRuntime
        case emptyModel

        public var errorDescription: String? {
            switch self {
            case .noInputFiles:
                return "At least one input file is required."
            case .emptyInputPath:
                return "Input file path cannot be empty."
            case .invalidChunkDuration:
                return "Chunk duration must be greater than zero."
            case .invalidOverlapDuration:
                return "Overlap duration must be non-negative and smaller than chunk duration."
            case .invalidSpeakerCount:
                return "Speaker count must be greater than zero."
            case .emptyProfileID:
                return "Profile ID cannot be empty."
            case .emptyRuntime:
                return "Runtime cannot be empty."
            case .emptyModel:
                return "Model ID cannot be empty."
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

        if let chunkDuration {
            guard chunkDuration > 0 else { throw ValidationError.invalidChunkDuration }
            guard overlapDuration >= 0, overlapDuration < chunkDuration else {
                throw ValidationError.invalidOverlapDuration
            }
        } else if overlapDuration != 0 {
            throw ValidationError.invalidOverlapDuration
        }

        if let speakerCount {
            guard speakerCount > 0 else { throw ValidationError.invalidSpeakerCount }
        }

        return self
    }
}
