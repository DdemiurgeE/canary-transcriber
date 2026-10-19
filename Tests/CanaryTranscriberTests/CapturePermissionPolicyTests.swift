import XCTest
@testable import CanaryTranscriberCore

final class CapturePermissionPolicyTests: XCTestCase {
    func testUndeterminedMicrophonePermissionIsRequestedOnce() {
        XCTAssertEqual(CapturePermissionPolicy.microphoneAction(for: .notDetermined), .request)
    }

    func testDeniedOrRestrictedMicrophonePermissionRequiresSettings() {
        XCTAssertEqual(CapturePermissionPolicy.microphoneAction(for: .denied), .openSettings)
        XCTAssertEqual(CapturePermissionPolicy.microphoneAction(for: .restricted), .openSettings)
    }

    func testAuthorizedMicrophoneNeedsNoPrompt() {
        XCTAssertEqual(CapturePermissionPolicy.microphoneAction(for: .authorized), .none)
    }

    func testMissingScreenRecordingPermissionRequestsOrExplainsSettings() {
        XCTAssertEqual(CapturePermissionPolicy.screenAction(isAuthorized: false), .request)
        XCTAssertEqual(CapturePermissionPolicy.screenAction(isAuthorized: true), .none)
    }
}
