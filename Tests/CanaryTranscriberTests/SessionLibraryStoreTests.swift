import XCTest
@testable import CanaryTranscriberCore

final class SessionLibraryStoreTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SessionLibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        return url
    }

    func testLoadReturnsEmptyArrayWhenNoFileExists() {
        let store = SessionLibraryStore(directoryURL: makeTempDirectory())
        XCTAssertEqual(store.load(), [])
    }

    func testSaveThenLoadRoundTrips() {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionLibraryStore(directoryURL: directory)

        let session = SessionRecord(
            sourceAudioPath: "/tmp/meeting.m4a",
            displayName: "meeting",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            profileID: "multilingual-canary-v2",
            runtime: "mlx_audio_cli",
            model: "CogniSoftOrg/canary-1b-v2-mlx-bf16",
            language: "ru",
            diarizationEnabled: true,
            speakerCount: 2,
            status: .done,
            textPath: "/tmp/meeting.canary.txt",
            jsonPath: "/tmp/meeting.canary.json",
            markdownPath: "/tmp/meeting.canary.md",
            logExcerpt: "Stage: transcribe\n"
        )

        store.save([session])
        XCTAssertEqual(store.load(), [session])
    }

    func testSaveOverwritesPreviousContent() {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionLibraryStore(directoryURL: directory)

        let first = SessionRecord(
            sourceAudioPath: "/tmp/a.m4a",
            displayName: "a",
            createdAt: Date(timeIntervalSince1970: 1),
            profileID: "p",
            runtime: "mlx_audio_cli",
            model: "m",
            language: "ru",
            diarizationEnabled: false
        )
        store.save([first])
        XCTAssertEqual(store.load(), [first])

        let second = SessionRecord(
            sourceAudioPath: "/tmp/b.m4a",
            displayName: "b",
            createdAt: Date(timeIntervalSince1970: 2),
            profileID: "p",
            runtime: "mlx_audio_cli",
            model: "m",
            language: "ru",
            diarizationEnabled: false
        )
        store.save([second])
        XCTAssertEqual(store.load(), [second])
    }
}
