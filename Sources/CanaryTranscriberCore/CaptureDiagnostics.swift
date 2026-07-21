import Foundation
import AVFoundation

public enum CaptureDiagnostic: Equatable, Error, CustomStringConvertible, Sendable {
    case screenRecordingPermissionDenied
    case microphonePermissionDenied
    case applicationUnavailable(String)
    case microphoneUnavailable(String)
    case emptyOrTinyFile(URL)
    case ffmpegUnavailable
    case ffmpegFailed(code: Int32, details: String)

    public var description: String {
        switch self {
        case .screenRecordingPermissionDenied:
            return "Screen Recording/System Audio Recording permission is denied. Open System Settings → Privacy & Security → Screen & System Audio Recording and allow Canary Transcriber."
        case .microphonePermissionDenied:
            return "Microphone permission is denied. Open System Settings → Privacy & Security → Microphone and allow Canary Transcriber."
        case .applicationUnavailable(let target):
            return "The selected application is no longer available: \(target). Click Refresh apps and select it again."
        case .microphoneUnavailable(let target):
            return "The selected microphone is no longer available: \(target). Choose System default microphone or click Refresh mics."
        case .emptyOrTinyFile(let url):
            return "The captured audio file is empty or too small: \(url.path). Check the relevant macOS permission and selected device."
        case .ffmpegUnavailable:
            return "ffmpeg was not found. Install it with: brew install ffmpeg"
        case .ffmpegFailed(let code, let details):
            return "ffmpeg could not mix app audio and microphone (code \(code)): \(details)"
        }
    }
}

public enum CaptureFileValidator {
    public static let minimumUsableBytes: Int64 = 1_024
    public static let minimumMicrophoneFrames: AVAudioFramePosition = 4_800

    public static func isUsableAudioFile(_ url: URL?) -> Bool {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value) ?? 0
        return size > minimumUsableBytes
    }

    public static func validateAudioFile(_ url: URL) -> Result<URL, CaptureDiagnostic> {
        isUsableAudioFile(url) ? .success(url) : .failure(.emptyOrTinyFile(url))
    }

    public static func validateMicrophoneFile(_ url: URL, recordedFrames: AVAudioFramePosition) -> Result<URL, CaptureDiagnostic> {
        guard recordedFrames >= minimumMicrophoneFrames else {
            return .failure(.emptyOrTinyFile(url))
        }
        return validateAudioFile(url)
    }
}
