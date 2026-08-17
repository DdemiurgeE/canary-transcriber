import Foundation
import CanaryTranscriberCore

final class LiveTranscriptionWorker {
    private let runner = ProcessRunner()
    private let queue = DispatchQueue(label: "canary.live-transcription.serial")
    private var task: (any ProcessRunningTask)?
    private var stopped = false

    func drain(completion: @escaping () -> Void) {
        queue.async {
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            task?.terminate()
            task = nil
        }
    }

    func submit(
        segmentURL: URL,
        index: Int,
        start: TimeInterval,
        end: TimeInterval,
        config: LiveCaptureConfig,
        completion: @escaping (Result<LiveTranscriptSegment, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            do {
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("canary-live-\(UUID().uuidString).txt")
                defer { try? FileManager.default.removeItem(at: outputURL) }

                let request = try Self.makeRequest(segmentURL: segmentURL, outputURL: outputURL, config: config)
                let semaphore = DispatchSemaphore(value: 0)
                var result: ProcessResult?
                var outputError: Error?
                self.task = try self.runner.start(request, onOutput: { event in
                    if event.channel == .stderr, !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        outputError = NSError(domain: "CanaryLiveTranscription", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: event.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        ])
                    }
                }, onTermination: { termination in
                    result = termination
                    semaphore.signal()
                })
                semaphore.wait()
                self.task = nil
                guard !self.stopped else { return }
                if let outputError { throw outputError }
                guard result?.terminationStatus == 0 else {
                    throw NSError(domain: "CanaryLiveTranscription", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Live STT process failed for segment \(index)."
                    ])
                }
                let text = try String(contentsOf: outputURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let segment = LiveTranscriptSegment(index: index, start: start, end: end, text: text)
                DispatchQueue.main.async { completion(.success(segment)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func makeRequest(
        segmentURL: URL,
        outputURL: URL,
        config: LiveCaptureConfig
    ) throws -> ProcessRequest {
        guard config.runtime == "mlx_audio_cli" else {
            throw RuntimeInvocationBuilder.Error.unsupportedRuntime(config.runtime)
        }
        var arguments = [
            "-u", "-m", "mlx_audio.stt.generate",
            "--model", config.model,
            "--audio", segmentURL.path,
            "--output-path", outputURL.path,
            "--format", "txt"
        ]
        if !config.language.isEmpty {
            arguments += ["--language", config.language]
            let kwargs = "{\"source_lang\":\"\(config.language)\",\"target_lang\":\"\(config.language)\"}"
            arguments += ["--gen-kwargs", kwargs]
        }
        return ProcessRequest(
            executablePath: TranscriptionViewModel.defaultCanaryPythonPath(),
            arguments: arguments,
            environment: [
                "PYTHONUNBUFFERED": "1",
                "HF_HUB_DISABLE_PROGRESS_BARS": "1"
            ]
        )
    }
}
