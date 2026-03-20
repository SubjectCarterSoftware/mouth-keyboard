import XCTest
@testable import Speech2Text

final class TriggerCalibrationSessionTests: XCTestCase {
    func testRequiresThreeValidSamplesBeforeCompletion() {
        var session = TriggerCalibrationSession(primaryName: "Zeus")

        XCTAssertFalse(session.isComplete)
        XCTAssertEqual(session.recordSample(CalibrationSample(rawTranscript: "zeus")), .accepted)
        XCTAssertEqual(session.recordSample(CalibrationSample(rawTranscript: "  zeus  ")), .accepted)
        XCTAssertFalse(session.isComplete)

        XCTAssertEqual(session.recordSample(CalibrationSample(rawTranscript: "assistant zeus")), .completed)
        XCTAssertTrue(session.isComplete)
    }

    func testNilEmptyAndNoiseSamplesRequestRetryWithoutAdvancing() {
        var session = TriggerCalibrationSession(primaryName: "Zeus")

        XCTAssertEqual(session.recordSample(nil), .retry)
        XCTAssertEqual(session.recordSample(CalibrationSample(rawTranscript: "  ")), .retry)
        XCTAssertEqual(session.recordSample(CalibrationSample(rawTranscript: "z")), .retry)

        XCTAssertEqual(session.recordSample(CalibrationSample(rawTranscript: "zeus")), .accepted)
        XCTAssertEqual(session.recordSample(CalibrationSample(rawTranscript: "zeus")), .accepted)
        XCTAssertEqual(session.recordSample(CalibrationSample(rawTranscript: "zeus")), .completed)
        XCTAssertTrue(session.isComplete)
    }

    func testFinalizedAliasesContainCanonicalPrimaryName() {
        var session = TriggerCalibrationSession(primaryName: "  ZEUS ")
        _ = session.recordSample(CalibrationSample(rawTranscript: "assistant zeus"))
        _ = session.recordSample(CalibrationSample(rawTranscript: "hey zeus"))
        _ = session.recordSample(CalibrationSample(rawTranscript: "ZEUS"))

        XCTAssertEqual(
            session.finalizedAliases(),
            ["zeus", "assistant zeus", "hey zeus"]
        )
    }

    func testRerunCalibrationReplacesPriorAliasSet() {
        var firstSession = TriggerCalibrationSession(primaryName: "Zeus")
        _ = firstSession.recordSample(CalibrationSample(rawTranscript: "assistant zeus"))
        _ = firstSession.recordSample(CalibrationSample(rawTranscript: "hey zeus"))
        _ = firstSession.recordSample(CalibrationSample(rawTranscript: "zeus"))
        XCTAssertEqual(firstSession.finalizedAliases(), ["zeus", "assistant zeus", "hey zeus"])

        var rerunSession = TriggerCalibrationSession(primaryName: "Zeus")
        _ = rerunSession.recordSample(CalibrationSample(rawTranscript: "captain zeus"))
        _ = rerunSession.recordSample(CalibrationSample(rawTranscript: "zeus mode"))
        _ = rerunSession.recordSample(CalibrationSample(rawTranscript: "zeus"))
        XCTAssertEqual(rerunSession.finalizedAliases(), ["zeus", "captain zeus", "zeus mode"])
        XCTAssertFalse(rerunSession.finalizedAliases().contains("assistant zeus"))
    }
}
