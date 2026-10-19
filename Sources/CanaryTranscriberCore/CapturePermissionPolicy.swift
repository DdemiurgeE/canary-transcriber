import AVFoundation

public enum CapturePermissionAction: Equatable {
    case none
    case request
    case openSettings
}

public enum CapturePermissionPolicy {
    public static func microphoneAction(for status: AVAuthorizationStatus) -> CapturePermissionAction {
        switch status {
        case .authorized: return .none
        case .notDetermined: return .request
        case .denied, .restricted: return .openSettings
        @unknown default: return .openSettings
        }
    }

    // CoreGraphics preflight is Boolean: a false result may mean either a first-time
    // request or a previously denied request. The OS decides whether it can prompt.
    public static func screenAction(isAuthorized: Bool) -> CapturePermissionAction {
        isAuthorized ? .none : .request
    }
}
