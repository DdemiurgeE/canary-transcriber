import XCTest
@testable import CanaryTranscriberCore

final class SessionTranscriptTests: XCTestCase {
    func testDecodesPlainChunksWithoutDiarization() throws {
        let json = """
        {
            "audio": "/tmp/meeting.m4a",
            "profile": "multilingual-canary-v2",
            "runtime": "mlx_audio_cli",
            "model": "CogniSoftOrg/canary-1b-v2-mlx-bf16",
            "language": "ru",
            "timestamps": false,
            "manual_chunking": true,
            "chunk_duration": 30.0,
            "overlap_duration": 2.0,
            "diarization": false,
            "speaker_count": null,
            "meeting_workspace": false,
            "text": "Привет мир",
            "chunks": [
                {"index": 0, "start": 0.0, "end": 30.0, "path": "chunk_0000.wav", "speaker": null, "chars": 10, "text": "Привет мир"}
            ]
        }
        """.data(using: .utf8)!

        let transcript = try JSONDecoder().decode(SessionTranscript.self, from: json)
        XCTAssertEqual(transcript.text, "Привет мир")
        XCTAssertNil(transcript.transcriptionSegments)
        XCTAssertEqual(transcript.displaySegments, transcript.chunks)
        XCTAssertEqual(transcript.displaySegments.first?.speaker, nil)
    }

    func testDecodesSpeakerAttributedSegmentsWhenDiarizationRan() throws {
        let json = """
        {
            "audio": "/tmp/meeting.m4a",
            "profile": "multilingual-canary-v2",
            "runtime": "mlx_audio_cli",
            "model": "CogniSoftOrg/canary-1b-v2-mlx-bf16",
            "language": "ru",
            "diarization": true,
            "speaker_count": 2,
            "text": "combined",
            "chunks": [],
            "transcription_segments": [
                {"speaker": "SPEAKER_00", "start": 0.0, "end": 2.0, "text": "Привет"},
                {"speaker": "SPEAKER_01", "start": 2.0, "end": 5.0, "text": "Здравствуйте"}
            ],
            "speaker_summary": [
                {"speaker": "SPEAKER_00", "segments": 1, "seconds": 2.0, "chars": 6, "alias": "Alice"},
                {"speaker": "SPEAKER_01", "segments": 1, "seconds": 3.0, "chars": 12, "alias": ""}
            ],
            "speaker_aliases": {"SPEAKER_00": "Alice"}
        }
        """.data(using: .utf8)!

        let transcript = try JSONDecoder().decode(SessionTranscript.self, from: json)
        XCTAssertEqual(transcript.displaySegments.count, 2)
        XCTAssertEqual(transcript.displaySegments.first?.speaker, "SPEAKER_00")
        XCTAssertEqual(transcript.speakerSummary?.first?.alias, "Alice")
        XCTAssertEqual(transcript.speakerAliases, ["SPEAKER_00": "Alice"])
    }
}
