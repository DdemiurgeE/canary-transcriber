import Foundation

public struct BatchFileResult: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case succeeded
        case failed
        case stopped
    }

    public let path: String
    public let status: Status
    public let message: String?

    public init(path: String, status: Status, message: String? = nil) {
        self.path = path
        self.status = status
        self.message = message
    }
}

public struct BatchResult: Equatable, Sendable {
    public let files: [BatchFileResult]
    public let stopped: Bool

    public init(files: [BatchFileResult], stopped: Bool = false) {
        self.files = files
        self.stopped = stopped
    }

    public var succeededCount: Int { files.filter { $0.status == .succeeded }.count }
    public var failedCount: Int { files.filter { $0.status == .failed }.count }
    public var stoppedCount: Int { files.filter { $0.status == .stopped }.count }

    public var hasErrors: Bool {
        stopped || failedCount > 0
    }

    public var summary: String {
        "succeeded=\(succeededCount), failed=\(failedCount), stopped=\(stoppedCount), total=\(files.count)"
    }
}
