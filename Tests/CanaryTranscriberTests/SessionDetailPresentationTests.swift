import XCTest
@testable import CanaryTranscriber
@testable import CanaryTranscriberCore

final class SessionDetailPresentationTests: XCTestCase {
    func testFailedRerunReloadsPreviouslySavedTranscript() {
        XCTAssertTrue(SessionDetailView.shouldReloadTranscript(after: .failed))
        XCTAssertTrue(SessionDetailView.shouldReloadTranscript(after: .done))
        XCTAssertFalse(SessionDetailView.shouldReloadTranscript(after: .processing))
        XCTAssertFalse(SessionDetailView.shouldReloadTranscript(after: .queued))
    }
}
