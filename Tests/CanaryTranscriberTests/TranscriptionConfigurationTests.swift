import XCTest
@testable import CanaryTranscriberCore

final class TranscriptionConfigurationTests: XCTestCase {
    private func makeConfig(
        files: [String] = ["/tmp/input.wav"],
        chunkDuration: Double? = 30,
        overlapDuration: Double = 2,
        speakerCount: Int? = nil
    ) -> BatchConfig {
        BatchConfig(
            files: files,
            outputDir: "/tmp/output",
            writeNextToSource: false,
            profileID: "multilingual-canary-v2",
            runtime: "mlx_audio_cli",
            model: "CogniSoftOrg/canary-1b-v2-mlx-bf16",
            language: "ru",
            timestamps: false,
            chunkDuration: chunkDuration,
            overlapDuration: overlapDuration,
            diarization: speakerCount != nil,
            speakerCount: speakerCount,
            speakerAliases: [:]
        )
    }

    func testValidConfigurationPassesValidation() throws {
        XCTAssertNoThrow(try makeConfig().validated())
    }

    func testEmptyFilesFailValidation() {
        XCTAssertThrowsError(try makeConfig(files: []).validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .noInputFiles)
        }
    }

    func testNonPositiveChunkDurationFailsValidation() {
        XCTAssertThrowsError(try makeConfig(chunkDuration: 0).validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .invalidChunkDuration)
        }
    }

    func testOverlapMustBeSmallerThanChunkDuration() {
        XCTAssertThrowsError(try makeConfig(chunkDuration: 2, overlapDuration: 2).validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .invalidOverlapDuration)
        }
    }

    func testSpeakerCountMustBePositive() {
        XCTAssertThrowsError(try makeConfig(speakerCount: 0).validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .invalidSpeakerCount)
        }
    }
}
