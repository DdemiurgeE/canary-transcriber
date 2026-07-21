import XCTest
@testable import CanaryTranscriberCore

final class TranscriptionConfigurationTests: XCTestCase {
    private func makeConfig(
        files: [String] = ["/tmp/input.wav"],
        profileID: String = "multilingual-canary-v2",
        runtime: String = "mlx_audio_cli",
        chunkDuration: Double? = 30,
        overlapDuration: Double = 2,
        speakerCount: Int? = nil
    ) -> BatchConfig {
        BatchConfig(
            files: files,
            outputDir: "/tmp/output",
            writeNextToSource: false,
            profileID: profileID,
            runtime: runtime,
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

    func testBlankInputPathFailsValidation() {
        XCTAssertThrowsError(try makeConfig(files: ["  "]).validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .emptyInputPath)
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

    func testUnsupportedRuntimeFailsValidation() {
        let config = makeConfig(runtime: "unknown-runtime")

        XCTAssertThrowsError(try config.validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .unsupportedRuntime)
        }
    }

    func testProfileRuntimeMismatchFailsValidation() {
        let config = makeConfig(profileID: "fast-whisper-turbo")

        XCTAssertThrowsError(try config.validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .unsupportedProfileRuntime)
        }
    }

    func testNonFiniteChunkDurationFailsValidation() {
        XCTAssertThrowsError(try makeConfig(chunkDuration: .infinity).validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .nonFiniteChunkDuration)
        }
    }

    func testNonFiniteOverlapDurationFailsValidation() {
        XCTAssertThrowsError(try makeConfig(overlapDuration: .nan).validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .nonFiniteOverlapDuration)
        }
    }

    func testNilChunkDurationMeansOverlapMustBeZero() {
        XCTAssertNoThrow(try makeConfig(chunkDuration: nil, overlapDuration: 0).validated())
        XCTAssertThrowsError(try makeConfig(chunkDuration: nil, overlapDuration: 1).validated()) { error in
            XCTAssertEqual(error as? BatchConfig.ValidationError, .invalidOverlapDuration)
        }
    }
}
