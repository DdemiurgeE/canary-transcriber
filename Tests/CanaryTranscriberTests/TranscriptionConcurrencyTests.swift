import XCTest
@testable import CanaryTranscriberCore

final class TranscriptionConcurrencyTests: XCTestCase {
    func testBatchTranscriptionDoesNotDisableCaptureControls() {
        XCTAssertFalse(
            CaptureConcurrencyPolicy.captureControlsDisabled(
                isBatchRunning: true,
                isCaptureRecording: false,
                isCaptureFinishing: false
            )
        )
    }

    func testCaptureControlsAreDisabledOnlyWhileCaptureIsRecordingOrFinishing() {
        XCTAssertFalse(
            CaptureConcurrencyPolicy.captureControlsDisabled(
                isBatchRunning: false,
                isCaptureRecording: false,
                isCaptureFinishing: false
            )
        )
        XCTAssertTrue(
            CaptureConcurrencyPolicy.captureControlsDisabled(
                isBatchRunning: true,
                isCaptureRecording: true,
                isCaptureFinishing: false
            )
        )
        XCTAssertTrue(
            CaptureConcurrencyPolicy.captureControlsDisabled(
                isBatchRunning: true,
                isCaptureRecording: false,
                isCaptureFinishing: true
            )
        )
    }
}
