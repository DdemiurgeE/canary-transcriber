import XCTest
@testable import CanaryTranscriberCore

final class BatchResultAccumulatorTests: XCTestCase {
    func testMixedBatchPreservesSuccessAndFailureAndFinishesOnce() {
        let accumulator = BatchResultAccumulator()
        accumulator.start(paths: ["ok.wav", "bad.wav"])
        accumulator.recordSucceeded(path: "ok.wav")
        accumulator.recordFailed(path: "bad.wav", message: "decode failed")

        let result = accumulator.finish(stopped: false)

        XCTAssertEqual(result?.files, [
            BatchFileResult(path: "ok.wav", status: .succeeded),
            BatchFileResult(path: "bad.wav", status: .failed, message: "decode failed")
        ])
        XCTAssertEqual(result?.succeededCount, 1)
        XCTAssertEqual(result?.failedCount, 1)
        XCTAssertEqual(accumulator.terminalEventCount, 1)
        XCTAssertNil(accumulator.finish(stopped: false))
        XCTAssertEqual(accumulator.terminalEventCount, 1)
    }

    func testCancellationMarksUnreportedFilesStopped() {
        let accumulator = BatchResultAccumulator()
        accumulator.start(paths: ["done.wav", "pending.wav"])
        accumulator.recordSucceeded(path: "done.wav")

        let result = accumulator.finish(stopped: true, fallbackMessage: "cancelled")

        XCTAssertEqual(result?.stopped, true)
        XCTAssertEqual(result?.files[1], BatchFileResult(path: "pending.wav", status: .stopped, message: "cancelled"))
        XCTAssertEqual(result?.stoppedCount, 1)
    }
}
