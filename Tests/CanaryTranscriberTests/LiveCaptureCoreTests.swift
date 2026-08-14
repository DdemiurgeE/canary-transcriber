import XCTest
@testable import CanaryTranscriberCore

final class LiveCaptureCoreTests: XCTestCase {
    func testPlannerCreatesNonOverlappingWindowsByDefault() {
        let windows = LiveCaptureWindowPlanner.plan(duration: 12, windowDuration: 5, overlap: 0)

        XCTAssertEqual(windows, [
            LiveCaptureWindow(index: 0, start: 0, end: 5),
            LiveCaptureWindow(index: 1, start: 5, end: 10),
            LiveCaptureWindow(index: 2, start: 10, end: 12)
        ])
    }

    func testPlannerUsesOverlapAndIncludesShortFinalWindow() {
        let windows = LiveCaptureWindowPlanner.plan(duration: 9, windowDuration: 5, overlap: 1)

        XCTAssertEqual(windows, [
            LiveCaptureWindow(index: 0, start: 0, end: 5),
            LiveCaptureWindow(index: 1, start: 4, end: 9)
        ])
    }

    func testAccumulatorIgnoresDuplicateSegmentAndRendersTimestampedTranscript() {
        var accumulator = LiveTranscriptAccumulator()
        let first = LiveTranscriptSegment(index: 0, start: 0, end: 5, text: " Hello world. ")
        let duplicate = LiveTranscriptSegment(index: 0, start: 0, end: 5, text: "Hello world.")
        let second = LiveTranscriptSegment(index: 1, start: 5, end: 10, text: "Next sentence.")

        XCTAssertTrue(accumulator.append(first))
        XCTAssertFalse(accumulator.append(duplicate))
        XCTAssertTrue(accumulator.append(second))
        XCTAssertEqual(accumulator.text, "Hello world.\nNext sentence.")
        XCTAssertEqual(accumulator.renderTimestamped(), "[00:00–00:05] Hello world.\n[00:05–00:10] Next sentence.")
    }

    func testAccumulatorRejectsEmptyText() {
        var accumulator = LiveTranscriptAccumulator()
        XCTAssertFalse(accumulator.append(LiveTranscriptSegment(index: 0, start: 0, end: 5, text: "  ")))
        XCTAssertTrue(accumulator.segments.isEmpty)
    }
}
