import XCTest
@testable import CanaryTranscriber
@testable import CanaryTranscriberCore

/// Guards the "rename an existing session" path: patching a `.canary.md`/`.canary.json` that was
/// already written must update the speaker labels **without** regenerating the file, otherwise
/// user notes and hand edits are destroyed.
final class SpeakerRenamePropagationTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpeakerRenamePropagationTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeJSON(at url: URL) throws {
        let payload = """
        {
            "audio": "/tmp/meeting.m4a",
            "profile": "multilingual-canary-v2",
            "runtime": "mlx_audio_cli",
            "model": "m",
            "language": "ru",
            "diarization": true,
            "text": "hi there",
            "chunks": [],
            "speaker_summary": [
                {"speaker": "SPEAKER_00", "segments": 1, "seconds": 2.0, "chars": 2, "alias": ""}
            ],
            "speaker_aliases": {"SPEAKER_00": ""}
        }
        """
        try payload.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Mirrors what `MeetingWorkspace.render()` writes for one speaker and no alias, including the
    /// `_` escaping applied by `markdownInline`.
    private func writeMarkdown(at url: URL) throws {
        let lines = [
            "---",
            "source: meeting.m4a",
            "profile: multilingual-canary-v2",
            "---",
            "# Transcript: meeting.m4a",
            "",
            "## Speakers",
            "",
            "| Speaker | Segments | Duration | Alias |",
            "|---|---:|---:|---|",
            "| SPEAKER\\_00 | 1 | 00:00:02 |  |",
            "",
            "## Transcript",
            "",
            "**SPEAKER\\_00** [00:00:00 - 00:00:02]: hello from the transcript",
            "",
            "## Summary",
            "",
            "User notes that must be preserved",
            ""
        ]
        try (lines.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeSession(jsonURL: URL, markdownURL: URL) -> SessionRecord {
        SessionRecord(
            sourceAudioPath: "/tmp/meeting.m4a",
            displayName: "meeting",
            createdAt: Date(timeIntervalSince1970: 0),
            profileID: "multilingual-canary-v2",
            runtime: "mlx_audio_cli",
            model: "m",
            language: "ru",
            diarizationEnabled: true,
            speakerCount: 1,
            jsonPath: jsonURL.path,
            markdownPath: markdownURL.path
        )
    }

    func testRenamingASpeakerPatchesTheExistingJSONAndMarkdownFiles() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let jsonURL = directory.appendingPathComponent("meeting.canary.json")
        let markdownURL = directory.appendingPathComponent("meeting.canary.md")
        try writeJSON(at: jsonURL)
        try writeMarkdown(at: markdownURL)

        let transcript = try JSONDecoder().decode(SessionTranscript.self, from: Data(try Data(contentsOf: jsonURL)))
        let session = makeSession(jsonURL: jsonURL, markdownURL: markdownURL)
        let viewModel = TranscriptionViewModel(libraryStore: SessionLibraryStore(directoryURL: makeTempDirectory()))

        viewModel.setSpeakerAlias("Alice", for: "SPEAKER_00")
        viewModel.rewriteOutputsAfterSpeakerRename(alias: "Alice", speaker: "SPEAKER_00", session: session, transcript: transcript)

        // JSON: alias lands in both the summary and the alias map.
        let patchedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any]
        let summary = patchedJSON?["speaker_summary"] as? [[String: Any]]
        XCTAssertEqual(summary?.first?["alias"] as? String, "Alice")
        XCTAssertEqual((patchedJSON?["speaker_aliases"] as? [String: String])?["SPEAKER_00"], "Alice")

        // Markdown: labels are patched in place, everything else is untouched.
        let patchedMarkdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(patchedMarkdown.hasPrefix("---\nsource: meeting.m4a\nprofile: multilingual-canary-v2\n---\n"),
                      "front matter must survive the patch")
        XCTAssertTrue(patchedMarkdown.contains("| SPEAKER\\_00 | 1 | 00:00:02 | Alice |"),
                      "Speakers table alias cell must be updated in place")
        XCTAssertTrue(patchedMarkdown.contains("**Alice (SPEAKER\\_00)** [00:00:00 - 00:00:02]: hello from the transcript"),
                      "Transcript label must be rewritten")
        XCTAssertTrue(patchedMarkdown.contains("User notes that must be preserved"),
                      "user notes must be preserved (safe rename)")
        XCTAssertFalse(patchedMarkdown.contains("**SPEAKER\\_00**"),
                       "raw speaker label must no longer be used in the transcript")
    }

    func testClearingAnAliasRestoresTheRawSpeakerLabel() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let jsonURL = directory.appendingPathComponent("meeting.canary.json")
        let markdownURL = directory.appendingPathComponent("meeting.canary.md")
        try writeJSON(at: jsonURL)
        try writeMarkdown(at: markdownURL)

        let transcript = try JSONDecoder().decode(SessionTranscript.self, from: Data(try Data(contentsOf: jsonURL)))
        let session = makeSession(jsonURL: jsonURL, markdownURL: markdownURL)
        let viewModel = TranscriptionViewModel(libraryStore: SessionLibraryStore(directoryURL: makeTempDirectory()))

        viewModel.setSpeakerAlias("Alice", for: "SPEAKER_00")
        viewModel.rewriteOutputsAfterSpeakerRename(alias: "Alice", speaker: "SPEAKER_00", session: session, transcript: transcript)
        viewModel.setSpeakerAlias("", for: "SPEAKER_00")
        viewModel.rewriteOutputsAfterSpeakerRename(alias: "", speaker: "SPEAKER_00", session: session, transcript: transcript)

        let patchedMarkdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(patchedMarkdown.contains("**SPEAKER\\_00** [00:00:00 - 00:00:02]: hello from the transcript"),
                      "clearing the alias must restore the raw speaker label")
        XCTAssertTrue(patchedMarkdown.contains("| SPEAKER\\_00 | 1 | 00:00:02 |  |"),
                      "clearing the alias must empty the table cell")
        XCTAssertTrue(patchedMarkdown.contains("User notes that must be preserved"))
    }
}
