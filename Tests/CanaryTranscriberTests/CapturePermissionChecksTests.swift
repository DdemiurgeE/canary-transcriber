import XCTest
import AVFoundation
@testable import CanaryTranscriber
@testable import CanaryTranscriberCore

final class CapturePermissionChecksTests: XCTestCase {
    private final class FakePermissions: CapturePermissionProviding {
        var microphoneStatus: AVAuthorizationStatus = .authorized
        var screenAuthorized = true
        var microphoneRequests = 0
        var screenRequests = 0
        var microphoneRequestResult = true
        var screenRequestResult = true

        func microphoneAuthorizationStatus() -> AVAuthorizationStatus { microphoneStatus }
        func requestMicrophoneAccess() async -> Bool {
            microphoneRequests += 1
            return microphoneRequestResult
        }
        func screenAccessGranted() -> Bool { screenAuthorized }
        func requestScreenAccess() -> Bool {
            screenRequests += 1
            return screenRequestResult
        }
    }

    func testFirstLaunchRequestsBothMissingPermissions() async {
        let fake = FakePermissions()
        fake.microphoneStatus = .notDetermined
        fake.screenAuthorized = false
        let report = await CapturePermissionChecks.checkAtLaunch(using: fake)
        XCTAssertEqual(fake.microphoneRequests, 1)
        XCTAssertEqual(fake.screenRequests, 1)
        XCTAssertTrue(report.microphoneAuthorized)
        XCTAssertTrue(report.screenAuthorized)
    }

    func testDeniedMicrophoneDoesNotTriggerImpossibleRepeatPrompt() async {
        let fake = FakePermissions()
        fake.microphoneStatus = .denied
        let report = await CapturePermissionChecks.checkAtLaunch(using: fake)
        XCTAssertEqual(fake.microphoneRequests, 0)
        XCTAssertFalse(report.microphoneAuthorized)
        XCTAssertTrue(report.screenAuthorized)
    }

    func testAuthorizedPermissionsDoNotPrompt() async {
        let fake = FakePermissions()
        let report = await CapturePermissionChecks.checkAtLaunch(using: fake)
        XCTAssertEqual(fake.microphoneRequests, 0)
        XCTAssertEqual(fake.screenRequests, 0)
        XCTAssertTrue(report.microphoneAuthorized)
        XCTAssertTrue(report.screenAuthorized)
    }

    func testDeniedScreenRequestExplainsSettingsInsteadOfReportingSuccess() async {
        let fake = FakePermissions()
        fake.screenAuthorized = false
        fake.screenRequestResult = false
        let report = await CapturePermissionChecks.checkAtLaunch(using: fake)
        XCTAssertEqual(fake.screenRequests, 1)
        XCTAssertFalse(report.screenAuthorized)
    }

    @MainActor
    func testViewModelChecksOnceAndSurfacesDeniedMicOnLaunch() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CapturePermissionChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = TranscriptionViewModel(libraryStore: SessionLibraryStore(directoryURL: directory))
        let fake = FakePermissions()
        fake.microphoneStatus = .denied
        await model.checkCapturePermissionsOnLaunch(using: fake)
        await model.checkCapturePermissionsOnLaunch(using: fake)
        XCTAssertEqual(fake.microphoneRequests, 0)
        XCTAssertEqual(fake.screenRequests, 0)
        XCTAssertEqual(model.capturePermissionReport?.microphoneAuthorized, false)
        XCTAssertEqual(model.capturePermissionReport?.screenAuthorized, true)
    }
}
