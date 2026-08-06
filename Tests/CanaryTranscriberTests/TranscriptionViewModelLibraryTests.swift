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
