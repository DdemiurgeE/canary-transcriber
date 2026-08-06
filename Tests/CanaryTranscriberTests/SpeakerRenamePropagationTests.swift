import XCTest
@testable import CanaryTranscriber
@testable import CanaryTranscriberCore

final class SpeakerRenamePropagationTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SpeakerRenamePropagationTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRenamingASpeakerPatchesTheExistingJSONAndMarkdownFiles() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let jsonURL = directory.appendingPathComponent("meeting.canary.json")
        let jsonPayload = """
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
        try jsonPayload.write(to: jsonURL, atomically: true, encoding: .utf8)

        let markdownURL = directory.appendingPathComponent("meeting.canary.md")
        let markdownContents = """
        ---
        source: meeting.m4a
        profile: multilingual-canary-v2
        ---
        # Transcript: meeting.m4a

        stale body that must be replaced
        """
        try markdownContents.write(to: markdownURL, atomically: true, encoding: .utf8)

        let session = SessionRecord(
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

        let transcript = try JSONDecoder().decode(SessionTranscript.self, from: Data(jsonPayload.utf8))
        let viewModel = TranscriptionViewModel(libraryStore: SessionLibraryStore(directoryURL: makeTempDirectory()))

        viewModel.setSpeakerAlias("Alice", for: "SPEAKER_00")
        viewModel.rewriteOutputsAfterSpeakerRename(alias: "Alice", speaker: "SPEAKER_00", session: session, transcript: transcript)

        let patchedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any]
        let summary = patchedJSON?["speaker_summary"] as? [[String: Any]]
        XCTAssertEqual(summary?.first?["alias"] as? String, "Alice")
        let aliasMap = patchedJSON?["speaker_aliases"] as? [String: String]
        XCTAssertEqual(aliasMap?["SPEAKER_00"], "Alice")

        let patchedMarkdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(patchedMarkdown.hasPrefix("---\nsource: meeting.m4a\nprofile: multilingual-canary-v2\n---\n"))
        XCTAssertFalse(patchedMarkdown.contains("stale body that must be replaced"))
    }
}
