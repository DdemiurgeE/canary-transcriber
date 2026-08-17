import Foundation
import CanaryTranscriberCore

extension TranscriptionViewModel {
    func startLiveCapture() {
        guard let target = selectedCaptureApp else {
            logs += "⚠️ Select an application first.\n"
            return
        }
        guard !liveAppCapture.isCapturing, !liveAppCapture.isFinishing else { return }
        let outputDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/CanaryTranscripts/LiveCaptures", isDirectory: true)
        let config = LiveCaptureConfig(
            windowDuration: 5,
            overlapDuration: 0,
            profileID: selectedProfileID,
            runtime: runtime,
            model: model,
            language: language,
            includeMicrophone: captureMicrophone,
            outputDirectory: outputDirectory.path
        )
        do {
            _ = try config.validated()
        } catch {
            logs += "❌ Invalid Live Capture configuration: \(error.localizedDescription)\n"
            return
        }

        liveTranscriptAccumulator = LiveTranscriptAccumulator()
        liveTranscript = ""
        liveExportBaseURL = outputDirectory.appendingPathComponent("live-\(Int(Date().timeIntervalSince1970)).canary")
        liveTranscriptionWorker.stop()
        liveTranscriptionWorker = LiveTranscriptionWorker()
        isLiveTranscribing = true
        logs += "Stage: starting Live Capture with 5-second segments.\n"

        Task {
            await liveAppCapture.start(
                target: target,
                segmentDuration: config.windowDuration,
                includeMicrophone: config.includeMicrophone,
                microphoneDeviceID: selectedMicrophoneID,
                outputDirectory: outputDirectory,
                onLog: { [weak self] text in
                    DispatchQueue.main.async {
                        self?.logs += text
                        self?.appendPersistentLog(text)
                    }
                },
                onSegmentReady: { [weak self] index, url, duration in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        let start = Double(index) * config.windowDuration
                        let stage = "Stage: transcribing live segment \(index + 1)\n"
                        self.logs += stage
                        self.appendPersistentLog(stage)
                        self.liveTranscriptionWorker.submit(
                            segmentURL: url,
                            index: index,
                            start: start,
                            end: start + max(0, duration),
                            config: config
                        ) { [weak self] result in
                            DispatchQueue.main.async {
                                guard let self else { return }
                                switch result {
                                case .success(let segment):
                                    if self.liveTranscriptAccumulator.append(segment) {
                                        self.liveTranscript = self.liveTranscriptAccumulator.renderTimestamped()
                                        self.persistLiveTranscript(config: config)
                                    }
                                case .failure(let error):
                                    let message = "⚠️ Live segment transcription failed: \(error.localizedDescription)\n"
                                    self.logs += message
                                    self.appendPersistentLog(message)
                                }
                            }
                        }
                    }
                },
                onFinished: { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.liveTranscriptionWorker.drain {
                            self.persistLiveTranscript(config: config)
                            self.liveTranscriptionWorker.stop()
                            self.isLiveTranscribing = false
                            switch result {
                            case .success:
                                self.logs += "Live Capture stopped.\n"
                            case .failure(let error):
                                self.logs += "❌ Live Capture failed: \(error.localizedDescription)\n"
                            }
                        }
                    }
                }
            )
        }
    }

    private func persistLiveTranscript(config: LiveCaptureConfig) {
        guard let base = liveExportBaseURL else { return }
        do {
            try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            let textURL = base.appendingPathExtension("txt")
            let jsonURL = base.appendingPathExtension("json")
            let markdownURL = base.appendingPathExtension("md")
            try liveTranscriptAccumulator.renderTimestamped().write(to: textURL, atomically: true, encoding: .utf8)
            let payload: [String: Any] = [
                "live_capture": true,
                "profile": config.profileID,
                "runtime": config.runtime,
                "model": config.model,
                "language": config.language,
                "include_microphone": config.includeMicrophone,
                "segments": liveTranscriptAccumulator.segments.map {
                    ["index": $0.index, "start": $0.start, "end": $0.end, "text": $0.text]
                },
                "text": liveTranscriptAccumulator.text
            ]
            let json = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            try json.write(to: jsonURL, options: Data.WritingOptions.atomic)
            let frontMatter = TranscriptionFrontMatter(
                source: base.lastPathComponent,
                profile: config.profileID,
                runtime: config.runtime,
                model: config.model,
                language: config.language,
                date: ISO8601DateFormatter().string(from: Date())
            ).render()
            let markdown = frontMatter + "\n# Live Transcript\n\n" + liveTranscriptAccumulator.renderTimestamped() + "\n"
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
        } catch {
            logs += "⚠️ Could not persist live transcript: \(error.localizedDescription)\n"
        }
    }

    func stopLiveCapture() {
        liveAppCapture.stop()
    }
}
