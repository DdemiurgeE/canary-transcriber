import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import AudioToolbox
import ScreenCaptureKit

@main
struct CanaryTranscriberApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("About Canary Transcriber") {
                    let credits = NSAttributedString(
                        string: """
Canary Transcriber — macOS GUI for batch transcription of audio/video files using local MLX STT runtimes.

Profiles:
• fast-parakeet-v3: NVIDIA Parakeet TDT 0.6B v3 via mlx-audio
• fast-whisper-turbo: Whisper large-v3-turbo via mlx-whisper
• accurate-whisper-large-v3: Whisper large-v3-mlx via mlx-whisper
• multilingual-canary-v2: CogniSoft Canary 1B v2 via mlx-audio
• realtime-voxtral-mini: Voxtral Mini 4B Realtime via mlx-audio

Features: ScreenCaptureKit per-app audio capture, AVAudioEngine microphone recording, mic-priority ffmpeg mix, automated dependency setup, model download via HuggingFace Hub.

License: MIT
""",
                        attributes: [.font: NSFont.systemFont(ofSize: 11)]
                    )
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [.credits: credits]
                    )
                }
            }
        }
    }
}

struct AudioFileItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    var status: String = "pending"

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AudioFileItem, rhs: AudioFileItem) -> Bool { lhs.id == rhs.id }
}

struct BatchConfig: Codable {
    let files: [String]
    let outputDir: String?
    let writeNextToSource: Bool
    let profileID: String
    let runtime: String
    let model: String
    let language: String
    let timestamps: Bool
    let chunkDuration: Double?
    let overlapDuration: Double
}

struct TranscriptionProfile: Identifiable, Hashable {
    let id: String
    let title: String
    let runtime: String
    let model: String
    let language: String
    let chunkDuration: String
    let details: String
}


struct CaptureAppTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let processID: pid_t

    var title: String {
        let bundle = bundleIdentifier.isEmpty ? "unknown bundle" : bundleIdentifier
        return "\(name) (pid \(processID), \(bundle))"
    }
}

struct MicrophoneDeviceTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let modelID: String
    let manufacturer: String

    var title: String {
        let vendor = manufacturer.isEmpty ? "" : " — \(manufacturer)"
        return "\(name)\(vendor)"
    }
}

enum DependencyStatus {
    case unknown
    case checking
    case present
    case missing
    case downloaded
    case downloading
    case updatable
}

struct FastTooltipModifier: ViewModifier {
    let text: String
    @State private var show = false
    private let delay: Double = 0.35

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if show {
                    Text(text)
                        .font(.caption)
                        .padding(6)
                        .background(.regularMaterial)
                        .cornerRadius(4)
                        .fixedSize()
                        .offset(y: 32)
                        .transition(.opacity.animation(.easeInOut(duration: 0.1)))
                }
            }
            .onHover { hovering in
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        show = true
                    }
                } else {
                    show = false
                }
            }
    }
}

extension View {
    func fastTooltip(_ text: String) -> some View {
        modifier(FastTooltipModifier(text: text))
    }
}

final class AppAudioCaptureController: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var isRecording = false

    private final class RealtimeAudioFileWriter {
        let url: URL
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        var hasStartedSession = false

        init(url: URL, sampleRate: Int = 48_000, channels: Int = 2) throws {
            self.url = url
            writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 192_000
            ]
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw NSError(domain: "CanaryAppAudioCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter не может добавить AAC audio input для \(url.lastPathComponent)."])
            }
            writer.add(input)
            guard writer.startWriting() else {
                throw writer.error ?? NSError(domain: "CanaryAppAudioCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter не стартовал для \(url.lastPathComponent)."])
            }
        }

        func append(_ sampleBuffer: CMSampleBuffer) {
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            if !hasStartedSession {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: timestamp)
                hasStartedSession = true
            }
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }

        func finish(completion: @escaping (Result<URL, Error>) -> Void) {
            input.markAsFinished()
            writer.finishWriting {
                if let error = self.writer.error {
                    completion(.failure(error))
                } else if Self.isUsableAudioFile(self.url) {
                    completion(.success(self.url))
                } else {
                    completion(.failure(NSError(domain: "CanaryAppAudioCapture", code: 5, userInfo: [NSLocalizedDescriptionKey: "Файл \(self.url.lastPathComponent) пустой или слишком маленький."])))
                }
            }
        }

        static func isUsableAudioFile(_ url: URL?) -> Bool {
            guard let url, FileManager.default.fileExists(atPath: url.path) else { return false }
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value) ?? 0
            return size > 1024
        }
    }


    private final class MicrophoneEngineRecorder {
        let url: URL
        private let deviceUID: String?
        private let engine = AVAudioEngine()
        private var file: AVAudioFile?
        private var recordedFrames: AVAudioFramePosition = 0

        init(url: URL, deviceUID: String?) {
            self.url = url
            self.deviceUID = deviceUID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? deviceUID : nil
        }

        func start() throws {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }

            let input = engine.inputNode
            if let deviceUID, let audioDeviceID = Self.audioDeviceID(matchingUID: deviceUID), let audioUnit = input.audioUnit {
                var mutableDeviceID = audioDeviceID
                let status = AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &mutableDeviceID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                guard status == noErr else {
                    throw NSError(domain: "CanaryAppAudioCapture", code: 21, userInfo: [NSLocalizedDescriptionKey: "Не удалось выбрать микрофон \(deviceUID) для AVAudioEngine (AudioUnitSetProperty status \(status))."])
                }
            } else if let deviceUID {
                throw NSError(domain: "CanaryAppAudioCapture", code: 23, userInfo: [NSLocalizedDescriptionKey: "Не удалось найти CoreAudio device для выбранного микрофона \(deviceUID). Выбери System default microphone или нажми Refresh mics."])
            }

            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "CanaryAppAudioCapture", code: 22, userInfo: [NSLocalizedDescriptionKey: "AVAudioEngine вернул пустой input format для микрофона."])
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            self.file = file
            recordedFrames = 0

            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let self, buffer.frameLength > 0 else { return }
                do {
                    try self.file?.write(from: buffer)
                    self.recordedFrames += AVAudioFramePosition(buffer.frameLength)
                } catch {
                    // Surface this on finish via the tiny-file/empty-file validation.
                }
            }
            engine.prepare()
            try engine.start()
        }

        func finish(completion: @escaping (Result<URL, Error>) -> Void) {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            file = nil

            if RealtimeAudioFileWriter.isUsableAudioFile(url), recordedFrames >= 4_800 {
                completion(.success(url))
            } else {
                completion(.failure(NSError(domain: "CanaryAppAudioCapture", code: 18, userInfo: [NSLocalizedDescriptionKey: "Микрофон записал слишком мало данных (\(recordedFrames) frames). Проверь выбранное устройство и Microphone permission."])))
            }
        }

        private static func audioDeviceID(matchingUID targetUID: String) -> AudioDeviceID? {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var dataSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return nil }
            let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
            var devices = Array(repeating: AudioDeviceID(), count: count)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == noErr else { return nil }

            for device in devices {
                var uidAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceUID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                var uid: Unmanaged<CFString>?
                if AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid) == noErr,
                   uid?.takeUnretainedValue() as String? == targetUID {
                    return device
                }
            }
            return nil
        }
    }

    private var stream: SCStream?
    private var appAudioWriter: RealtimeAudioFileWriter?
    private var microphoneRecorder: MicrophoneEngineRecorder?
    private let sampleQueue = DispatchQueue(label: "canary.app-audio-capture.samples")
    private let microphoneQueue = DispatchQueue(label: "canary.microphone-capture.samples")
    private var appOutputURL: URL?
    private var microphoneOutputURL: URL?
    private var mixedOutputURL: URL?
    private var includeMicrophone = false
    private var onLog: ((String) -> Void)?
    private var onFinished: ((Result<URL, Error>) -> Void)?

    @MainActor
    static func loadShareableApplications() async throws -> [CaptureAppTarget] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return content.applications
            .filter { $0.processID != ownPID }
            .map { app in
                CaptureAppTarget(
                    id: "\(app.bundleIdentifier)|\(app.processID)",
                    name: app.applicationName.isEmpty ? "Application" : app.applicationName,
                    bundleIdentifier: app.bundleIdentifier,
                    processID: app.processID
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @MainActor
    static func loadMicrophones() -> [MicrophoneDeviceTarget] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
            .map { device in
                MicrophoneDeviceTarget(
                    id: device.uniqueID,
                    name: device.localizedName,
                    modelID: device.modelID,
                    manufacturer: device.manufacturer
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func start(target: CaptureAppTarget, includeMicrophone: Bool, microphoneDeviceID: String?, outputDirectory: URL, onLog: @escaping (String) -> Void, onFinished: @escaping (Result<URL, Error>) -> Void) async {
        guard !isRecording else { return }
        self.includeMicrophone = includeMicrophone
        self.onLog = onLog
        self.onFinished = onFinished

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                throw NSError(domain: "CanaryAppAudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "ScreenCaptureKit не вернул ни одного дисплея для content filter."])
            }
            guard let app = content.applications.first(where: { $0.processID == target.processID }) else {
                throw NSError(domain: "CanaryAppAudioCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Приложение больше не найдено: \(target.title). Обнови список приложений."])
            }

            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let safeName = target.name.replacingOccurrences(of: "[^A-Za-z0-9А-Яа-я._-]+", with: "-", options: .regularExpression)
            let stamp = Int(Date().timeIntervalSince1970)
            let appURL = outputDirectory.appendingPathComponent("app-audio-\(safeName)-\(stamp).m4a")
            let micURL = outputDirectory.appendingPathComponent("mic-audio-\(safeName)-\(stamp).caf")
            let mixedURL = outputDirectory.appendingPathComponent("conference-audio-\(safeName)-\(stamp).m4a")
            appOutputURL = appURL
            microphoneOutputURL = includeMicrophone ? micURL : nil
            mixedOutputURL = includeMicrophone ? mixedURL : appURL

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

            self.appAudioWriter = try RealtimeAudioFileWriter(url: appURL)
            self.stream = stream

            try await stream.startCapture()
            if includeMicrophone {
                let recorder = MicrophoneEngineRecorder(url: micURL, deviceUID: microphoneDeviceID)
                try recorder.start()
                microphoneRecorder = recorder
            }
            await MainActor.run {
                self.isRecording = true
                onLog("🎙️ App audio capture started: \(target.title) → \(appURL.path)\n")
                if includeMicrophone {
                    let micLabel = microphoneDeviceID?.isEmpty == false ? microphoneDeviceID! : "system default"
                    onLog("🎤 Microphone capture enabled via AVAudioEngine (device=\(micLabel)) → \(micURL.path)\n")
                    onLog("   After Stop, app + mic will be mixed via ffmpeg into \(mixedURL.lastPathComponent).\n")
                }
                onLog("   macOS may request Screen Recording and Microphone permissions for Canary Transcriber.\n")
            }
        } catch {
            cleanupAfterFailure()
            await MainActor.run {
                onLog("❌ Failed to start app audio capture: \(error.localizedDescription)\n")
                onFinished(.failure(error))
            }
        }
    }

    func stop() {
        guard isRecording || stream != nil || appAudioWriter != nil || microphoneRecorder != nil else { return }
        let streamToStop = stream
        onLog?("⏹️ Stopping app/mic audio capture...\n")
        isRecording = false
        Task {
            if let streamToStop {
                try? await streamToStop.stopCapture()
            }
            finishWritersAndMixIfNeeded()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            appAudioWriter?.append(sampleBuffer)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onLog?("⚠️ ScreenCaptureKit stream stopped with error: \(error.localizedDescription)\n")
        stop()
    }

    private func finishWritersAndMixIfNeeded() {
        sampleQueue.async {
            let appWriter = self.appAudioWriter
            let micRecorder = self.microphoneRecorder
            let includeMic = self.includeMicrophone
            let mixedURL = self.mixedOutputURL

            let group = DispatchGroup()
            var appResult: Result<URL, Error>?
            var micResult: Result<URL, Error>?

            if let appWriter {
                group.enter()
                appWriter.finish { result in
                    appResult = result
                    group.leave()
                }
            }
            if let micRecorder {
                group.enter()
                self.microphoneQueue.async {
                    micRecorder.finish { result in
                        micResult = result
                        group.leave()
                    }
                }
            }

            group.notify(queue: self.sampleQueue) {
                let finalResult: Result<URL, Error>
                switch appResult {
                case .success(let appURL):
                    if includeMic {
                        switch micResult {
                        case .success(let micURL):
                            do {
                                let out = try self.mixAppAndMicrophone(appURL: appURL, micURL: micURL, outputURL: mixedURL ?? appURL)
                                finalResult = .success(out)
                            } catch {
                                finalResult = .failure(error)
                            }
                        case .failure(let error):
                            finalResult = .failure(NSError(domain: "CanaryAppAudioCapture", code: 7, userInfo: [NSLocalizedDescriptionKey: "App audio recorded, but microphone did not record: \(error.localizedDescription). Check Microphone permission for Canary Transcriber."]))
                        case .none:
                            finalResult = .failure(NSError(domain: "CanaryAppAudioCapture", code: 8, userInfo: [NSLocalizedDescriptionKey: "Microphone was enabled but the writer returned no result."]))
                        }
                    } else {
                        finalResult = .success(appURL)
                    }
                case .failure(let error):
                    finalResult = .failure(error)
                case .none:
                    finalResult = .failure(NSError(domain: "CanaryAppAudioCapture", code: 9, userInfo: [NSLocalizedDescriptionKey: "App audio writer returned no result."]))
                }

                DispatchQueue.main.async {
                    self.stream = nil
                    self.appAudioWriter = nil
                    self.microphoneRecorder = nil
                    self.appOutputURL = nil
                    self.microphoneOutputURL = nil
                    self.mixedOutputURL = nil
                    self.includeMicrophone = false
                    self.isRecording = false
                    self.onFinished?(finalResult)
                }
            }
        }
    }

    private func mixAppAndMicrophone(appURL: URL, micURL: URL, outputURL: URL) throws -> URL {
        let ffmpeg = try resolveFFmpeg()
        onLog?("Stage: mix app audio + microphone with ffmpeg (mic-priority: app -13 dB, mic normalized/boosted) → \(outputURL.path)\n")
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", appURL.path,
            "-i", micURL.path,
            "-filter_complex", "[0:a]volume=0.22[a0];[1:a]highpass=f=90,lowpass=f=9000,afftdn=nf=-28,dynaudnorm=f=150:g=31:p=0.95:m=15,volume=3.0[a1];[a0][a1]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0,alimiter=limit=0.95,aresample=48000[a]",
            "-map", "[a]",
            "-c:a", "aac", "-b:a", "192k",
            outputURL.path
        ]
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "CanaryAppAudioCapture", code: 10, userInfo: [NSLocalizedDescriptionKey: "ffmpeg could not mix app audio and microphone (code \(proc.terminationStatus)): \(output.suffix(2000))"])
        }
        guard RealtimeAudioFileWriter.isUsableAudioFile(outputURL) else {
            throw NSError(domain: "CanaryAppAudioCapture", code: 11, userInfo: [NSLocalizedDescriptionKey: "ffmpeg produced an empty/too-small mixed file: \(outputURL.path)"])
        }
        return outputURL
    }

    private func resolveFFmpeg() throws -> String {
        let candidates = [
            ProcessInfo.processInfo.environment["FFMPEG_BIN"],
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for candidate in candidates {
            if let candidate, FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw NSError(domain: "CanaryAppAudioCapture", code: 12, userInfo: [NSLocalizedDescriptionKey: "ffmpeg not found. Install with: brew install ffmpeg"])
    }

    private func cleanupAfterFailure() {
        stream = nil
        appAudioWriter = nil
        microphoneRecorder = nil
        appOutputURL = nil
        microphoneOutputURL = nil
        mixedOutputURL = nil
        includeMicrophone = false
        isRecording = false
    }
}

struct ContentView: View {
    @State private var files: [AudioFileItem] = []
    @State private var selectedFileID: AudioFileItem.ID?
    @State private var logs: String = "Ready. Add audio files and click Transcribe.\n"

    @State private var pythonPath: String = Self.defaultCanaryPythonPath()
    @State private var selectedProfileID: String = "multilingual-canary-v2"
    @State private var runtime: String = "mlx_audio_cli"
    @State private var model: String = "CogniSoftOrg/canary-1b-v2-mlx-bf16"
    @State private var language: String = "ru"
    @State private var chunkDuration: String = "30"
    @State private var timestamps: Bool = false
    @State private var writeNextToSource: Bool = true
    @State private var outputFolder: String = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/CanaryTranscripts").path

    @State private var isRunning = false
    @State private var process: Process?
    @State private var currentConfigPath: String?
    @State private var isFileDropTargeted = false

    @StateObject private var appAudioCapture = AppAudioCaptureController()
    @State private var captureApps: [CaptureAppTarget] = []
    @State private var selectedCaptureAppID: CaptureAppTarget.ID?
    @State private var isRefreshingCaptureApps = false
    @State private var captureMicrophone: Bool = true
    @State private var microphoneDevices: [MicrophoneDeviceTarget] = []
    @State private var selectedMicrophoneID: MicrophoneDeviceTarget.ID?

    // Dependencies & models
    @State private var ffmpegStatus: DependencyStatus = .unknown
    @State private var pythonStatus: DependencyStatus = .unknown
    @State private var modelDownloadStatus: [String: DependencyStatus] = [:]
    @State private var isInstallingFFmpeg = false
    @State private var isSettingUpPython = false
    @State private var isDownloadingModel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dependencyPanel
            settingsPanel
            appCapturePanel
            filePanel
            controlsPanel
            logPanel
        }
        .padding(16)
        .frame(minWidth: 1080, idealWidth: 1120, minHeight: 820, idealHeight: 900)
        .onAppear {
            bringAppToFront()
            refreshCaptureApps()
            refreshMicrophones()
            checkDependencies()
        }
    }

    private var profiles: [TranscriptionProfile] {
        [
            TranscriptionProfile(
                id: "fast-parakeet-v3",
                title: "fast — Parakeet v3",
                runtime: "mlx_audio_cli",
                model: "mlx-community/parakeet-tdt-0.6b-v3",
                language: "ru",
                chunkDuration: "30",
                details: "Default fast MLX STT: NVIDIA Parakeet TDT 0.6B v3 via mlx-audio."
            ),
            TranscriptionProfile(
                id: "fast-whisper-turbo",
                title: "fast — Whisper Turbo",
                runtime: "mlx_whisper",
                model: "mlx-community/whisper-large-v3-turbo",
                language: "ru",
                chunkDuration: "30",
                details: "Fast Whisper-compatible profile via mlx-whisper."
            ),
            TranscriptionProfile(
                id: "accurate-whisper-large-v3",
                title: "accurate — Whisper large-v3",
                runtime: "mlx_whisper",
                model: "mlx-community/whisper-large-v3-mlx",
                language: "ru",
                chunkDuration: "30",
                details: "Well-tested universal baseline for quality and challenging audio."
            ),
            TranscriptionProfile(
                id: "multilingual-canary-v2",
                title: "multilingual European — Canary 1B v2",
                runtime: "mlx_audio_cli",
                model: "CogniSoftOrg/canary-1b-v2-mlx-bf16",
                language: "ru",
                chunkDuration: "30",
                details: "Canary 1B v2 for 25 European languages; ASR/translation via mlx-audio."
            ),
            TranscriptionProfile(
                id: "realtime-voxtral-mini",
                title: "realtime — Voxtral Mini Realtime",
                runtime: "mlx_audio_cli",
                model: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
                language: "ru",
                chunkDuration: "30",
                details: "Streaming/realtime-oriented model; runs on files via mlx-audio in batch mode."
            )
        ]
    }

    private var selectedProfile: TranscriptionProfile {
        profiles.first(where: { $0.id == selectedProfileID }) ?? profiles[0]
    }

    private var header: some View {
        HStack {
            if isRunning {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("running")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 20)
    }

    private var dependencyPanel: some View {
        GroupBox("Dependencies & Models") {
            VStack(alignment: .leading, spacing: 8) {
                // ffmpeg
                HStack(spacing: 8) {
                    statusDot(ffmpegStatus)
                    Text("ffmpeg").frame(width: 90, alignment: .leading)
                    Text(ffmpegStatusLabel(ffmpegStatus)).foregroundStyle(.secondary)
                    Spacer()
                    switch ffmpegStatus {
                    case .missing:
                        Button(isInstallingFFmpeg ? "Installing..." : "Install ffmpeg") { installFFmpeg() }
                            .disabled(isInstallingFFmpeg)
                    default:
                        EmptyView()
                    }
                }

                // Python venv
                HStack(spacing: 8) {
                    statusDot(pythonStatus)
                    Text("Python venv").frame(width: 90, alignment: .leading)
                    Text(pythonStatusLabel(pythonStatus)).foregroundStyle(.secondary)
                    Spacer()
                    switch pythonStatus {
                    case .missing:
                        Button(isSettingUpPython ? "Setting up..." : "Setup venv") { setupPythonEnvironment() }
                            .disabled(isSettingUpPython || isRunning)
                    default:
                        EmptyView()
                    }
                }

                Divider()

                // Selected model
                let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.model : model.trimmingCharacters(in: .whitespacesAndNewlines)
                let modelStatus = modelDownloadStatus[modelID] ?? .unknown
                HStack(spacing: 8) {
                    statusDot(modelStatus)
                    Text("Model").frame(width: 90, alignment: .leading)
                    Text(modelID).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    switch modelStatus {
                    case .downloaded:
                        Text("✓ cached").foregroundStyle(.green).font(.caption)
                    case .downloading:
                        ProgressView().controlSize(.small)
                    case .missing, .unknown:
                        Button(isDownloadingModel ? "Downloading..." : "Download model") { downloadModel(modelID) }
                            .disabled(isDownloadingModel || isRunning)
                    case .updatable:
                        HStack(spacing: 4) {
                            Text("update available").font(.caption).foregroundStyle(.orange)
                            Button("Update") { downloadModel(modelID) }
                                .disabled(isDownloadingModel || isRunning)
                                .controlSize(.small)
                        }
                    case .checking:
                        Text("Checking...").foregroundStyle(.secondary).font(.caption)
                    case .present:
                        Text("✓ installed").foregroundStyle(.green).font(.caption)
                    }
                }

                Text("Dependencies: brew / pip / venv. Models download from HuggingFace Hub.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var settingsPanel: some View {
        GroupBox("Settings") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Profile")
                        .frame(width: 120, alignment: .leading)
                    Picker("Profile", selection: $selectedProfileID) {
                        ForEach(profiles) { profile in
                            Text(profile.title).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    .onChange(of: selectedProfileID) { applySelectedProfile() }
                    Text(selectedProfile.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack {
                    Text("Python venv")
                        .frame(width: 120, alignment: .leading)
                    TextField("/path/to/venv/bin/python", text: $pythonPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose") { choosePython() }
                }

                HStack {
                    Text("Runtime")
                        .frame(width: 120, alignment: .leading)
                    Picker("Runtime", selection: $runtime) {
                        Text("mlx-audio CLI").tag("mlx_audio_cli")
                        Text("mlx-whisper").tag("mlx_whisper")
                        Text("canary-mlx legacy").tag("canary_mlx")
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Text("Lang")
                    TextField("ru", text: $language)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)

                    Text("Chunk sec")
                    TextField("30", text: $chunkDuration)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)

                    Toggle("timestamps", isOn: $timestamps)
                        .toggleStyle(.checkbox)
                }

                Toggle("Save alongside source file", isOn: $writeNextToSource)
                    .toggleStyle(.checkbox)

                HStack {
                    Text("Model")
                        .frame(width: 120, alignment: .leading)
                    Text(model.isEmpty ? selectedProfile.model : model)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack {
                    Text("Output folder")
                        .frame(width: 120, alignment: .leading)
                    TextField("/path/to/output", text: $outputFolder)
                        .textFieldStyle(.roundedBorder)
                        .disabled(writeNextToSource)
                    Button("Choose") { chooseOutputFolder() }
                        .disabled(writeNextToSource)
                }
            }
            .padding(.vertical, 4)
        }
    }



    private var appCapturePanel: some View {
        GroupBox("App Audio Capture — ScreenCaptureKit") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Application", selection: $selectedCaptureAppID) {
                        Text(captureApps.isEmpty ? "Press Refresh apps" : "Select an application").tag(Optional<CaptureAppTarget.ID>.none)
                        ForEach(captureApps) { app in
                            Text(app.title).tag(Optional(app.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 400)
                    .disabled(appAudioCapture.isRecording || isRunning)

                    Button(isRefreshingCaptureApps ? "Refreshing..." : "Refresh apps") { refreshCaptureApps() }
                        .disabled(isRefreshingCaptureApps || appAudioCapture.isRecording || isRunning)

                    Spacer()

                    HStack(spacing: 4) {
                        Button(action: { startAppAudioCapture(withMic: false) }) {
                            Image(systemName: "app.badge")
                                .font(.title)
                        }
                        .fastTooltip("Record app audio only (no microphone)")
                        .disabled(appAudioCapture.isRecording || isRunning || selectedCaptureApp == nil)

                        Button(action: { startAppAudioCapture(withMic: true) }) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.title)
                        }
                        .fastTooltip("Record app audio + microphone")
                        .disabled(appAudioCapture.isRecording || isRunning || selectedCaptureApp == nil)

                        Button(action: { stopAppAudioCapture() }) {
                            Image(systemName: "stop.fill")
                                .font(.title)
                        }
                        .fastTooltip("Stop recording")
                        .disabled(!appAudioCapture.isRecording)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                HStack(spacing: 8) {
                    Picker("Microphone", selection: $selectedMicrophoneID) {
                        Text(microphoneDevices.isEmpty ? "System default microphone" : "System default microphone").tag(Optional<MicrophoneDeviceTarget.ID>.none)
                        ForEach(microphoneDevices) { mic in
                            Text(mic.title).tag(Optional(mic.id))
                        }
                    }
                    .frame(maxWidth: 360)
                    .disabled(!captureMicrophone || appAudioCapture.isRecording || isRunning)

                    Button("Refresh mics") { refreshMicrophones() }
                        .disabled(appAudioCapture.isRecording || isRunning)
                }

            }
            .padding(.vertical, 4)
        }
    }

    private var filePanel: some View {
        GroupBox("Files") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Add files") { chooseAudioFiles() }
                        .disabled(isRunning)
                    Button("Remove selected") { removeSelectedFile() }
                        .disabled(isRunning || selectedFileID == nil)
                    Button("Clear list") { files.removeAll() }
                        .disabled(isRunning || files.isEmpty)
                    Text("Selected: \(files.count)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Drag & drop audio/video files here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isFileDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    isFileDropTargeted ? Color.accentColor : Color.secondary.opacity(files.isEmpty ? 0.45 : 0.15),
                                    style: StrokeStyle(lineWidth: isFileDropTargeted ? 2 : 1, dash: files.isEmpty ? [6, 5] : [])
                                )
                        )

                    List(selection: $selectedFileID) {
                        ForEach(files) { item in
                            HStack {
                                Text(item.status)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(width: 90, alignment: .leading)
                                    .foregroundStyle(colorForStatus(item.status))
                                Text(item.path)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .tag(item.id)
                        }
                    }
                    .opacity(files.isEmpty ? 0.35 : 1)
                    .padding(4)

                    if files.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(isFileDropTargeted ? Color.accentColor : Color.secondary)
                            Text(isFileDropTargeted ? "Release to add files" : "Drop audio/video files here")
                                .font(.headline)
                            Text("or click Add files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 180, idealHeight: 210, maxHeight: 240)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted, perform: handleFileDrop(providers:))
            }
            .padding(.vertical, 4)
        }
    }

    private var controlsPanel: some View {
        HStack(spacing: 8) {
            Button(isRunning ? "Transcribing..." : "Transcribe") { startBatch() }
                .disabled(isRunning || files.isEmpty)

            Button("Stop") { stopBatch() }
                .disabled(!isRunning)

            Button("Open output") { openOutputLocation() }

            Button("Clear logs") { logs = "" }
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log")
                .font(.headline)
            ScrollView {
                Text(logs)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180, idealHeight: 220, maxHeight: .infinity)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
    }



    private var selectedCaptureApp: CaptureAppTarget? {
        guard let selectedCaptureAppID else { return nil }
        return captureApps.first(where: { $0.id == selectedCaptureAppID })
    }

    private var selectedMicrophone: MicrophoneDeviceTarget? {
        guard let selectedMicrophoneID else { return nil }
        return microphoneDevices.first(where: { $0.id == selectedMicrophoneID })
    }

    private func refreshMicrophones() {
        let devices = AppAudioCaptureController.loadMicrophones()
        microphoneDevices = devices
        if let selectedMicrophoneID, !devices.contains(where: { $0.id == selectedMicrophoneID }) {
            self.selectedMicrophoneID = nil
        }
        logs += "Stage: microphones found: \(devices.count)"
        if let selectedMicrophone {
            logs += "; selected=\(selectedMicrophone.title)"
        } else {
            logs += "; selected=system default"
        }
        logs += "\n"
    }

    private func refreshCaptureApps() {
        guard !isRefreshingCaptureApps else { return }
        isRefreshingCaptureApps = true
        logs += "Stage: refresh ScreenCaptureKit application list...\n"
        Task {
            do {
                let apps = try await AppAudioCaptureController.loadShareableApplications()
                await MainActor.run {
                    self.captureApps = apps
                    if let selectedCaptureAppID, !apps.contains(where: { $0.id == selectedCaptureAppID }) {
                        self.selectedCaptureAppID = nil
                    }
                    if self.selectedCaptureAppID == nil {
                        self.selectedCaptureAppID = apps.first?.id
                    }
                    self.logs += "Stage: ScreenCaptureKit apps found: \(apps.count)\n"
                    self.isRefreshingCaptureApps = false
                }
            } catch {
                await MainActor.run {
                    self.logs += "❌ Cannot refresh app list: \(error.localizedDescription)\n"
                    self.logs += "⚠️ Check System Settings → Privacy & Security → Screen Recording for Canary Transcriber.\n"
                    self.isRefreshingCaptureApps = false
                }
            }
        }
    }

    private func startAppAudioCapture(withMic: Bool = true) {
        guard let target = selectedCaptureApp else {
            logs += "⚠️ Select an application first.\n"
            return
        }
        let captureDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/CanaryTranscripts/AppAudioCaptures", isDirectory: true)
        let micLabel = captureMicrophone ? (selectedMicrophone?.title ?? "system default") : "off"
        captureMicrophone = withMic
        logs += "Stage: start app audio capture for \(target.title); microphone=\(micLabel)\n"
        Task {
            await appAudioCapture.start(target: target, includeMicrophone: captureMicrophone, microphoneDeviceID: selectedMicrophoneID, outputDirectory: captureDir, onLog: { text in
                DispatchQueue.main.async {
                    self.logs += text
                    self.appendPersistentLog(text)
                }
            }, onFinished: { result in
                switch result {
                case .success(let url):
                    self.logs += "✅ App audio recording saved: \(url.path)\n"
                    self.appendPersistentLog("✅ App audio recording saved: \(url.path)\n")
                    self.addAudioPaths([url.path], source: "app audio capture")
                case .failure(let error):
                    self.logs += "❌ App audio recording failed: \(error.localizedDescription)\n"
                    self.appendPersistentLog("❌ App audio recording failed: \(error.localizedDescription)\n")
                }
            })
        }
    }

    private func stopAppAudioCapture() {
        appAudioCapture.stop()
    }

    private func applySelectedProfile() {
        let profile = selectedProfile
        runtime = profile.runtime
        model = profile.model
        language = profile.language
        chunkDuration = profile.chunkDuration
        logs += "Profile selected: \(profile.title) → runtime=\(profile.runtime), model=\(profile.model)\n"
    }

    private func chooseAudioFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = []
        panel.message = "Select audio/video files for Canary Transcriber"
        if panel.runModal() == .OK {
            let newPaths = panel.urls.map { normalizeUserPath($0.standardizedFileURL.path) }
            addAudioPaths(newPaths, source: "picker")
        }
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard !isRunning else {
            logs += "⚠️ Cannot add files during transcription.\n"
            return false
        }

        let fileURLType = UTType.fileURL.identifier
        let matchingProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(fileURLType) }
        guard !matchingProviders.isEmpty else { return false }

        for provider in matchingProviders {
            provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { item, error in
                if let error {
                    DispatchQueue.main.async {
                        logs += "⚠️ Drop error: \(error.localizedDescription)\n"
                    }
                    return
                }

                guard let path = decodeDroppedFilePath(item) else {
                    DispatchQueue.main.async {
                        logs += "⚠️ Drop: could not read file URL.\n"
                    }
                    return
                }

                DispatchQueue.main.async {
                    addAudioPaths([path], source: "drag&drop")
                }
            }
        }
        return true
    }

    private func decodeDroppedFilePath(_ item: NSSecureCoding?) -> String? {
        if let url = item as? URL {
            return normalizeUserPath(url.standardizedFileURL.path)
        }
        if let data = item as? Data,
           let raw = String(data: data, encoding: .utf8),
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return normalizeUserPath(url.standardizedFileURL.path)
        }
        if let string = item as? String,
           let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return normalizeUserPath(url.standardizedFileURL.path)
        }
        return nil
    }

    private func addAudioPaths(_ rawPaths: [String], source: String) {
        let fm = FileManager.default
        let existing = Set(files.map { $0.path })
        var additions: [AudioFileItem] = []
        var skippedDirectories = 0
        var skippedDuplicates = 0

        for rawPath in rawPaths {
            let path = normalizeUserPath(rawPath)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                skippedDirectories += 1
                continue
            }
            if existing.contains(path) || additions.contains(where: { $0.path == path }) {
                skippedDuplicates += 1
                continue
            }
            additions.append(AudioFileItem(path: path))
        }

        if !additions.isEmpty {
            files.append(contentsOf: additions)
        }
        logs += "Added files (\(source)): \(additions.count)"
        if skippedDuplicates > 0 { logs += ", duplicates skipped: \(skippedDuplicates)" }
        if skippedDirectories > 0 { logs += ", directories skipped: \(skippedDirectories)" }
        logs += "\n"
    }

    private func choosePython() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url {
            pythonPath = normalizeUserPath(url.standardizedFileURL.path)
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = normalizeUserPath(url.standardizedFileURL.path)
        }
    }

    private func removeSelectedFile() {
        guard let selectedFileID else { return }
        files.removeAll { $0.id == selectedFileID }
        self.selectedFileID = nil
    }

    private func startBatch() {
        guard !isRunning else { return }

        let cleanPython = normalizeUserPath(pythonPath)
        pythonPath = cleanPython
        guard FileManager.default.isExecutableFile(atPath: cleanPython) else {
            logs += "❌ Python is not executable: \(cleanPython)\n"
            logs += "   Set the Python venv path, e.g. ~/venvs/canary-mlx/bin/python\n"
            return
        }

        let normalizedFiles = files.map { item in
            AudioFileItem(path: normalizeUserPath(item.path), status: "queued")
        }
        files = normalizedFiles
        let missing = normalizedFiles.filter { !FileManager.default.fileExists(atPath: $0.path) }
        if !missing.isEmpty {
            logs += "❌ Files not found:\n"
            for item in missing { logs += "   \(item.path)\n" }
            return
        }

        let cleanOutput = normalizeUserPath(outputFolder)
        outputFolder = cleanOutput
        if !writeNextToSource {
            do {
                try FileManager.default.createDirectory(atPath: cleanOutput, withIntermediateDirectories: true)
            } catch {
                logs += "❌ Cannot create output folder: \(error.localizedDescription)\n"
                return
            }
        }

        let chunk = Double(chunkDuration.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30.0
        let config = BatchConfig(
            files: normalizedFiles.map { $0.path },
            outputDir: writeNextToSource ? nil : cleanOutput,
            writeNextToSource: writeNextToSource,
            profileID: selectedProfileID,
            runtime: runtime,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.model : model.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.language : language.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamps: timestamps,
            chunkDuration: chunk <= 0 ? nil : chunk,
            overlapDuration: 2.0
        )

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canary-transcriber-\(UUID().uuidString).json")
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL)
            currentConfigPath = configURL.path
        } catch {
            logs += "❌ Cannot write temp config: \(error.localizedDescription)\n"
            return
        }

        runPython(configURL: configURL, pythonPath: cleanPython, config: config)
    }

    private func runPython(configURL: URL, pythonPath: String, config: BatchConfig) {
        let script = #"""
import json
import shutil
import subprocess
import sys
import tempfile
import traceback
import wave
from pathlib import Path

try:
    cfg = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    files = [Path(p).expanduser() for p in cfg["files"]]
    output_dir = Path(cfg["outputDir"]).expanduser() if cfg.get("outputDir") else None
    write_next_to_source = bool(cfg.get("writeNextToSource", True))
    model_id = cfg.get("model") or "qfuxa/canary-mlx"
    runtime = cfg.get("runtime") or "canary_mlx"
    profile_id = cfg.get("profileID") or "custom"
    language = cfg.get("language") or "ru"
    timestamps = bool(cfg.get("timestamps", False))
    chunk_duration = cfg.get("chunkDuration", 30.0)
    overlap_duration = float(cfg.get("overlapDuration", 2.0))

    def emit(kind, **payload):
        payload["kind"] = kind
        print("CANARY_EVENT " + json.dumps(payload, ensure_ascii=False, default=str), flush=True)

    def output_paths(audio_path):
        base_dir = audio_path.parent if write_next_to_source else output_dir
        base_dir.mkdir(parents=True, exist_ok=True)
        stem = audio_path.stem
        return base_dir / f"{stem}.canary.txt", base_dir / f"{stem}.canary.json"

    def resolve_ffmpeg():
        candidates = [
            shutil.which("ffmpeg"),
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
        ]
        for c in candidates:
            if c and Path(c).exists():
                return c
        raise RuntimeError("ffmpeg not found. Install with: brew install ffmpeg")

    def wav_duration_seconds(path):
        with wave.open(str(path), "rb") as wf:
            frames = wf.getnframes()
            rate = wf.getframerate()
            return frames / float(rate)

    def make_wav_chunks(audio_path, work_dir, seconds):
        ffmpeg = resolve_ffmpeg()
        normalized = work_dir / "normalized.wav"
        print(f"Stage: ffmpeg normalize -> {normalized}", flush=True)
        subprocess.run([
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(audio_path),
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            str(normalized),
        ], check=True)

        duration = wav_duration_seconds(normalized)
        chunk_seconds = float(seconds or 30.0)
        if chunk_seconds <= 0:
            chunk_seconds = 30.0
        chunks = []
        start = 0.0
        idx = 0
        while start < duration:
            out = work_dir / f"chunk_{idx:04d}.wav"
            subprocess.run([
                ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                "-ss", f"{start:.3f}", "-i", str(normalized),
                "-t", f"{chunk_seconds:.3f}",
                "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
                str(out),
            ], check=True)
            if out.exists() and out.stat().st_size > 44:
                chunks.append((idx, start, out))
            idx += 1
            start += chunk_seconds
        print(f"Stage: prepared {len(chunks)} wav chunks; duration={duration:.1f}s chunk={chunk_seconds:.1f}s", flush=True)
        return chunks, duration, chunk_seconds

    def make_transcriber(runtime_name, model_name):
        print(f"Stage: runtime preflight profile={profile_id} runtime={runtime_name} model={model_name}", flush=True)
        if runtime_name == "canary_mlx":
            try:
                from canary_mlx import load_model
            except Exception as exc:
                raise RuntimeError("Python package canary-mlx is required for runtime=canary_mlx. Install: python -m pip install canary-mlx") from exc
            print(f"Stage: load_model({model_name})", flush=True)
            model_obj = load_model(model_name)
            print("Stage: model loaded", flush=True)
            def transcribe(path):
                result = model_obj.transcribe(str(path), language=language, timestamps=timestamps)
                return result.text if hasattr(result, "text") else str(result)
            return transcribe

        if runtime_name == "mlx_whisper":
            try:
                import mlx_whisper
            except Exception as exc:
                raise RuntimeError("Python package mlx-whisper is required for Whisper profiles. Install: python -m pip install mlx-whisper") from exc
            print("Stage: mlx_whisper ready", flush=True)
            def transcribe(path):
                kwargs = {"path_or_hf_repo": model_name}
                if language:
                    kwargs["language"] = language
                try:
                    result = mlx_whisper.transcribe(str(path), **kwargs)
                except TypeError:
                    kwargs.pop("language", None)
                    result = mlx_whisper.transcribe(str(path), **kwargs)
                if isinstance(result, dict):
                    return str(result.get("text", ""))
                return result.text if hasattr(result, "text") else str(result)
            return transcribe

        if runtime_name == "mlx_audio_cli":
            try:
                import mlx_audio  # noqa: F401
            except Exception as exc:
                raise RuntimeError("Python package mlx-audio is required for Parakeet/Canary v2/Voxtral profiles. Install: python -m pip install 'mlx-audio[stt]' or python -m pip install mlx-audio") from exc
            print("Stage: mlx_audio CLI ready", flush=True)
            def transcribe(path):
                with tempfile.TemporaryDirectory(prefix="mlx-audio-out-") as out_tmp:
                    out_dir = Path(out_tmp)
                    out_file = out_dir / "transcript.txt"
                    cmd = [
                        sys.executable, "-m", "mlx_audio.stt.generate",
                        "--model", model_name,
                        "--audio", str(path),
                        "--output-path", str(out_file),
                        "--format", "txt",
                    ]
                    if language:
                        cmd.extend(["--language", language])
                        lang_kwargs = json.dumps({"source_lang": language, "target_lang": language}, ensure_ascii=False)
                        cmd.extend(["--gen-kwargs", lang_kwargs])
                    print("Stage: mlx-audio command language=" + str(language) + " gen_kwargs=" + (lang_kwargs if language else "{}"), flush=True)
                    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                    output = proc.stdout or ""
                    if proc.returncode != 0:
                        if "--language" in cmd:
                            cmd = [x for x in cmd if x not in ["--language", language]]
                            proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                            output = proc.stdout or ""
                    if proc.returncode != 0:
                        raise RuntimeError(f"mlx-audio CLI failed with code {proc.returncode}: {output[-4000:]}")
                    text_candidates = []
                    for candidate in sorted(out_dir.rglob("*")):
                        if candidate.is_file() and candidate.suffix.lower() in {".txt", ".text", ".md"}:
                            text_candidates.append(candidate.read_text(encoding="utf-8", errors="ignore"))
                        elif candidate.is_file() and candidate.suffix.lower() == ".json":
                            try:
                                data = json.loads(candidate.read_text(encoding="utf-8", errors="ignore"))
                                if isinstance(data, dict):
                                    for key in ["text", "transcription", "transcript"]:
                                        if data.get(key):
                                            text_candidates.append(str(data[key]))
                            except Exception:
                                pass
                    joined = "\n".join(t.strip() for t in text_candidates if t.strip()).strip()
                    if joined:
                        return joined
                    return "\n".join(line for line in output.splitlines() if line.strip() and not line.startswith("Stage:"))
            return transcribe

        raise RuntimeError(f"Unknown runtime: {runtime_name}. Supported: canary_mlx, mlx_whisper, mlx_audio_cli")

    print(f"Stage: STT preflight; files={len(files)} profile={profile_id} runtime={runtime}", flush=True)
    for p in files:
        if not p.exists():
            raise FileNotFoundError(f"audio file not found: {p}")
    if output_dir is not None:
        output_dir.mkdir(parents=True, exist_ok=True)

    transcribe_chunk = make_transcriber(runtime, model_id)

    ok = 0
    failed = 0
    for index, audio_path in enumerate(files, 1):
        emit("file_started", path=str(audio_path), index=index, total=len(files))
        print(f"Stage: transcribe [{index}/{len(files)}] {audio_path}", flush=True)
        txt_path, json_path = output_paths(audio_path)
        try:
            parts = []
            chunk_records = []
            with tempfile.TemporaryDirectory(prefix="canary-transcriber-") as tmp:
                chunks, duration, effective_chunk = make_wav_chunks(audio_path, Path(tmp), chunk_duration)
                for chunk_index, chunk_start, chunk_path in chunks:
                    print(f"Stage: STT chunk {chunk_index + 1}/{len(chunks)} start={chunk_start:.1f}s runtime={runtime}", flush=True)
                    chunk_text = transcribe_chunk(chunk_path)
                    chunk_text = chunk_text.strip()
                    if chunk_text:
                        parts.append(chunk_text)
                    chunk_records.append({
                        "index": chunk_index,
                        "start": chunk_start,
                        "path": str(chunk_path.name),
                        "chars": len(chunk_text),
                        "text": chunk_text,
                    })

            text = "\n".join(parts).strip()
            txt_path.write_text(text, encoding="utf-8")
            payload = {
                "audio": str(audio_path),
                "profile": profile_id,
                "runtime": runtime,
                "model": model_id,
                "language": language,
                "timestamps": timestamps,
                "manual_chunking": True,
                "chunk_duration": chunk_duration,
                "overlap_duration": 0,
                "text": text,
                "chunks": chunk_records,
            }
            json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
            ok += 1
            emit("file_done", path=str(audio_path), txt=str(txt_path), json=str(json_path), chars=len(text))
            print(f"Transcript saved: {txt_path} (chars={len(text)})", flush=True)
            if len(text.strip()) == 0:
                print("Warning: selected STT profile returned empty text for this file. Check runtime dependencies, language/audio format, or try another profile.", flush=True)
        except RuntimeError as e:
            msg = str(e)
            if "Insufficient Memory" in msg or "OutOfMemory" in msg or "out of memory" in msg.lower():
                msg = "MLX runtime ran out of Metal memory. Try smaller Chunk sec, e.g. 15 or 10. Original: " + msg
            failed += 1
            emit("file_failed", path=str(audio_path), error=msg)
            print(f"ERROR transcribing {audio_path}: {msg}", flush=True)
        except Exception as e:
            failed += 1
            emit("file_failed", path=str(audio_path), error=str(e))
            print(f"ERROR transcribing {audio_path}: {e}", flush=True)
            traceback.print_exc()

    emit("batch_done", ok=ok, failed=failed, total=len(files))
    print(f"Batch complete: ok={ok}, failed={failed}, total={len(files)}", flush=True)
    raise SystemExit(0 if failed == 0 else 2)
except KeyboardInterrupt:
    print("Interrupted", flush=True)
    raise
except Exception as e:
    print(f"FATAL: {e}", flush=True)
    traceback.print_exc()
    raise SystemExit(1)
"""#

        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-u", "-c", script, configURL.path]
        proc.standardOutput = pipe
        proc.standardError = pipe
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        let guiSafePath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = env["PATH"], !existingPath.isEmpty {
            env["PATH"] = guiSafePath + ":" + existingPath
        } else {
            env["PATH"] = guiSafePath
        }
        proc.environment = env

        let batchHeader = """

=== MLX batch transcription ===
Python: \(pythonPath)
Profile: \(config.profileID)
Runtime: \(config.runtime)
Model: \(config.model)
Language: \(config.language)
Chunk duration: \(config.chunkDuration.map { String($0) } ?? "off")
Files: \(config.files.count)
Output: \(config.writeNextToSource ? "next to source files" : (config.outputDir ?? ""))
PATH: \(env["PATH"] ?? "")
Persistent log: \(persistentLogPath())

"""
        logs += batchHeader
        appendPersistentLog(batchHeader)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                appendProcessOutput(chunk)
            }
        }

        proc.terminationHandler = { finished in
            DispatchQueue.main.async {
                self.isRunning = false
                self.process = nil
                if let currentConfigPath {
                    try? FileManager.default.removeItem(atPath: currentConfigPath)
                    self.currentConfigPath = nil
                }
                if finished.terminationStatus == 0 {
                    self.logs += "\n✅ Batch completed successfully.\n"
                    self.appendPersistentLog("\n✅ Batch completed successfully.\n")
                } else if finished.terminationStatus == 15 {
                    self.logs += "\n⏹️ Batch stopped by user.\n"
                    self.appendPersistentLog("\n⏹️ Batch stopped by user.\n")
                } else {
                    let reason = String(describing: finished.terminationReason)
                    let message = "\n⚠️ Batch completed with errors (code \(finished.terminationStatus), reason \(reason)).\n"
                    self.logs += message
                    self.appendPersistentLog(message)
                }
                let exitLine = "---\nExit code: \(finished.terminationStatus)\n"
                self.logs += exitLine
                self.appendPersistentLog(exitLine)
            }
            pipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            isRunning = true
            try proc.run()
            process = proc
            logs += "Started PID: \(proc.processIdentifier)\n"
        } catch {
            isRunning = false
            process = nil
            logs += "❌ Cannot start Python: \(error.localizedDescription)\n"
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func stopBatch() {
        guard let process else { return }
        logs += "\nОстанавливаю PID: \(process.processIdentifier)...\n"
        process.terminate()
    }

    private func appendProcessOutput(_ chunk: String) {
        for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.hasPrefix("CANARY_EVENT ") {
                handleEventLine(String(text.dropFirst("CANARY_EVENT ".count)))
            } else if !text.isEmpty {
                logs += text + "\n"
                appendPersistentLog(text + "\n")
            }
        }
    }

    private func handleEventLine(_ jsonText: String) {
        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = payload["kind"] as? String else {
            logs += "CANARY_EVENT parse failed: \(jsonText)\n"
            return
        }

        switch kind {
        case "file_started":
            if let path = payload["path"] as? String {
                updateStatus(path: path, status: "running")
            }
        case "file_done":
            if let path = payload["path"] as? String {
                updateStatus(path: path, status: "done")
            }
            let txt = payload["txt"] as? String ?? ""
            let chars = payload["chars"] as? Int ?? 0
            logs += "✅ Done: \(txt) (chars=\(chars))\n"
        case "file_failed":
            if let path = payload["path"] as? String {
                updateStatus(path: path, status: "failed")
            }
            logs += "❌ Failed: \(payload["path"] ?? "") — \(payload["error"] ?? "unknown")\n"
        case "batch_done":
            logs += "Batch summary: ok=\(payload["ok"] ?? 0), failed=\(payload["failed"] ?? 0), total=\(payload["total"] ?? 0)\n"
        default:
            logs += "Event: \(jsonText)\n"
        }
    }

    private func updateStatus(path: String, status: String) {
        if let idx = files.firstIndex(where: { $0.path == path }) {
            files[idx].status = status
        }
    }

    private func openOutputLocation() {
        if writeNextToSource {
            if let first = files.first {
                NSWorkspace.shared.open(URL(fileURLWithPath: first.path).deletingLastPathComponent())
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents"))
            }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: normalizeUserPath(outputFolder), isDirectory: true))
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "done": return .green
        case "running": return .blue
        case "failed": return .red
        default: return .secondary
        }
    }

    private func normalizeUserPath(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\\ ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasPrefix("file://"), let url = URL(string: s) {
            return url.path
        }
        if s.hasPrefix("~/") {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(String(s.dropFirst(2)))
                .path
        }
        if !s.hasPrefix("/"), let slash = s.firstIndex(of: "/") {
            s = String(s[slash...])
        }
        return s
    }

    private func bringAppToFront() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            guard let window = NSApp.windows.first else { return }
            let minimumSize = NSSize(width: 1080, height: 820)
            let preferredSize = NSSize(width: 1120, height: 900)
            window.minSize = minimumSize
            var frame = window.frame
            if frame.width < minimumSize.width || frame.height < minimumSize.height {
                let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
                let newWidth = min(max(frame.width, preferredSize.width), screenFrame.width)
                let newHeight = min(max(frame.height, preferredSize.height), screenFrame.height)
                frame.size = NSSize(width: newWidth, height: newHeight)
                frame.origin.x = screenFrame.midX - newWidth / 2
                frame.origin.y = screenFrame.midY - newHeight / 2
                window.setFrame(frame, display: true, animate: false)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func persistentLogPath() -> String {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/CanaryTranscripts/canary-transcriber.log")
            .path
    }

    private func appendPersistentLog(_ text: String) {
        let url = URL(fileURLWithPath: persistentLogPath())
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data(text.utf8)
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Do not break the UI if filesystem logging fails.
        }
    }

    private static func defaultCanaryPythonPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["CANARY_MLX_PYTHON_BIN"], !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("venvs/canary-mlx/bin/python").path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("venvs/canary-mlx/bin/python").path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".venvs/canary-mlx/bin/python").path,
            URL(fileURLWithPath: cwd).appendingPathComponent(".venv-canary/bin/python").path,
            URL(fileURLWithPath: cwd).appendingPathComponent(".venv/bin/python").path
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? candidates[0]
    }

    // MARK: - Dependency checks

    private func statusDot(_ status: DependencyStatus) -> some View {
        Circle()
            .fill(statusDotColor(status))
            .frame(width: 10, height: 10)
    }

    private func statusDotColor(_ status: DependencyStatus) -> Color {
        switch status {
        case .present, .downloaded: return .green
        case .checking, .downloading, .updatable: return .orange
        case .missing: return .red
        case .unknown: return .gray
        }
    }

    private func ffmpegStatusLabel(_ status: DependencyStatus) -> String {
        switch status {
        case .unknown, .checking: return "Checking..."
        case .present: return "Installed"
        case .missing: return "Not found"
        case .downloaded, .downloading: return ""
        case .updatable: return ""
        }
    }

    private func pythonStatusLabel(_ status: DependencyStatus) -> String {
        switch status {
        case .unknown, .checking: return "Checking..."
        case .present: return "Ready"
        case .missing: return "Not found — setup venv"
        case .downloaded, .downloading: return ""
        case .updatable: return ""
        }
    }

    private func checkDependencies() {
        ffmpegStatus = .checking
        pythonStatus = .checking

        DispatchQueue.global(qos: .userInitiated).async {
            // Check ffmpeg
            let ffCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            let ffFound = ffCandidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
            DispatchQueue.main.async { self.ffmpegStatus = ffFound ? .present : .missing }

            // Check Python venv
            let py = self.pythonPath
            if FileManager.default.isExecutableFile(atPath: py) {
                let runtime = self.runtime
                let importCheck: String
                switch runtime {
                case "mlx_audio_cli":
                    importCheck = "import mlx_audio"
                case "mlx_whisper":
                    importCheck = "import mlx_whisper"
                case "canary_mlx":
                    importCheck = "import canary_mlx"
                default:
                    importCheck = "import mlx_audio"
                }
                let task = Process()
                task.executableURL = URL(fileURLWithPath: py)
                task.arguments = ["-c", importCheck]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                    task.waitUntilExit()
                    DispatchQueue.main.async { self.pythonStatus = task.terminationStatus == 0 ? .present : .missing }
                } catch {
                    DispatchQueue.main.async { self.pythonStatus = .missing }
                }
            } else {
                DispatchQueue.main.async { self.pythonStatus = .missing }
            }

            // Check if the selected model is cached
            self.checkModelCache()
        }
    }

    private func checkModelCache() {
        let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedProfile.model : model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else { return }

        let py = pythonPath
        guard FileManager.default.isExecutableFile(atPath: py) else { return }

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: py)
        task.arguments = ["-c", """
from pathlib import Path
import sys
model_id = sys.argv[1]
cache = Path.home() / ".cache" / "huggingface" / "hub"
model_dir = cache / ("models--" + model_id.replace("/", "--"))
if not model_dir.exists():
    print("ABSENT")
    sys.exit(0)
found = list(model_dir.rglob("*.safetensors")) + list(model_dir.rglob("*.bin")) + list(model_dir.rglob("*.msgpack"))
if not found:
    print("ABSENT")
    sys.exit(0)
# Check if remote has a newer commit
ref_file = model_dir / "refs" / "main"
if ref_file.exists():
    print("CACHED")
else:
    print("CACHED")
""", modelID]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                self.modelDownloadStatus[modelID] = output == "CACHED" ? .downloaded : .missing
            }
        } catch {
            DispatchQueue.main.async { self.modelDownloadStatus[modelID] = .missing }
        }
    }

    private func installFFmpeg() {
        guard !isInstallingFFmpeg else { return }
        isInstallingFFmpeg = true
        logs += "Stage: installing ffmpeg via Homebrew...\n"
        appendPersistentLog("Stage: installing ffmpeg via Homebrew...\n")

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
            task.arguments = ["install", "ffmpeg"]
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self.logs += output + "\n"
                    self.appendPersistentLog(output + "\n")
                    if task.terminationStatus == 0 {
                        self.ffmpegStatus = .present
                        self.logs += "✅ ffmpeg установлен.\n"
                    } else {
                        self.logs += "❌ ffmpeg install failed (code \(task.terminationStatus)). Установи вручную: brew install ffmpeg\n"
                    }
                    self.isInstallingFFmpeg = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logs += "❌ Не удалось запустить brew: \(error.localizedDescription)\n"
                    self.logs += "   Установи ffmpeg вручную: brew install ffmpeg\n"
                    self.isInstallingFFmpeg = false
                }
            }
        }
    }

    private func setupPythonEnvironment() {
        guard !isSettingUpPython else { return }
        isSettingUpPython = true
        let venvDir = NSHomeDirectory() + "/venvs/canary-mlx"
        let pythonBin = "/usr/bin/python3"
        logs += "Stage: creating venv at \(venvDir)...\n"
        appendPersistentLog("Stage: creating venv at \(venvDir)...\n")

        DispatchQueue.global(qos: .userInitiated).async {
            let createTask = Process()
            let createPipe = Pipe()
            createTask.executableURL = URL(fileURLWithPath: pythonBin)
            createTask.arguments = ["-m", "venv", venvDir]
            createTask.standardOutput = createPipe
            createTask.standardError = createPipe
            do {
                try createTask.run()
                createTask.waitUntilExit()
                let output = String(data: createPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async { self.logs += output + "\n" }

                guard createTask.terminationStatus == 0 else {
                    DispatchQueue.main.async {
                        self.logs += "❌ Не удалось создать venv. Создай вручную:\n   python3 -m venv \(venvDir)\n"
                        self.isSettingUpPython = false
                    }
                    return
                }

                let venvPython = venvDir + "/bin/python"

                // Install packages
                let packages = "\"mlx-audio[stt]\" mlx-whisper canary-mlx huggingface_hub"
                let installTask = Process()
                let installPipe = Pipe()
                installTask.executableURL = URL(fileURLWithPath: venvPython)
                installTask.arguments = ["-m", "pip", "install", packages, "--quiet"]
                installTask.standardOutput = installPipe
                installTask.standardError = installPipe

                DispatchQueue.main.async { self.logs += "Stage: installing packages... (может занять несколько минут)\n" }
                try installTask.run()
                installTask.waitUntilExit()
                let pipOutput = String(data: installPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    if installTask.terminationStatus == 0 {
                        self.pythonPath = venvPython
                        self.pythonStatus = .present
                        self.logs += "✅ Venv создан и пакеты установлены: \(venvPython)\n"
                    } else {
                        self.logs += pipOutput + "\n"
                        self.logs += "❌ pip install failed. Установи пакеты вручную:\n   \(venvPython) -m pip install mlx-audio mlx-whisper canary-mlx huggingface-hub\n"
                    }
                    self.isSettingUpPython = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logs += "❌ Ошибка: \(error.localizedDescription). Создай venv вручную.\n"
                    self.isSettingUpPython = false
                }
            }
        }
    }

    private func downloadModel(_ modelID: String) {
        guard !isDownloadingModel, !modelID.isEmpty else { return }
        isDownloadingModel = true
        modelDownloadStatus[modelID] = .downloading
        logs += "Stage: downloading model \(modelID) via huggingface_hub...\n"
        appendPersistentLog("Stage: downloading model \(modelID) via huggingface_hub...\n")

        let py = pythonPath
        guard FileManager.default.isExecutableFile(atPath: py) else {
            logs += "❌ Python venv не найден. Сначала настрой окружение.\n"
            modelDownloadStatus[modelID] = .missing
            isDownloadingModel = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: py)
            task.arguments = ["-c", """
import sys
try:
    from huggingface_hub import snapshot_download
    print("Stage: downloading " + \(modelID.debugDescription) + " to HuggingFace cache...", flush=True)
    snapshot_download(\(modelID.debugDescription), resume_download=True, local_files_only=False)
    print("DONE", flush=True)
except KeyboardInterrupt:
    print("INTERRUPTED", flush=True)
    sys.exit(1)
except Exception as e:
    print(f"FAILED: {e}", flush=True)
    sys.exit(1)
"""]
            task.standardOutput = Pipe()
            task.standardError = task.standardOutput
            do {
                try task.run()
                task.waitUntilExit()
                if let pipe = task.standardOutput as? Pipe {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    DispatchQueue.main.async {
                        self.logs += output
                        self.appendPersistentLog(output)
                        if task.terminationStatus == 0 && output.contains("DONE") {
                            self.modelDownloadStatus[modelID] = .downloaded
                            self.logs += "✅ Модель \(modelID) загружена.\n"
                        } else {
                            self.modelDownloadStatus[modelID] = .missing
                        }
                        self.isDownloadingModel = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.modelDownloadStatus[modelID] = .missing
                        self.isDownloadingModel = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.logs += "❌ Ошибка загрузки модели: \(error.localizedDescription)\n"
                    self.modelDownloadStatus[modelID] = .missing
                    self.isDownloadingModel = false
                }
            }
        }
    }
}
