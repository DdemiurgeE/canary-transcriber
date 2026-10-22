import XCTest
@testable import CanaryTranscriber
@testable import CanaryTranscriberCore

final class TranscriptionViewModelLibraryTests: XCTestCase {
    private func makeViewModel() -> TranscriptionViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TranscriptionViewModelLibraryTests-\(UUID().uuidString)", isDirectory: true)
        return TranscriptionViewModel(libraryStore: SessionLibraryStore(directoryURL: directory))
    }

    func testQueueingTheSamePathTwiceDoesNotDuplicateTheLibraryRow() {
        let viewModel = makeViewModel()
        viewModel.queueSession(for: "/tmp/meeting.m4a")
        viewModel.queueSession(for: "/tmp/meeting.m4a")

        XCTAssertEqual(viewModel.librarySessions.count, 1)
    }

    func testPostRecordingSettingsApplyChosenProfileLanguageAndDiarizationAfterCapture() {
        let viewModel = makeViewModel()
        viewModel.queueSession(for: "/tmp/recorded-conference.m4a")
        let id = viewModel.librarySessions[0].id
        viewModel.updateSession(path: "/tmp/recorded-conference.m4a") { $0.status = .done }

        let settings = PostRecordingRunSettings(
            profileID: "fast-whisper-turbo", language: "en", chunkDuration: "15",
            timestamps: true, diarization: true, speakerCount: "3",
            aliasesText: "SPEAKER_00 = Alice"
        )
        XCTAssertTrue(viewModel.applyPostRecordingSettings(settings, to: id))
        XCTAssertEqual(viewModel.selectedProfileID, "fast-whisper-turbo")
        XCTAssertEqual(viewModel.runtime, "mlx_whisper")
        XCTAssertEqual(viewModel.model, "mlx-community/whisper-large-v3-turbo")
        XCTAssertEqual(viewModel.language, "en")
        XCTAssertEqual(viewModel.chunkDuration, "15")
        XCTAssertTrue(viewModel.timestamps)
        XCTAssertTrue(viewModel.diarizationEnabled)
        XCTAssertEqual(viewModel.diarizationSpeakerCount, "3")
        XCTAssertEqual(viewModel.parsedSpeakerAliases()["SPEAKER_00"], "Alice")
        XCTAssertEqual(viewModel.librarySessions[0].status, .done)
    }

    func testPostRecordingDraftValidationRejectsInvalidChunkAndSpeakers() {
        var settings = PostRecordingRunSettings(
            profileID: "multilingual-canary-v2", language: "ru", chunkDuration: "15",
            timestamps: false, diarization: true, speakerCount: "auto", aliasesText: ""
        )
        XCTAssertTrue(settings.isValid)
        settings.chunkDuration = "2"
        XCTAssertFalse(settings.isValid)
        settings.chunkDuration = "15"
        settings.speakerCount = "0"
        XCTAssertFalse(settings.isValid)
        settings.speakerCount = "3"
        XCTAssertTrue(settings.isValid)
        settings.language = "   "
        XCTAssertFalse(settings.isValid)
    }

    func testInvalidPostRecordingSettingsLeaveCurrentConfigurationUntouched() {
        let viewModel = makeViewModel()
        viewModel.queueSession(for: "/tmp/recorded-conference.m4a")
        let id = viewModel.librarySessions[0].id
        let initialProfile = viewModel.selectedProfileID
        let settings = PostRecordingRunSettings(
            profileID: "missing-profile", language: "ru", chunkDuration: "30",
            timestamps: false, diarization: true, speakerCount: "0", aliasesText: ""
        )
        XCTAssertFalse(viewModel.applyPostRecordingSettings(settings, to: id))
        XCTAssertEqual(viewModel.selectedProfileID, initialProfile)
        XCTAssertFalse(viewModel.diarizationEnabled)
    }

    func testRequeueingACompletedSessionReusesItsRowInsteadOfDuplicating() {
        let viewModel = makeViewModel()
        viewModel.queueSession(for: "/tmp/meeting.m4a")
        let id = viewModel.librarySessions[0].id

        viewModel.updateSession(path: "/tmp/meeting.m4a") { $0.status = .done }
        XCTAssertEqual(viewModel.librarySessions.count, 1)

        // Simulate a re-run being queued for the same source file after it already finished.
        viewModel.queueSession(for: "/tmp/meeting.m4a")

        XCTAssertEqual(viewModel.librarySessions.count, 1)
        XCTAssertEqual(viewModel.librarySessions[0].id, id)
        XCTAssertEqual(viewModel.librarySessions[0].status, .queued)
    }
}
