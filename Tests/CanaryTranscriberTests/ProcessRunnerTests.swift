import XCTest
@testable import CanaryTranscriber
import CanaryTranscriberCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesInterleavedStdoutAndStderrAndFinalPartialLine() throws {
        let runner = ProcessRunner()
        let finished = expectation(description: "process terminates")
        let lock = NSLock()
        var events: [ProcessOutputEvent] = []
        var result: ProcessResult?

        _ = try runner.start(
            ProcessRequest(
                executablePath: "/bin/sh",
                arguments: ["-c", "printf 'out-1\\n'; printf 'err-1\\n' >&2; printf 'partial'"]
            ),
            onOutput: { event in
                lock.lock()
                events.append(event)
                lock.unlock()
            },
            onTermination: { termination in
                lock.lock()
                result = termination
                lock.unlock()
                finished.fulfill()
            }
        )

        wait(for: [finished], timeout: 2)
        XCTAssertEqual(result?.terminationStatus, 0)
        XCTAssertTrue(events.contains { $0.channel == .stdout && $0.text == "out-1\n" })
        XCTAssertTrue(events.contains { $0.channel == .stderr && $0.text == "err-1\n" })
        XCTAssertTrue(events.contains { $0.channel == .stdout && $0.text == "partial" && $0.isFinalPartialLine })
    }

    func testNonZeroExitIsReported() throws {
        let runner = ProcessRunner()
        let finished = expectation(description: "process terminates")
        var status: Int32?

        _ = try runner.start(
            ProcessRequest(executablePath: "/bin/sh", arguments: ["-c", "exit 7"]),
            onOutput: { _ in },
            onTermination: { result in
                status = result.terminationStatus
                finished.fulfill()
            }
        )

        wait(for: [finished], timeout: 2)
        XCTAssertEqual(status, 7)
    }

    func testCancellationTerminatesRunningProcess() throws {
        let runner = ProcessRunner()
        let finished = expectation(description: "process terminates")
        var result: ProcessResult?

        let task = try runner.start(
            ProcessRequest(executablePath: "/bin/sh", arguments: ["-c", "sleep 5"]),
            onOutput: { _ in },
            onTermination: { termination in
                result = termination
                finished.fulfill()
            }
        )
        XCTAssertTrue(task.isRunning)
        task.terminate()

        wait(for: [finished], timeout: 2)
        XCTAssertEqual(result?.terminationStatus, 15)
    }

    func testMissingExecutableFailsBeforeStarting() {
        let runner = ProcessRunner()

        XCTAssertThrowsError(try runner.start(
            ProcessRequest(executablePath: "/definitely/missing/canary-process"),
            onOutput: { _ in },
            onTermination: { _ in }
        )) { error in
            XCTAssertEqual(
                error as? ProcessRunner.RunnerError,
                .executableNotFound("/definitely/missing/canary-process")
            )
        }
    }
}
