import XCTest
@testable import Speech2Text

final class TriggerTranscriptParserTests: XCTestCase {
    func testLastNameWinsUsesLastAliasOccurrenceAsBoundary() {
        let split = TriggerTranscriptParser.split(
            transcript: "Zeus this stays content atlas convert to email the weekly recap",
            activeAliases: ["zeus", "atlas"]
        )

        XCTAssertEqual(
            split,
            .validTrigger(
                content: "Zeus this stays content",
                instruction: "convert to email the weekly recap",
                matchedAlias: "atlas"
            )
        )
    }

    func testSplitPreservesPreBoundaryContent() {
        let split = TriggerTranscriptParser.split(
            transcript: "Draft note for finance team. ZEUS polish this into an email update",
            activeAliases: ["zeus"]
        )

        XCTAssertEqual(
            split,
            .validTrigger(
                content: "Draft note for finance team.",
                instruction: "polish this into an email update",
                matchedAlias: "zeus"
            )
        )
    }

    func testNoAliasMatchReturnsNoTriggerPassthrough() {
        let transcript = "Please send this to finance before noon."
        let split = TriggerTranscriptParser.split(
            transcript: transcript,
            activeAliases: ["zeus", "atlas"]
        )

        XCTAssertEqual(split, .noTrigger(transcript: transcript))
    }

    func testTooShortInstructionReturnsNonActivatingResult() {
        let split = TriggerTranscriptParser.split(
            transcript: "atlas email",
            activeAliases: ["atlas"]
        )

        XCTAssertEqual(
            split,
            .invalidTrigger(
                content: "",
                instruction: "email",
                matchedAlias: "atlas",
                reason: .instructionTooShort(minimumTokens: 2, actualTokens: 1)
            )
        )
    }

    func testContentMentionsWithoutValidBoundaryDoNotActivate() {
        let transcript = "The atlases are in the office drawer."
        let split = TriggerTranscriptParser.split(
            transcript: transcript,
            activeAliases: ["atlas"]
        )

        XCTAssertEqual(split, .noTrigger(transcript: transcript))
    }
}
