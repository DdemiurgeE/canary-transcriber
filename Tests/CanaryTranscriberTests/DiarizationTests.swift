import XCTest
@testable import CanaryTranscriberCore

final class DiarizationTests: XCTestCase {
    func testFixtureJSONDecodesNormalSegments() throws {
        let data = Data(#"[{"speaker":"SPEAKER_00","start":0.0,"end":2.5},{"speaker":"SPEAKER_01","start":2.5,"end":5.0}]"#.utf8)
        let segments = try JSONDecoder().decode([DiarizationSegment].self, from: data)

        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(isValid(segments))
        XCTAssertEqual(segments[1].duration, 2.5, accuracy: 0.001)
    }

    func testZeroSegmentsAreValidAndDoNotCreateSpeakers() {
        let result = DiarizationResult.segments([])
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertFalse(result.isFallback)
    }

    func testMalformedSegmentsProduceActionableIssues() {
        let cases: [([DiarizationSegment], DiarizationValidationIssue)] = [
            ([DiarizationSegment(speaker: "", start: 0, end: 1)], .emptySpeaker(index: 0)),
            ([DiarizationSegment(speaker: "SPEAKER_00", start: .nan, end: 1)], .nonFiniteTime(index: 0)),
            ([DiarizationSegment(speaker: "SPEAKER_00", start: -1, end: 1)], .negativeStart(index: 0)),
            ([DiarizationSegment(speaker: "SPEAKER_00", start: 2, end: 1)], .endBeforeStart(index: 0)),
            ([
                DiarizationSegment(speaker: "SPEAKER_00", start: 2, end: 3),
                DiarizationSegment(speaker: "SPEAKER_01", start: 1, end: 2)
            ], .unsorted(index: 1))
        ]

        for (segments, expected) in cases {
            XCTAssertTrue(isFailure(DiarizationValidator.validate(segments), expected))
        }
    }

    func testOverlappingSegmentsAreAllowed() {
        let segments = [
            DiarizationSegment(speaker: "SPEAKER_00", start: 0, end: 3),
            DiarizationSegment(speaker: "SPEAKER_01", start: 2, end: 4)
        ]
        XCTAssertTrue(isValid(segments))
    }

    func testFallbackReasonsAreSpeakerlessAndWarningBearing() {
        let result = DiarizationResult.speakerless(
            reason: .missingConsent,
            warning: "HuggingFace consent is required for pyannote."
        )
        XCTAssertTrue(result.isFallback)
        XCTAssertTrue(result.segments.isEmpty)
        if case .speakerless(let reason, let warning) = result {
            XCTAssertEqual(reason, .missingConsent)
            XCTAssertFalse(warning.isEmpty)
        } else {
            XCTFail("Expected speakerless fallback")
        }
    }

    private func isValid(_ segments: [DiarizationSegment]) -> Bool {
        if case .success = DiarizationValidator.validate(segments) { return true }
        return false
    }

    private func isFailure(_ result: Result<Void, DiarizationValidationIssue>, _ expected: DiarizationValidationIssue) -> Bool {
        if case .failure(let issue) = result { return issue == expected }
        return false
    }
}
