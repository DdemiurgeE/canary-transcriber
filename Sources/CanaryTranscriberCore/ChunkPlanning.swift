import Foundation

public struct AudioChunk: Equatable, Sendable {
    public let index: Int
    public let start: Double
    public let end: Double

    public init(index: Int, start: Double, end: Double) {
        self.index = index
        self.start = start
        self.end = end
    }
}

public enum ChunkPlanning {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case nonFiniteDuration
        case invalidDuration
        case nonFiniteChunkDuration
        case invalidChunkDuration
        case invalidOverlap

        public var errorDescription: String? {
            switch self {
            case .nonFiniteDuration: return "Audio duration must be finite."
            case .invalidDuration: return "Audio duration cannot be negative."
            case .nonFiniteChunkDuration: return "Chunk duration must be finite."
            case .invalidChunkDuration: return "Chunk duration must be greater than zero."
            case .invalidOverlap: return "Overlap must be non-negative and smaller than chunk duration."
            }
        }
    }

    public enum RetryDecision: Equatable, Sendable {
        case retry(smallerChunkDuration: Double)
        case fail
    }

    public static func makeChunks(
        duration: Double,
        chunkDuration: Double?,
        overlapDuration: Double = 0
    ) throws -> [AudioChunk] {
        guard duration.isFinite else { throw Error.nonFiniteDuration }
        guard duration >= 0 else { throw Error.invalidDuration }
        guard let chunkDuration else {
            return duration == 0 ? [] : [AudioChunk(index: 0, start: 0, end: duration)]
        }
        guard chunkDuration.isFinite else { throw Error.nonFiniteChunkDuration }
        guard chunkDuration > 0 else { throw Error.invalidChunkDuration }
        guard overlapDuration.isFinite, overlapDuration >= 0, overlapDuration < chunkDuration else {
            throw Error.invalidOverlap
        }
        guard duration > 0 else { return [] }

        var chunks: [AudioChunk] = []
        var start = 0.0
        var index = 0
        let step = chunkDuration - overlapDuration
        while start < duration {
            chunks.append(AudioChunk(index: index, start: start, end: min(start + chunkDuration, duration)))
            start += step
            index += 1
        }
        return chunks
    }

    public static func retryAfterMemoryFailure(
        chunkDuration: Double?,
        minimumChunkDuration: Double = 5
    ) -> RetryDecision {
        guard let chunkDuration, chunkDuration > minimumChunkDuration else { return .fail }
        return .retry(smallerChunkDuration: max(minimumChunkDuration, floor(chunkDuration / 2)))
    }
}
