import XCTest
@testable import CanaryTranscriberCore

final class MeetingWorkspaceTests: XCTestCase {
    func testRenderIncludesSpeakerSummaryTranscriptAndActionSections() {
        let segments = [
            SpeakerSegment(speaker: "SPEAKER_00", start: 0, end: 2.5, text: "Привет"),
            SpeakerSegment(speaker: "SPEAKER_01", start: 2.5, end: 5, text: "Здравствуйте")
        ]
        let workspace = MeetingWorkspace(
            sourceName: "meeting.m4a",
            segments: segments,
            aliases: ["SPEAKER_00": "Alice"],
            fallbackText: "Привет\nЗдравствуйте"
        )

        let markdown = workspace.render()
        XCTAssertTrue(markdown.contains("## Speakers"))
        XCTAssertTrue(markdown.contains("Alice (SPEAKER\\_00)"))
        XCTAssertTrue(markdown.contains("**Alice (SPEAKER\\_00)** [00:00:00 - 00:00:02]: Привет"))
        XCTAssertTrue(markdown.contains("**SPEAKER\\_01** [00:00:02 - 00:00:05]: Здравствуйте"))
        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("## Decisions"))
        XCTAssertTrue(markdown.contains("## Action items"))
        XCTAssertTrue(markdown.contains("## Open questions"))
    }

    func testRenderFallsBackToJoinedTextWhenSegmentTextIsMissing() {
        let segments = [
            SpeakerSegment(speaker: "SPEAKER_00", start: 0, end: 3, text: "")
        ]
        let workspace = MeetingWorkspace(
            sourceName: "meeting.m4a",
            segments: segments,
            aliases: [:],
            fallbackText: "Transcript survived"
        )

        XCTAssertTrue(workspace.render().contains("Transcript survived"))
    }

    func testEmptySegmentsUsePlainTranscriptFallback() {
        let workspace = MeetingWorkspace(
            sourceName: "audio.m4a",
            segments: [],
            aliases: [:],
            fallbackText: "Plain transcript"
        )

        let markdown = workspace.render()
        XCTAssertTrue(markdown.contains("# Transcript: audio.m4a"))
        XCTAssertTrue(markdown.contains("Plain transcript"))
        XCTAssertFalse(markdown.contains("## Speakers"))
    }

    func testMarkdownEscapesUntrustedSourceAliasSpeakerAndTranscript() {
        let workspace = MeetingWorkspace(
            sourceName: "bad|name`\n# heading.m4a",
            segments: [SpeakerSegment(speaker: "SPEAKER|00", start: 0, end: 1, text: "hello | *world*\nnext")],
            aliases: ["SPEAKER|00": "Alice|`_"],
            fallbackText: "fallback"
        )

        let markdown = workspace.render()
        XCTAssertTrue(markdown.contains("bad\\|name\\` # heading.m4a"))
        XCTAssertTrue(markdown.contains("Alice\\|\\`\\_ (SPEAKER\\|00)"))
        XCTAssertTrue(markdown.contains("hello \\| \\*world\\*  \nnext"))
        XCTAssertFalse(markdown.contains("| SPEAKER|00 |"))
    }
}
