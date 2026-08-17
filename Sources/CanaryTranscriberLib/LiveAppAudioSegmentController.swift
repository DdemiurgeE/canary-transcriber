import Foundation
import AVFoundation
import ScreenCaptureKit
import CanaryTranscriberCore

/// ScreenCaptureKit source that emits closed, independently readable AAC segments.
/// The existing AppAudioCaptureController remains the full-session capture path.
final class LiveAppAudioSegmentController: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var isCapturing = false
    @Published private(set) var isFinishing = false

    private final class SegmentWriter {
        let url: URL
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private var started = false

        init(url: URL) throws {
            self.url = url
            writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw NSError(domain: "CanaryLiveCapture", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not add AAC input for live segment."
                ])
            }
            writer.add(input)
            guard writer.startWriting() else {
                throw writer.error ?? NSError(domain: "CanaryLiveCapture", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Could not start live segment writer."
                ])
            }
        }

        func append(_ sampleBuffer: CMSampleBuffer) {
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            if !started {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                started = true
            }
            guard input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        }

        func finish(completion: @escaping (Result<URL, Error>) -> Void) {
            input.markAsFinished()
            writer.finishWriting {
                if let error = self.writer.error {
                    completion(.failure(error))
                } else if CaptureFileValidator.isUsableAudioFile(self.url) {
                    completion(.success(self.url))
                } else {
                    completion(.failure(NSError(domain: "CanaryLiveCapture", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Live segment is empty or too small: \(self.url.lastPathComponent)"
                    ])))
                }
            }
        }
    }

    private let sampleQueue = DispatchQueue(label: "canary.live-app-capture.samples")
    private var stream: SCStream?
    private var writer: SegmentWriter?
    private var segmentIndex = 0
    private var segmentStart: CMTime?
    private var lastSampleTime: CMTime?
    private var target: CaptureAppTarget?
    private var outputDirectory: URL?
    private var segmentDuration: TimeInterval = 5
    private var sessionID = UUID()
    private var onLog: ((String) -> Void)?
    private var onSegmentReady: ((Int, URL, TimeInterval) -> Void)?
    private var onFinished: ((Result<Void, Error>) -> Void)?
    private var includeMicrophone = false
    private var microphoneDeviceID: String?
    private var microphoneEngine: AVAudioEngine?
    private var microphoneFile: AVAudioFile?
    private var microphoneFormat: AVAudioFormat?
    private var microphoneFrames: AVAudioFramePosition = 0
    private var microphoneLock = NSLock()

    func start(
        target: CaptureAppTarget,
        segmentDuration: TimeInterval = 5,
        includeMicrophone: Bool = false,
        microphoneDeviceID: String? = nil,
        outputDirectory: URL,
        onLog: @escaping (String) -> Void,
        onSegmentReady: @escaping (Int, URL, TimeInterval) -> Void,
        onFinished: @escaping (Result<Void, Error>) -> Void
    ) async {
        guard !isCapturing, !isFinishing else { return }
        let generation = UUID()
        sessionID = generation
        self.target = target
        self.outputDirectory = outputDirectory
        self.segmentDuration = max(1, segmentDuration)
        self.onLog = onLog
        self.onSegmentReady = onSegmentReady
        self.onFinished = onFinished
        self.includeMicrophone = includeMicrophone
        self.microphoneDeviceID = microphoneDeviceID

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                throw NSError(domain: "CanaryLiveCapture", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "ScreenCaptureKit returned no display."
                ])
            }
            guard let app = content.applications.first(where: { $0.processID == target.processID }) else {
                throw NSError(domain: "CanaryLiveCapture", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: "Application was not found: \(target.title). Refresh the application list."
                ])
            }

            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            if includeMicrophone {
                try startMicrophone(outputDirectory: outputDirectory)
            }
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
            self.stream = stream
            try await stream.startCapture()

            await MainActor.run {
                guard self.sessionID == generation else { return }
                self.isCapturing = true
                onLog("Live capture started: \(target.title), \(Int(self.segmentDuration))s segments.\n")
            }
        } catch {
            await MainActor.run {
                cleanup()
                onLog("Live capture failed to start: \(error.localizedDescription)\n")
                onFinished(.failure(error))
            }
        }
    }

    func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return
        }
        guard isCapturing || stream != nil || writer != nil else { return }
        isCapturing = false
        isFinishing = true
        onLog?("Stopping live capture and closing the final segment...\n")
        let streamToStop = stream
        Task {
            if let streamToStop { try? await streamToStop.stopCapture() }
            sampleQueue.async { [weak self] in self?.finishCurrentSegmentAndStop() }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        sampleQueue.async { [weak self] in
            self?.consume(sampleBuffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onLog?("Live ScreenCaptureKit stream stopped: \(error.localizedDescription)\n")
        stop()
    }

    private func consume(_ sampleBuffer: CMSampleBuffer) {
        guard isCapturing else { return }
        do {
            if writer == nil {
                writer = try makeWriter()
                segmentStart = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            }
            writer?.append(sampleBuffer)
            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            lastSampleTime = sampleTime
            guard let start = segmentStart else { return }
            let elapsed = CMTimeGetSeconds(sampleTime - start)
            if elapsed >= segmentDuration {
                rotateSegment(duration: elapsed)
            }
        } catch {
            onLog?("Live segment writer failed: \(error.localizedDescription)\n")
            stop()
        }
    }

    private func rotateSegment(duration: TimeInterval) {
        guard let current = writer else { return }
        writer = nil
        segmentStart = nil
        let index = segmentIndex
        segmentIndex += 1
        let microphoneURL = includeMicrophone ? closeMicrophoneSegment() : nil
        if includeMicrophone, let outputDirectory {
            try? openMicrophoneSegment(outputDirectory: outputDirectory)
        }
        current.finish { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.mixIfNeeded(appURL: url, microphoneURL: microphoneURL, index: index, duration: duration)
                self.onLog?("Live segment ready: \(url.lastPathComponent)\n")
            case .failure(let error):
                self.onLog?("Live segment rejected: \(error.localizedDescription)\n")
            }
        }
    }

    private func finishCurrentSegmentAndStop() {
        guard let current = writer else {
            finish(.success(()))
            return
        }
        writer = nil
        let index = segmentIndex
        segmentIndex += 1
        let microphoneURL = includeMicrophone ? stopMicrophone() : nil
        let duration: TimeInterval
        if let start = segmentStart, let last = lastSampleTime {
            duration = max(0, CMTimeGetSeconds(last - start))
        } else {
            duration = segmentDuration
        }
        current.finish { [weak self] result in
            guard let self else { return }
            if case .success(let url) = result {
                self.mixIfNeeded(appURL: url, microphoneURL: microphoneURL, index: index, duration: duration)
            }
            self.finish(result.map { _ in () })
        }
    }

    private func startMicrophone(outputDirectory: URL) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let microphoneDeviceID,
           let deviceID = MicrophoneEngineRecorder.audioDeviceID(matchingUID: microphoneDeviceID),
           let audioUnit = input.audioUnit {
            var mutableDeviceID = deviceID
            let status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &mutableDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else {
                throw NSError(domain: "CanaryLiveCapture", code: 20, userInfo: [NSLocalizedDescriptionKey: "Could not select microphone \(microphoneDeviceID) (status \(status))."])
            }
        } else if microphoneDeviceID != nil {
            throw NSError(domain: "CanaryLiveCapture", code: 21, userInfo: [NSLocalizedDescriptionKey: "Could not find the selected microphone."])
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "CanaryLiveCapture", code: 22, userInfo: [NSLocalizedDescriptionKey: "AVAudioEngine returned an empty microphone format."])
        }
        self.microphoneEngine = engine
        self.microphoneFormat = format
        self.microphoneFrames = 0
        try openMicrophoneSegment(outputDirectory: outputDirectory)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, buffer.frameLength > 0 else { return }
            self.microphoneLock.lock()
            defer { self.microphoneLock.unlock() }
            do {
                try self.microphoneFile?.write(from: buffer)
                self.microphoneFrames += AVAudioFramePosition(buffer.frameLength)
            } catch {
                self.onLog?("Live microphone segment write failed: \(error.localizedDescription)\\n")
            }
        }
        engine.prepare()
        try engine.start()
        onLog?("Live microphone capture enabled.\\n")
    }

    private func openMicrophoneSegment(outputDirectory: URL) throws {
        guard let microphoneFormat, let target else { return }
        let safeName = target.name.replacingOccurrences(of: "[^A-Za-z0-9А-Яа-я._-]+", with: "-", options: .regularExpression)
        let filename = "live-mic-\(safeName)-\(Int(Date().timeIntervalSince1970))-\(segmentIndex).caf"
        let url = outputDirectory.appendingPathComponent(filename)
        microphoneLock.lock()
        defer { microphoneLock.unlock() }
        microphoneFile = try AVAudioFile(forWriting: url, settings: microphoneFormat.settings)
        microphoneFrames = 0
    }

    private func closeMicrophoneSegment() -> URL? {
        microphoneLock.lock()
        defer { microphoneLock.unlock() }
        let url = microphoneFile?.url
        microphoneFile = nil
        guard let url, CaptureFileValidator.isUsableAudioFile(url), microphoneFrames >= CaptureFileValidator.minimumMicrophoneFrames else {
            return nil
        }
        return url
    }

    private func stopMicrophone() -> URL? {
        if let engine = microphoneEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        microphoneEngine = nil
        return closeMicrophoneSegment()
    }

    private func mixIfNeeded(appURL: URL, microphoneURL: URL?, index: Int, duration: TimeInterval) {
        guard includeMicrophone, let microphoneURL, let outputDirectory, let target else {
            onSegmentReady?(index, appURL, duration)
            return
        }
        let safeName = target.name.replacingOccurrences(of: "[^A-Za-z0-9А-Яа-я._-]+", with: "-", options: .regularExpression)
        let output = outputDirectory.appendingPathComponent("live-mixed-\(safeName)-\(Int(Date().timeIntervalSince1970))-\(index).m4a")
        do {
            let mixed = try AudioMixer.mixAppAndMicrophone(appURL: appURL, micURL: microphoneURL, outputURL: output, onLog: onLog)
            onSegmentReady?(index, mixed, duration)
        } catch {
            onLog?("Live app+microphone mix failed: \(error.localizedDescription)\\n")
        }
    }

    private func makeWriter() throws -> SegmentWriter {
        guard let outputDirectory, let target else {
            throw NSError(domain: "CanaryLiveCapture", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "Live capture output is not configured."
            ])
        }
        let safeName = target.name.replacingOccurrences(of: "[^A-Za-z0-9А-Яа-я._-]+", with: "-", options: .regularExpression)
        let filename = "live-app-\(safeName)-\(Int(Date().timeIntervalSince1970))-\(segmentIndex).m4a"
        return try SegmentWriter(url: outputDirectory.appendingPathComponent(filename))
    }

    private func finish(_ result: Result<Void, Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cleanup()
            self.isFinishing = false
            self.onFinished?(result)
        }
    }

    private func cleanup() {
        if let microphoneEngine {
            microphoneEngine.inputNode.removeTap(onBus: 0)
            microphoneEngine.stop()
        }
        microphoneEngine = nil
        microphoneLock.lock()
        microphoneFile = nil
        microphoneLock.unlock()
        microphoneFormat = nil
        microphoneFrames = 0
        includeMicrophone = false
        microphoneDeviceID = nil
        stream = nil
        writer = nil
        segmentStart = nil
        lastSampleTime = nil
        segmentIndex = 0
        target = nil
        outputDirectory = nil
        isCapturing = false
    }
}
