import XCTest
@testable import CanaryTranscriberCore

final class TranscriptionOutputsTests: XCTestCase {
    func testOutputPathsUseSourceDirectoryAndCanarySuffix() {
        let source = URL(fileURLWithPath: "/tmp/Meeting Recording.m4a")
        let paths = TranscriptionOutputPaths(sourceURL: source, outputDirectory: nil, writeNextToSource: true)

        XCTAssertEqual(paths.text.lastPathComponent, "Meeting Recording.canary.txt")
        XCTAssertEqual(paths.json.lastPathComponent, "Meeting Recording.canary.json")
        XCTAssertEqual(paths.markdown.lastPathComponent, "Meeting Recording.canary.md")
        XCTAssertEqual(paths.text.deletingLastPathComponent().path, "/tmp")
    }

    func testOutputPathsUseConfiguredDirectory() {
        let source = URL(fileURLWithPath: "/input/meeting.wav")
        let output = URL(fileURLWithPath: "/output/transcripts")
        let paths = TranscriptionOutputPaths(sourceURL: source, outputDirectory: output, writeNextToSource: false)

        XCTAssertEqual(paths.text.path, "/output/transcripts/meeting.canary.txt")
        XCTAssertEqual(paths.json.path, "/output/transcripts/meeting.canary.json")
        XCTAssertEqual(paths.markdown.path, "/output/transcripts/meeting.canary.md")
    }

    func testOutputPathsUseSeparateMarkdownDirectoryWhenConfigured() {
        let source = URL(fileURLWithPath: "/input/meeting.wav")
        let output = URL(fileURLWithPath: "/output/transcripts")
        let markdownDir = URL(fileURLWithPath: "/output/notes-vault")
        let paths = TranscriptionOutputPaths(sourceURL: source, outputDirectory: output, writeNextToSource: false, markdownDirectory: markdownDir)

        XCTAssertEqual(paths.text.path, "/output/transcripts/meeting.canary.txt")
        XCTAssertEqual(paths.json.path, "/output/transcripts/meeting.canary.json")
        XCTAssertEqual(paths.markdown.path, "/output/notes-vault/meeting.canary.md")
    }

    func testFrontMatterEscapesQuotesAndUsesStableFieldOrder() {
        let frontMatter = TranscriptionFrontMatter(
            source: "meeting: Pavel's test.m4a",
            profile: "multilingual-canary-v2",
            runtime: "mlx_audio_cli",
            model: "org/model",
            language: "ru",
            date: "2026-07-21T12:00:00Z"
        )

        XCTAssertEqual(frontMatter.render(), """
        ---
        source: "meeting: Pavel's test.m4a"
        profile: multilingual-canary-v2
        runtime: mlx_audio_cli
        model: org/model
        language: ru
        date: 2026-07-21T12:00:00Z
        ---
        """.replacingOccurrences(of: "        ", with: "") + "\n")
    }
}
