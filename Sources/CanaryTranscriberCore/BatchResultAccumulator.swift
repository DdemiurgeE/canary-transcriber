import Foundation

/// Collects per-file protocol events into one terminal batch result.
/// It is deliberately small and deterministic so the ViewModel can use the same
/// behavior as integration tests without coupling tests to SwiftUI.
public final class BatchResultAccumulator {
    private var orderedPaths: [String] = []
    private var results: [String: BatchFileResult] = [:]
    private var didFinish = false

    public private(set) var terminalEventCount = 0

    public init() {}

    public func start(paths: [String]) {
        orderedPaths = paths
        results = [:]
        didFinish = false
        terminalEventCount = 0
    }

    public func recordSucceeded(path: String) {
        guard !didFinish else { return }
        results[path] = BatchFileResult(path: path, status: .succeeded)
    }

    public func recordFailed(path: String, message: String) {
        guard !didFinish else { return }
        results[path] = BatchFileResult(path: path, status: .failed, message: message)
    }

    public func finish(stopped: Bool, fallbackMessage: String? = nil) -> BatchResult? {
        guard !didFinish else { return nil }
        didFinish = true
        terminalEventCount += 1

        let fallbackStatus: BatchFileResult.Status = stopped ? .stopped : .failed
        let files = orderedPaths.map { path in
            results[path] ?? BatchFileResult(path: path, status: fallbackStatus, message: fallbackMessage)
        }
        return BatchResult(files: files, stopped: stopped)
    }
}
