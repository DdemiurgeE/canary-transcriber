import XCTest
import CanaryTranscriberCore

final class RuntimeInvocationTests: XCTestCase {
    func testCanaryRussianInvocationIncludesRuToRuGenerationKwargs() throws {
        let invocation = try RuntimeInvocationBuilder.make(
            runtime: "mlx_audio_cli",
            model: "CogniSoftOrg/canary-1b-v2-mlx-bf16",
            audioPath: "/tmp/chunk.wav",
            language: "ru"
        )

        XCTAssertEqual(invocation.executable, "python")
        XCTAssertEqual(invocation.arguments, [
            "-m", "mlx_audio.stt.generate",
            "--model", "CogniSoftOrg/canary-1b-v2-mlx-bf16",
            "--audio", "/tmp/chunk.wav",
            "--language", "ru",
            "--gen-kwargs", "{\"source_lang\":\"ru\",\"target_lang\":\"ru\"}"
        ])
    }

    func testUnsupportedRuntimeFails() {
        XCTAssertThrowsError(try RuntimeInvocationBuilder.make(
            runtime: "unknown", model: "model", audioPath: "audio.wav", language: "ru"
        )) { error in
            XCTAssertEqual(error as? RuntimeInvocationBuilder.Error, .unsupportedRuntime("unknown"))
        }
    }
}
