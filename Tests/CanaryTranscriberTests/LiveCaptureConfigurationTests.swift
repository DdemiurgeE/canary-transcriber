import XCTest
@testable import CanaryTranscriberCore

final class LiveCaptureConfigurationTests: XCTestCase {
    func testValidConfigRoundTripsAndUsesNonOverlappingDefaults() throws {
        let config = LiveCaptureConfig(
            windowDuration: 5,
            overlapDuration: 0,
            profileID: "fast-parakeet-v3",
            runtime: "mlx_audio_cli",
            model: "mlx-community/parakeet-tdt-0.6b-v3",
            language: "ru",
            includeMicrophone: true,
            outputDirectory: "/tmp/live"
        )

        XCTAssertNoThrow(try config.validated())
        let decoded = try JSONDecoder().decode(LiveCaptureConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testInvalidWindowAndRuntimeAreRejected() {
        let config = LiveCaptureConfig(
            windowDuration: 0,
            overlapDuration: 1,
            profileID: "",
            runtime: "unknown",
            model: "",
            language: "ru",
            includeMicrophone: false,
            outputDirectory: ""
        )

        XCTAssertThrowsError(try config.validated()) { error in
            XCTAssertEqual(error as? LiveCaptureConfig.ValidationError, .invalidWindowDuration)
        }
    }
}
