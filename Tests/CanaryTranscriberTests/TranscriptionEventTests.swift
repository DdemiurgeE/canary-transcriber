import XCTest
import Foundation
@testable import CanaryTranscriberCore

final class TranscriptionEventTests: XCTestCase {
    func testParsesFileCompletedCompatibilityEvent() throws {
        let line = "CANARY_EVENT {\"kind\":\"file_done\",\"file\":\"/tmp/meeting.m4a\",\"txt\":\"/tmp/meeting.canary.txt\",\"json\":\"/tmp/meeting.canary.json\",\"md\":\"/tmp/meeting.canary.md\"}"

        let event = try XCTUnwrap(TranscriptionEventParser.parseLine(line))
        XCTAssertEqual(event, .fileCompleted(
            path: "/tmp/meeting.m4a",
            textPath: "/tmp/meeting.canary.txt",
            jsonPath: "/tmp/meeting.canary.json",
            markdownPath: "/tmp/meeting.canary.md",
            chars: nil
        ))
    }

    func testParsesProgressAndWarningEvents() throws {
        let progress = try XCTUnwrap(TranscriptionEventParser.parseLine("CANARY_EVENT {\"kind\":\"chunk_done\",\"index\":2,\"start\":60.0,\"chars\":140}"))
        XCTAssertEqual(progress, .chunkCompleted(index: 2, start: 60, chars: 140))

        let warning = try XCTUnwrap(TranscriptionEventParser.parseLine("CANARY_EVENT {\"kind\":\"warning\",\"message\":\"HF token missing\"}"))
        XCTAssertEqual(warning, .warning(message: "HF token missing"))
    }

    func testParsesDiarizationProgressStages() throws {
        let loading = try XCTUnwrap(TranscriptionEventParser.parseLine("CANARY_EVENT {\"kind\":\"stage\",\"name\":\"diarization_model_loading\"}"))
        XCTAssertEqual(loading, .stage(name: "diarization_model_loading", file: nil))

        let running = try XCTUnwrap(TranscriptionEventParser.parseLine("CANARY_EVENT {\"kind\":\"stage\",\"name\":\"speaker_segment_transcription\",\"file\":\"meeting.m4a\",\"total\":3}"))
        XCTAssertEqual(running, .stage(name: "speaker_segment_transcription", file: "meeting.m4a"))
    }

    func testNonEventLineIsIgnored() {
        XCTAssertNil(TranscriptionEventParser.parseLine("Stage: normalizing audio"))
    }

    func testPreservesFileDoneCharsForDiagnostics() throws {
        let event = try XCTUnwrap(TranscriptionEventParser.parseLine("CANARY_EVENT {\"kind\":\"file_done\",\"file\":\"meeting.m4a\",\"chars\":321}"))
        XCTAssertEqual(event, .fileCompleted(path: "meeting.m4a", textPath: nil, jsonPath: nil, markdownPath: nil, chars: 321))
    }

    func testUnknownEventRemainsObservable() throws {
        let event = try XCTUnwrap(TranscriptionEventParser.parseLine("CANARY_EVENT {\"kind\":\"future_kind\",\"value\":42,\"ok\":true}"))
        XCTAssertEqual(event, .unknown(kind: "future_kind", payload: ["kind": "future_kind", "value": "42", "ok": "true"]))
    }

    func testEmbeddedPythonEmitsRepresentativeCanaryEvents() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CanaryTranscriberLib/CanaryTranscriber.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let startMarker = "let script = #\"\"\""
        let endMarker = "\"\"\"#"
        let start = try XCTUnwrap(source.range(of: startMarker)).upperBound
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)).lowerBound
        let script = String(source[start..<end])

        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("canary-event-fixtures-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config: [String: Any] = [
            "files": [],
            "_eventFixtures": [
                ["kind": "batch_start", "total": 1],
                ["kind": "file_started", "path": "meeting.m4a", "index": 1],
                ["kind": "chunk_done", "index": 0, "start": 0.0, "chars": 7],
                ["kind": "file_done", "file": "meeting.m4a", "chars": 7],
                ["kind": "future_kind", "value": 42]
            ]
        ]
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", script, configURL.path]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(output.contains("CANARY_EVENT {\"total\": 1, \"kind\": \"batch_start\"}"), output)
        XCTAssertTrue(output.contains("\"chars\": 7"), output)
        XCTAssertTrue(output.contains("\"kind\": \"future_kind\""), output)
    }

    func testMalformedEventProducesDiagnostic() {
        XCTAssertThrowsError(try TranscriptionEventParser.parse("CANARY_EVENT not-json")) { error in
            XCTAssertEqual(error as? TranscriptionEventParser.ParseError, .invalidJSON)
        }
    }
}
