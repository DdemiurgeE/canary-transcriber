import Foundation

/// Defines which capture controls are blocked by the capture lifecycle.
/// Batch transcription is intentionally independent: recording can continue
/// while a previous batch is being transcribed or diarized.
public enum CaptureConcurrencyPolicy {
    public static func captureControlsDisabled(
        isBatchRunning: Bool,
        isCaptureRecording: Bool,
        isCaptureFinishing: Bool
    ) -> Bool {
        _ = isBatchRunning
        return isCaptureRecording || isCaptureFinishing
    }
}
