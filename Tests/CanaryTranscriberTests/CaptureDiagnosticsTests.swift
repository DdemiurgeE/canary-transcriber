import XCTest
@testable import CanaryTranscriberCore

final class CaptureDiagnosticsTests: XCTestCase {
    func testTinyOrMissingAppFileIsRejected() {
        let missing = URL(fileURLWithPath: "/tmp/canary-missing-\(UUID().uuidString).m4a")
        XCTAssertEqual(CaptureFileValidator.validateAudioFile(missing), .failure(.emptyOrTinyFile(missing)))
    }

    func testUsableAudioFileRequiresMoreThanMinimumBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: Int(CaptureFileValidator.minimumUsableBytes)).write(to: url)
        XCTAssertFalse(CaptureFileValidator.isUsableAudioFile(url))
        try Data(repeating: 0, count: Int(CaptureFileValidator.minimumUsableBytes + 1)).write(to: url)
        XCTAssertTrue(CaptureFileValidator.isUsableAudioFile(url))
    }

    func testMicrophoneFramesAndFileSizeAreBothRequired() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mic-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: Int(CaptureFileValidator.minimumUsableBytes + 1)).write(to: url)

        XCTAssertEqual(
            CaptureFileValidator.validateMicrophoneFile(url, recordedFrames: CaptureFileValidator.minimumMicrophoneFrames - 1),
            .failure(.emptyOrTinyFile(url))
        )
        XCTAssertEqual(
            CaptureFileValidator.validateMicrophoneFile(url, recordedFrames: CaptureFileValidator.minimumMicrophoneFrames),
            .success(url)
        )
    }

    func testPermissionAndDeviceDiagnosticsAreActionableAndEnglish() {
        let messages = [
            CaptureDiagnostic.screenRecordingPermissionDenied.description,
            CaptureDiagnostic.microphonePermissionDenied.description,
            CaptureDiagnostic.applicationUnavailable("Safari").description,
            CaptureDiagnostic.microphoneUnavailable("USB Mic").description,
            CaptureDiagnostic.ffmpegUnavailable.description
        ]
        for message in messages {
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("Не удалось"))
            XCTAssertFalse(message.contains("Проверь"))
        }
    }
}
