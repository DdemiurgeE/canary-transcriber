import XCTest
@testable import CanaryTranscriber
@testable import CanaryTranscriberCore

final class TranscriptionViewModelLibraryTests: XCTestCase {
    private func makeViewModel() -> TranscriptionViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TranscriptionViewModelLibraryTests-\(UUID().uuidString)", isDirectory: true)
        let suite = "CanaryTranscriberTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return TranscriptionViewModel(
            aliasPersistence: SpeakerAliasPersistence(defaults: defaults),
            libraryStore: SessionLibraryStore(directoryURL: directory),
            persistentLogURL: directory.appendingPathComponent("test.log")
        )
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

    func testSuccessfulRerunUsesChosenBatchConfigWithoutChangingNextBatchSettings() throws {
        let viewModel = makeViewModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CanaryRerun-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording.m4a")
        try Data("fixture".utf8).write(to: source)
        viewModel.writeNextToSource = false
        viewModel.outputFolder = directory.path
        viewModel.pythonPath = "/usr/bin/true" // No MLX or user audio is invoked.
        viewModel.speakerAliasesText = "SPEAKER_00 = Original"
        viewModel.queueSession(for: source.path)
        viewModel.updateSession(path: source.path) {
            $0.status = .done
            $0.jsonPath = directory.appendingPathComponent("previous.canary.json").path
        }
        let session = try XCTUnwrap(viewModel.librarySessions.first)
        let settings = PostRecordingRunSettings(
            profileID: "fast-whisper-turbo", language: "en", chunkDuration: "15",
            timestamps: true, diarization: true, speakerCount: "3",
            aliasesText: "SPEAKER_00 = Alice"
        )
        viewModel.requeueForTranscription(sessionIDs: [session.id], forceDiarization: false, settings: settings)
        XCTAssertTrue(viewModel.isRunning)
        let configPath = try XCTUnwrap(viewModel.currentConfigPath)
        let config = try JSONDecoder().decode(BatchConfig.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
        XCTAssertEqual(config.profileID, settings.profileID)
        XCTAssertEqual(config.language, settings.language)
        XCTAssertEqual(config.chunkDuration, 15)
        XCTAssertTrue(config.timestamps)
        XCTAssertTrue(config.diarization)
        XCTAssertEqual(config.speakerCount, 3)
        XCTAssertEqual(config.speakerAliases["SPEAKER_00"], "Alice")
        XCTAssertTrue(config.outputSuffix?.hasPrefix("rerun-") == true)
        XCTAssertEqual(viewModel.selectedProfileID, "multilingual-canary-v2")
        XCTAssertEqual(viewModel.language, "ru")
        XCTAssertFalse(viewModel.diarizationEnabled)
        XCTAssertEqual(viewModel.speakerAliasesText, "SPEAKER_00 = Original")
        let deadline = Date().addingTimeInterval(3)
        while viewModel.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.librarySessions.first?.status, .failed)
        XCTAssertEqual(viewModel.librarySessions.first?.jsonPath, session.jsonPath)
        XCTAssertFalse(viewModel.logs.contains("✅ Batch completed successfully."))
    }

    func testExecutableThatCannotLaunchRestoresCompletedSessionAndRemovesConfig() throws {
        let viewModel = makeViewModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CanaryLaunchFailure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording.m4a")
        try Data("fixture".utf8).write(to: source)
        let invalidExecutable = directory.appendingPathComponent("invalid-python")
        try Data("not a program".utf8).write(to: invalidExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: invalidExecutable.path)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: invalidExecutable.path))
        viewModel.pythonPath = invalidExecutable.path
        viewModel.writeNextToSource = false
        viewModel.outputFolder = directory.path
        viewModel.queueSession(for: source.path)
        let previousJSON = directory.appendingPathComponent("previous.canary.json").path
        viewModel.updateSession(path: source.path) {
            $0.status = .done
            $0.jsonPath = previousJSON
        }
        let session = try XCTUnwrap(viewModel.librarySessions.first)
        viewModel.requeueForTranscription(
            sessionIDs: [session.id], forceDiarization: false,
            settings: viewModel.postRecordingSettings(for: session)
        )
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.librarySessions.first?.status, .done)
        XCTAssertEqual(viewModel.librarySessions.first?.jsonPath, previousJSON)
        XCTAssertNil(viewModel.currentConfigPath)
    }

    func testQueueRestorationKeepsFilesAddedDuringRerun() {
        let viewModel = makeViewModel()
        viewModel.suspendedQueuedFiles = [AudioFileItem(path: "/tmp/queued.m4a")]
        viewModel.suspendedRerunPaths = ["/tmp/rerun.m4a"]
        viewModel.files = [
            AudioFileItem(path: "/tmp/rerun.m4a"),
            AudioFileItem(path: "/tmp/new-during-run.m4a")
        ]
        viewModel.restoreSuspendedQueue()
        XCTAssertEqual(viewModel.files.map(\.path), ["/tmp/queued.m4a", "/tmp/new-during-run.m4a"])
        XCTAssertNil(viewModel.suspendedQueuedFiles)
    }

    func testFailedPostRecordingRerunPreservesOtherQueuedFiles() {
        let viewModel = makeViewModel()
        viewModel.queueSession(for: "/tmp/previously-transcribed.m4a")
        viewModel.updateSession(path: "/tmp/previously-transcribed.m4a") { $0.status = .done }
        let doneID = viewModel.librarySessions[0].id
        viewModel.files = [AudioFileItem(path: "/tmp/newly-recorded.m4a")]
        viewModel.queueSession(for: "/tmp/newly-recorded.m4a")
        viewModel.pythonPath = "/no/such/python"
        var settings = viewModel.postRecordingSettings(for: viewModel.librarySessions[0])
        settings.profileID = "fast-whisper-turbo"
        settings.language = "en"
        viewModel.requeueForTranscription(
            sessionIDs: [doneID], forceDiarization: false, settings: settings
        )
        XCTAssertEqual(viewModel.files.map(\.path), ["/tmp/newly-recorded.m4a"])
        XCTAssertEqual(viewModel.librarySessions.first(where: { $0.id == doneID })?.status, .done)
        XCTAssertEqual(viewModel.selectedProfileID, "multilingual-canary-v2")
        XCTAssertEqual(viewModel.language, "ru")
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
