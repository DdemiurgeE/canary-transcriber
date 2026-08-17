import SwiftUI
import Foundation
import AVFoundation
import ScreenCaptureKit
import CanaryTranscriberCore

final class AppAudioCaptureController: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var isRecording = false
    /// True from the moment Stop is pressed until the mixed file is ready — flushing the
    /// writers and mixing app+mic through ffmpeg can take a while for long recordings, and
    /// without this the app looks idle/like nothing was recorded during that gap.
    @Published private(set) var isFinishing = false

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
                throw NSError(domain: "CanaryAppAudioCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter could not add AAC audio input for \(url.lastPathComponent)."])
            }
            writer.add(input)
            guard writer.startWriting() else {
                throw writer.error ?? NSError(domain: "CanaryAppAudioCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter did not start for \(url.lastPathComponent)."])
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
                    completion(.failure(NSError(domain: "CanaryAppAudioCapture", code: 5, userInfo: [NSLocalizedDescriptionKey: "File \(self.url.lastPathComponent) is empty or too small."])))
                }
            }
        }

        static func isUsableAudioFile(_ url: URL?) -> Bool {
            CaptureFileValidator.isUsableAudioFile(url)
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
                throw NSError(domain: "CanaryAppAudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "ScreenCaptureKit returned no display for the content filter."])
            }
            guard let app = content.applications.first(where: { $0.processID == target.processID }) else {
                throw NSError(domain: "CanaryAppAudioCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Application was not found: \(target.title). Refresh the application list."])
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
            await MainActor.run {
                cleanupAfterFailure()
                onLog("❌ Failed to start app audio capture: \(error.localizedDescription)\n")
                onFinished(.failure(error))
            }
        }
    }

    func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return
        }
        guard isRecording || stream != nil || appAudioWriter != nil || microphoneRecorder != nil else { return }
        let streamToStop = stream
        onLog?("⏹️ Stopping app/mic audio capture...\n")
        isRecording = false
        isFinishing = true
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
                                let out = try AudioMixer.mixAppAndMicrophone(appURL: appURL, micURL: micURL, outputURL: mixedURL ?? appURL, onLog: self.onLog)
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
                    self.isFinishing = false
                    self.onFinished?(finalResult)
                }
            }
        }
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
        isFinishing = false
    }
}
