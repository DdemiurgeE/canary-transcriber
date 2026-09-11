import XCTest
@testable import CanaryTranscriber
import CanaryTranscriberCore

final class SessionEditingRegressionTests: XCTestCase {
    @MainActor
    func testRenamePreservesUserMarkdownNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = TranscriptionViewModel(aliasPersistence: SpeakerAliasPersistence(defaults: defaults), libraryStore: SessionLibraryStore(directoryURL: directory))
        let json = directory.appendingPathComponent("meeting.json")
        let markdown = directory.appendingPathComponent("meeting.md")
        try fixture(text: "Current transcript").write(to: json)
        let transcript = try SessionTranscript.load(from: json)
        let original = MeetingWorkspace(sourceName: "meeting.wav", segments: [SpeakerSegment(speaker: "SPEAKER_00", start: 0, end: 1, text: "Current transcript")], aliases: [:], fallbackText: "").render()
        let notes = original.replacingOccurrences(of: "## Summary\n", with: "## Summary\nMy private summary\n").replacingOccurrences(of: "## Decisions\n", with: "## Decisions\nKeep the launch date\n") + "\n## Custom notes\nUntouched **formatting**\n"
        try notes.write(to: markdown, atomically: true, encoding: .utf8)
        let session = record(json: json, markdown: markdown)
        model.rewriteOutputsAfterSpeakerRename(alias: "Alice", speaker: "SPEAKER_00", session: session, transcript: transcript)
        let result = try String(contentsOf: markdown)
        XCTAssertTrue(result.contains("My private summary"))
        XCTAssertTrue(result.contains("Keep the launch date"))
        XCTAssertTrue(result.contains("Untouched **formatting**"))
        XCTAssertTrue(result.contains("Alice"))
    }

    private func fixture(text: String, aliases: [String: String] = [:]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "audio": "meeting.wav", "profile": "fast-parakeet-v3", "runtime": "mlx_audio_cli", "model": "test", "language": "en", "diarization": true,
            "text": text, "chunks": [["start": 0, "end": 1, "speaker": "SPEAKER_00", "text": text]], "speaker_aliases": aliases
        ])
    }

    private func record(json: URL, markdown: URL) -> SessionRecord {
        SessionRecord(sourceAudioPath: "/meeting.wav", displayName: "meeting", createdAt: Date(), profileID: "fast-parakeet-v3", runtime: "mlx_audio_cli", model: "test", language: "en", diarizationEnabled: true, status: .done, jsonPath: json.path, markdownPath: markdown.path)
    }
}
