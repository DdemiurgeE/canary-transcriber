import XCTest
@testable import CanaryTranscriberCore

final class DiarizationProgressTests: XCTestCase {
    func testDiarizationStagesRemainObservableInExecutionOrder() throws {
        let lines = [
            "CANARY_EVENT {\"kind\":\"stage\",\"name\":\"diarization_model_loading\"}",
            "CANARY_EVENT {\"kind\":\"stage\",\"name\":\"diarization_running\",\"file\":\"meeting.wav\"}",
            "CANARY_EVENT {\"kind\":\"stage\",\"name\":\"diarization_completed\",\"segments\":2}",
            "CANARY_EVENT {\"kind\":\"stage\",\"name\":\"speaker_segment_transcription\",\"file\":\"meeting.wav\"}",
            "CANARY_EVENT {\"kind\":\"stage\",\"name\":\"workspace_writing\",\"file\":\"meeting.wav\"}",
        ]

        let names = try lines.map { line -> String in
            guard case let .stage(name, _) = try XCTUnwrap(TranscriptionEventParser.parseLine(line)) else {
                XCTFail("Expected stage event")
                return ""
            }
            return name
        }

        XCTAssertEqual(names, [
            "diarization_model_loading",
            "diarization_running",
            "diarization_completed",
            "speaker_segment_transcription",
            "workspace_writing",
        ])
    }
}
