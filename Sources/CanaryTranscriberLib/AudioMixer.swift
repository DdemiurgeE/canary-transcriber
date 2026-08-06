import Foundation
import CanaryTranscriberCore

final class AudioMixer {
    private init() {}

    static func mixArguments(appPath: String, micPath: String, outputPath: String) -> [String] {
        [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-i", appPath,
            "-i", micPath,
            "-filter_complex", "[0:a]volume=0.22[a0];[1:a]highpass=f=90,lowpass=f=9000,afftdn=nf=-28,dynaudnorm=f=150:g=31:p=0.95:m=15,volume=3.0[a1];[a0][a1]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0,alimiter=limit=0.95,aresample=48000[a]",
            "-map", "[a]",
            "-c:a", "aac", "-b:a", "192k",
            outputPath
        ]
    }

    static func mixAppAndMicrophone(appURL: URL, micURL: URL, outputURL: URL, onLog: ((String) -> Void)? = nil) throws -> URL {
        let ffmpeg = try resolveFFmpeg()
        onLog?("Stage: mix app audio + microphone with ffmpeg (mic-priority: app -13 dB, mic normalized/boosted) → \(outputURL.path)\n")
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = mixArguments(appPath: appURL.path, micPath: micURL.path, outputPath: outputURL.path)
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        // Drain the pipe while ffmpeg is still running, then wait: reading only after
        // waitUntilExit() deadlocks if ffmpeg's output fills the pipe buffer before it exits.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "CanaryAppAudioCapture", code: 10, userInfo: [NSLocalizedDescriptionKey: "ffmpeg could not mix app audio and microphone (code \(proc.terminationStatus)): \(output.suffix(2000))"])
        }
        guard CaptureFileValidator.isUsableAudioFile(outputURL) else {
            throw NSError(domain: "CanaryAppAudioCapture", code: 11, userInfo: [NSLocalizedDescriptionKey: "ffmpeg produced an empty/too-small mixed file: \(outputURL.path)"])
        }
        return outputURL
    }

    private static func resolveFFmpeg() throws -> String {
        let candidates = [
            ProcessInfo.processInfo.environment["FFMPEG_BIN"],
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for candidate in candidates where candidate.map(FileManager.default.isExecutableFile(atPath:)) == true {
            return candidate!
        }
        throw NSError(domain: "CanaryAppAudioCapture", code: 12, userInfo: [NSLocalizedDescriptionKey: "ffmpeg not found. Install with: brew install ffmpeg"])
    }
}
