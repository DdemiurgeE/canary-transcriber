import XCTest
@testable import CanaryTranscriber

final class AudioMixerTests: XCTestCase {
    func testMixArgumentsMapsInputsMicPriorityAndOutputPath() {
        let args = AudioMixer.mixArguments(
            appPath: "/tmp/app.m4a",
            micPath: "/tmp/mic.caf",
            outputPath: "/tmp/mixed.m4a"
        )

        XCTAssertEqual(args.first, "-hide_banner")
        XCTAssertEqual(args.last, "/tmp/mixed.m4a")

        guard let appIndex = args.firstIndex(of: "/tmp/app.m4a"),
              let micIndex = args.firstIndex(of: "/tmp/mic.caf") else {
            return XCTFail("expected both input paths in arguments")
        }
        XCTAssertLessThan(appIndex, micIndex, "app audio must be the first ffmpeg input so [0:a]/[1:a] map correctly")

        guard let filterComplex = args.first(where: { $0.contains("amix") }) else {
            return XCTFail("expected a -filter_complex argument containing amix")
        }
        XCTAssertTrue(filterComplex.contains("[0:a]volume=0.22"), "app audio must stay attenuated relative to microphone")
        XCTAssertTrue(filterComplex.contains("dynaudnorm"), "microphone must be normalized")
    }
}
