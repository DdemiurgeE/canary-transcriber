import Foundation
import CanaryTranscriberCore

final class LiveTranscriptionWorker {
    private let queue = DispatchQueue(label: "canary.live-transcription.serial")
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pending: [Int: (LiveTranscriptSegment, (Result<LiveTranscriptSegment, Error>) -> Void)] = [:]
    private var nextRequestID = 0
    private var stopped = false
    private var drainWaiters: [() -> Void] = []
    private var configurationKey: String?

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
                try self.ensureProcess(config: config)
                let requestID = self.nextRequestID
                self.nextRequestID += 1
                let placeholder = LiveTranscriptSegment(index: index, start: start, end: end, text: "")
                self.pending[requestID] = (placeholder, completion)
                let request: [String: Any] = [
                    "id": requestID,
                    "audio": segmentURL.path,
                    "language": config.language
                ]
                let data = try JSONSerialization.data(withJSONObject: request)
                self.inputPipe?.fileHandleForWriting.write(data)
                self.inputPipe?.fileHandleForWriting.write(Data("\n".utf8))
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func drain(completion: @escaping () -> Void) {
        queue.async {
            if self.pending.isEmpty {
                DispatchQueue.main.async { completion() }
            } else {
                self.drainWaiters.append(completion)
            }
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            drainWaiters.removeAll()
            pending.removeAll()
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            inputPipe?.fileHandleForWriting.closeFile()
            process?.terminate()
            process = nil
            inputPipe = nil
            outputPipe = nil
            configurationKey = nil
        }
    }

    private func ensureProcess(config: LiveCaptureConfig) throws {
        let key = "\(config.runtime)|\(config.model)|\(config.language)"
        if process?.isRunning == true, configurationKey == key { return }
        guard config.runtime == "mlx_audio_cli" else {
            throw RuntimeInvocationBuilder.Error.unsupportedRuntime(config.runtime)
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: TranscriptionViewModel.defaultCanaryPythonPath())
        process.arguments = ["-u", "-c", Self.pythonWorkerScript, "--model", config.model]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        process.environment = environment
        process.terminationHandler = { [weak self] process in
            self?.queue.async {
                guard let self else { return }
                let message = String(decoding: self.stderrBuffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let failure = NSError(
                    domain: "CanaryLiveTranscription",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Resident MLX worker exited." : message]
                )
                let callbacks = self.pending.values.map(\.1)
                self.pending.removeAll()
                callbacks.forEach { callback in
                    DispatchQueue.main.async { callback(.failure(failure)) }
                }
                self.finishDrainWaiters()
            }
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.stdoutBuffer.append(data)
                self?.consumeOutputLines()
            }
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.stderrBuffer.append(data) }
        }
        try process.run()
        self.process = process
        self.inputPipe = input
        self.outputPipe = output
        self.stdoutBuffer.removeAll(keepingCapacity: true)
        self.stderrBuffer.removeAll(keepingCapacity: true)
        self.configurationKey = key
    }

    private func consumeOutputLines() {
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let response = object as? [String: Any],
                  let id = response["id"] as? Int,
                  let entry = pending.removeValue(forKey: id) else { continue }
            let result: Result<LiveTranscriptSegment, Error>
            if let message = response["error"] as? String {
                result = .failure(NSError(domain: "CanaryLiveTranscription", code: 2, userInfo: [NSLocalizedDescriptionKey: message]))
            } else {
                let text = (response["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                result = .success(LiveTranscriptSegment(index: entry.0.index, start: entry.0.start, end: entry.0.end, text: text))
            }
            DispatchQueue.main.async { entry.1(result) }
            finishDrainWaitersIfNeeded()
        }
    }

    private func finishDrainWaitersIfNeeded() {
        guard pending.isEmpty else { return }
        finishDrainWaiters()
    }

    private func finishDrainWaiters() {
        let waiters = drainWaiters
        drainWaiters.removeAll()
        waiters.forEach { waiter in DispatchQueue.main.async { waiter() } }
    }

    private static let pythonWorkerScript = #"""
import argparse, json, tempfile
from pathlib import Path
from mlx_audio.stt.generate import generate_transcription
from mlx_audio.stt.utils import load_model

parser = argparse.ArgumentParser()
parser.add_argument('--model', required=True)
args = parser.parse_args()
model = load_model(args.model)
print(json.dumps({'ready': True}), flush=True)
for raw in __import__('sys').stdin:
    try:
        request = json.loads(raw)
        language = request.get('language', '')
        kwargs = {}
        if language:
            kwargs['language'] = language
            kwargs['gen_kwargs'] = {'source_lang': language, 'target_lang': language}
        with tempfile.TemporaryDirectory(prefix='canary-live-worker-') as directory:
            result = generate_transcription(
                model=model,
                audio=request['audio'],
                output_path=str(Path(directory) / 'transcript'),
                format='txt',
                **kwargs,
            )
        text = getattr(result, 'text', '') or ''
        print(json.dumps({'id': request['id'], 'text': text}, ensure_ascii=False), flush=True)
    except Exception as exc:
        print(json.dumps({'id': request.get('id', -1), 'error': str(exc)}, ensure_ascii=False), flush=True)
"""#
}
