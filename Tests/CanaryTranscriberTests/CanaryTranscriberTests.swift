import XCTest
@testable import CanaryTranscriberCore

final class CanaryTranscriberTests: XCTestCase {
    func testParseSpeakerAliasesTextSupportsCommentsAndSeparators() {
        let input = """
        # comment
        SPEAKER_00 = Alice
        SPEAKER_01: Bob
        SPEAKER_02	Charlie
        SPEAKER_01 = Bobby
        malformed line

        """

        let parsed = parseSpeakerAliasesText(input)

        XCTAssertEqual(parsed["SPEAKER_00"], "Alice")
        XCTAssertEqual(parsed["SPEAKER_01"], "Bobby")
        XCTAssertEqual(parsed["SPEAKER_02"], "Charlie")
        XCTAssertEqual(parsed.count, 3)
    }

    func testBatchConfigRoundTripsSpeakerAliases() throws {
        let config = BatchConfig(
            files: ["/tmp/input.wav"],
            outputDir: "/tmp/output",
            writeNextToSource: false,
            profileID: "multilingual-canary-v2",
            runtime: "mlx_audio_cli",
            model: "CogniSoftOrg/canary-1b-v2-mlx-bf16",
            language: "ru",
            timestamps: false,
            chunkDuration: 30,
            overlapDuration: 2,
            diarization: true,
            speakerCount: 2,
            speakerAliases: ["SPEAKER_00": "Alice", "SPEAKER_01": "Bob"]
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(BatchConfig.self, from: data)

        XCTAssertEqual(decoded.speakerAliases["SPEAKER_00"], "Alice")
        XCTAssertEqual(decoded.speakerAliases["SPEAKER_01"], "Bob")
        XCTAssertEqual(decoded.speakerCount, 2)
        XCTAssertEqual(decoded.model, "CogniSoftOrg/canary-1b-v2-mlx-bf16")
    }
}
