import Foundation
import Darwin
import CanaryTranscriberCore

public final class ProcessRunner: ProcessRunning {
    public enum RunnerError: Error, Equatable, LocalizedError {
        case emptyExecutablePath
        case executableNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .emptyExecutablePath:
                return "Process executable path cannot be empty."
            case .executableNotFound(let path):
                return "Process executable was not found or is not executable: \(path)"
            }
        }
    }

    private final class Task: ProcessRunningTask {
        private let process: Process
        private let terminationLock = NSLock()
        private var didTerminate = false

        init(process: Process) {
            self.process = process
        }

        var processIdentifier: Int32 { process.processIdentifier }
        var isRunning: Bool { process.isRunning }

        func terminate() {
            terminationLock.lock()
            guard !didTerminate else {
                terminationLock.unlock()
                return
            }
            didTerminate = true
            terminationLock.unlock()

            let descendants = ProcessRunner.descendantPIDs(of: process.processIdentifier)
            for pid in descendants.reversed() {
                _ = Darwin.kill(pid, SIGTERM)
            }
            if process.isRunning {
                process.terminate()
            }
        }
    }

    public init() {}

    private static func descendantPIDs(of parent: Int32) -> [Int32] {
        let query = Process()
        let pipe = Pipe()
        query.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        query.arguments = ["-P", String(parent)]
        query.standardOutput = pipe
        query.standardError = FileHandle.nullDevice
        do {
            try query.run()
            query.waitUntilExit()
        } catch {
            return []
        }

        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let children = output.split(whereSeparator: { $0.isNewline }).compactMap { Int32($0) }
        return children + children.flatMap { descendantPIDs(of: $0) }
    }

    @discardableResult
    public func start(
        _ request: ProcessRequest,
        onOutput: @escaping (ProcessOutputEvent) -> Void,
        onTermination: @escaping (ProcessResult) -> Void
    ) throws -> any ProcessRunningTask {
        guard !request.executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunnerError.emptyExecutablePath
        }
        guard FileManager.default.isExecutableFile(atPath: request.executablePath) else {
            throw RunnerError.executableNotFound(request.executablePath)
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutBuffer = LockedLineBuffer(channel: .stdout, onOutput: onOutput)
        let stderrBuffer = LockedLineBuffer(channel: .stderr, onOutput: onOutput)

        process.executableURL = URL(fileURLWithPath: request.executablePath)
        process.arguments = request.arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = request.environment.isEmpty ? nil : request.environment
        if let workingDirectory = request.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }
        process.terminationHandler = { process in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
            stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
            stdoutBuffer.flush()
            stderrBuffer.flush()
            onTermination(ProcessResult(
                terminationStatus: process.terminationStatus,
                terminationReason: process.terminationReason
            ))
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        return Task(process: process)
    }
}

private final class LockedLineBuffer: @unchecked Sendable {
    private let channel: ProcessOutputChannel
    private let onOutput: (ProcessOutputEvent) -> Void
    private var pending = Data()
    private let lock = NSLock()

    init(channel: ProcessOutputChannel, onOutput: @escaping (ProcessOutputEvent) -> Void) {
        self.channel = channel
        self.onOutput = onOutput
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        pending.append(data)
        let events = drainCompleteLines()
        lock.unlock()
        events.forEach(onOutput)
    }

    func flush() {
        lock.lock()
        guard !pending.isEmpty else {
            lock.unlock()
            return
        }
        let text = String(decoding: pending, as: UTF8.self)
        pending.removeAll(keepingCapacity: false)
        lock.unlock()
        onOutput(ProcessOutputEvent(channel: channel, text: text, isFinalPartialLine: true))
    }

    private func drainCompleteLines() -> [ProcessOutputEvent] {
        var events: [ProcessOutputEvent] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[..<newline]
            pending.removeSubrange(...newline)
            events.append(ProcessOutputEvent(
                channel: channel,
                text: String(decoding: lineData, as: UTF8.self) + "\n"
            ))
        }
        return events
    }
}
