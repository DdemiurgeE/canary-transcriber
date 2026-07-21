import XCTest
import CanaryTranscriberCore

final class ChunkPlanningTests: XCTestCase {
    func testPlansOverlappingFinalPartialChunk() throws {
        let chunks = try ChunkPlanning.makeChunks(duration: 65, chunkDuration: 30, overlapDuration: 2)

        XCTAssertEqual(chunks, [
            AudioChunk(index: 0, start: 0, end: 30),
            AudioChunk(index: 1, start: 28, end: 58),
            AudioChunk(index: 2, start: 56, end: 65)
        ])
    }

    func testNilChunkDurationUsesOneFullChunk() throws {
        XCTAssertEqual(
            try ChunkPlanning.makeChunks(duration: 12.5, chunkDuration: nil),
            [AudioChunk(index: 0, start: 0, end: 12.5)]
        )
    }

    func testInvalidPlanningInputsFail() {
        XCTAssertThrowsError(try ChunkPlanning.makeChunks(duration: 10, chunkDuration: 0))
        XCTAssertThrowsError(try ChunkPlanning.makeChunks(duration: 10, chunkDuration: 10, overlapDuration: 10))
        XCTAssertThrowsError(try ChunkPlanning.makeChunks(duration: .infinity, chunkDuration: 10))
    }

    func testMemoryFailureRetriesWithHalfChunkButNotBelowMinimum() {
        XCTAssertEqual(
            ChunkPlanning.retryAfterMemoryFailure(chunkDuration: 30),
            .retry(smallerChunkDuration: 15)
        )
        XCTAssertEqual(
            ChunkPlanning.retryAfterMemoryFailure(chunkDuration: 5),
            .fail
        )
    }
}
