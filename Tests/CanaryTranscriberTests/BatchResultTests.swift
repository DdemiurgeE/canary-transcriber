import XCTest
import CanaryTranscriberCore

final class BatchResultTests: XCTestCase {
    func testSummaryPreservesSuccessfulFilesWhenOneFails() {
        let result = BatchResult(files: [
            BatchFileResult(path: "ok.wav", status: .succeeded),
            BatchFileResult(path: "bad.wav", status: .failed, message: "missing input")
        ])

        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.stoppedCount, 0)
        XCTAssertTrue(result.hasErrors)
        XCTAssertEqual(result.summary, "succeeded=1, failed=1, stopped=0, total=2")
    }

    func testStoppedBatchIsNotSuccessful() {
        let result = BatchResult(files: [
            BatchFileResult(path: "first.wav", status: .succeeded),
            BatchFileResult(path: "second.wav", status: .stopped)
        ], stopped: true)

        XCTAssertTrue(result.hasErrors)
        XCTAssertEqual(result.stoppedCount, 1)
    }
}
