import XCTest
@testable import CanaryTranscriberCore

final class SpeakerAliasPersistenceTests: XCTestCase {
    func testRoundTripTrimsInvalidEntriesAndPreservesCommentsAndSeparators() {
        let text = """
        # local aliases
        SPEAKER_00 = Alice
        SPEAKER_01: Bob
        SPEAKER_02\tCarol
        invalid
        SPEAKER_03 =
        """

        let decoded = SpeakerAliasPersistence.decode(text)
        XCTAssertEqual(decoded, [
            "SPEAKER_00": "Alice",
            "SPEAKER_01": "Bob",
            "SPEAKER_02": "Carol"
        ])

        let encoded = SpeakerAliasPersistence.encode(decoded)
        XCTAssertEqual(encoded, "SPEAKER_00 = Alice\nSPEAKER_01 = Bob\nSPEAKER_02 = Carol")
        XCTAssertEqual(SpeakerAliasPersistence.decode(encoded), decoded)
    }

    func testUsesOneStableStorageKey() {
        XCTAssertEqual(SpeakerAliasPersistence.storageKey, speakerAliasesStorageKey)
    }
}
