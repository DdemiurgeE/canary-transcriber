import XCTest
@testable import CanaryTranscriberCore

final class TranscriptionEventTests: XCTestCase {
    func testParsesFileCompletedCompatibilityEvent() throws {
        let line = "CANARY_EVENT {\"kind\":\"file_done\",\"file\":\"/tmp/meeting.m4a\",\"txt\":\"/tmp/meeting.canary.txt\",\"json\":\"/tmp/meeting.canary.json\",\"md\":\"/tmp/meeting.canary.md\"}"

        let event = try XCTUnwrap(TranscriptionEventParser.parseLine(line))
        XCTAssertEqual(event, .fileCompleted(
            path: "/tmp/meeting.m4a",
            textPath: "/tmp/meeting.canary.txt",
            jsonPath: "/tmp/meeting.canary.json",
            markdownPath: "/tmp/meeting.canary.md"
        ))
    }

    func testParsesProgressAndWarningEvents() throws {
        let progress = try XCTUnwrap(TranscriptionEventParser.parseLine("CANARY_EVENT {\"kind\":\"chunk_done\",\"index\":2,\"start\":60.0,\"chars\":140}"))
        XCTAssertEqual(progress, .chunkCompleted(index: 2, start: 60, chars: 140))

        let warning = try XCTUnwrap(TranscriptionEventParser.parseLine("CANARY_EVENT {\"kind\":\"warning\",\"message\":\"HF token missing\"}"))
        XCTAssertEqual(warning, .warning(message: "HF token missing"))
    }

    func testNonEventLineIsIgnored() {
        XCTAssertNil(TranscriptionEventParser.parseLine("Stage: normalizing audio"))
    }

    func testMalformedEventProducesDiagnostic() {
        XCTAssertThrowsError(try TranscriptionEventParser.parse("CANARY_EVENT not-json")) { error in
            XCTAssertEqual(error as? TranscriptionEventParser.ParseError, .invalidJSON)
        }
    }
}
