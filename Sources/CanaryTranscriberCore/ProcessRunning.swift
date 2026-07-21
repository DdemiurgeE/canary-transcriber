import Foundation

public enum ProcessOutputChannel: Equatable, Sendable {
    case stdout
    case stderr
}

public struct ProcessOutputEvent: Equatable, Sendable {
    public let channel: ProcessOutputChannel
    public let text: String
    public let isFinalPartialLine: Bool

    public init(channel: ProcessOutputChannel, text: String, isFinalPartialLine: Bool = false) {
        self.channel = channel
        self.text = text
        self.isFinalPartialLine = isFinalPartialLine
    }
}

public struct ProcessRequest: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: String?

    public init(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

public struct ProcessResult: Equatable, Sendable {
    public let terminationStatus: Int32
    public let terminationReason: Process.TerminationReason

    public init(terminationStatus: Int32, terminationReason: Process.TerminationReason) {
        self.terminationStatus = terminationStatus
        self.terminationReason = terminationReason
    }
}

public protocol ProcessRunningTask: AnyObject {
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    func terminate()
}

public protocol ProcessRunning: AnyObject {
    @discardableResult
    func start(
        _ request: ProcessRequest,
        onOutput: @escaping (ProcessOutputEvent) -> Void,
        onTermination: @escaping (ProcessResult) -> Void
    ) throws -> any ProcessRunningTask
}
