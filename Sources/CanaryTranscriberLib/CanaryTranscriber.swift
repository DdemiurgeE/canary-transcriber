import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import AudioToolbox
import ScreenCaptureKit
import CanaryTranscriberCore

struct AudioFileItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    var status: String = "pending"

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AudioFileItem, rhs: AudioFileItem) -> Bool { lhs.id == rhs.id }
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
            CaptureFileValidator.isUsableAudioFile(url)
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

            if CaptureFileValidator.isUsableAudioFile(url), recordedFrames >= CaptureFileValidator.minimumMicrophoneFrames {
                completion(.success(url))
            } else {
                completion(.failure(NSError(domain: "CanaryAppAudioCapture", code: 18, userInfo: [NSLocalizedDescriptionKey: CaptureDiagnostic.emptyOrTinyFile(url).description])))
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

public struct ContentView: View {
    @StateObject private var viewModel: TranscriptionViewModel

    public init() {
        _viewModel = StateObject(wrappedValue: TranscriptionViewModel())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(viewModel: viewModel)
            DependencyPanelView(viewModel: viewModel)
            SettingsView(viewModel: viewModel)
            AppAudioCaptureView(viewModel: viewModel)
            FilesView(viewModel: viewModel)
            ControlsPanelView(viewModel: viewModel)
            LogView(viewModel: viewModel)
        }
        .padding(16)
        .frame(minWidth: 1080, idealWidth: 1120, minHeight: 820, idealHeight: 900)
        .onAppear {
            viewModel.bringAppToFront()
            viewModel.refreshCaptureApps()
            viewModel.refreshMicrophones()
            viewModel.checkDependencies()
        }
    }
}
