import AVFoundation
import CoreGraphics
import CanaryTranscriberCore

protocol CapturePermissionProviding {
    func microphoneAuthorizationStatus() -> AVAuthorizationStatus
    func requestMicrophoneAccess() async -> Bool
    func screenAccessGranted() -> Bool
    func requestScreenAccess() -> Bool
}

struct CapturePermissionReport {
    let microphoneAuthorized: Bool
    let screenAuthorized: Bool
}

enum CapturePermissionChecks {
    static func checkAtLaunch(using provider: CapturePermissionProviding) async -> CapturePermissionReport {
        let microphoneAuthorized: Bool
        switch CapturePermissionPolicy.microphoneAction(for: provider.microphoneAuthorizationStatus()) {
        case .none: microphoneAuthorized = true
        case .request: microphoneAuthorized = await provider.requestMicrophoneAccess()
        case .openSettings: microphoneAuthorized = false
        }

        let screenAuthorized: Bool
        switch CapturePermissionPolicy.screenAction(isAuthorized: provider.screenAccessGranted()) {
        case .none: screenAuthorized = true
        case .request: screenAuthorized = provider.requestScreenAccess()
        case .openSettings: screenAuthorized = false
        }
        return CapturePermissionReport(microphoneAuthorized: microphoneAuthorized, screenAuthorized: screenAuthorized)
    }
}

struct SystemCapturePermissions: CapturePermissionProviding {
    func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func screenAccessGranted() -> Bool { CGPreflightScreenCaptureAccess() }
    func requestScreenAccess() -> Bool { CGRequestScreenCaptureAccess() }
}
