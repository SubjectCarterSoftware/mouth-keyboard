import XCTest
@testable import Speech2Text

final class TriggerTranscriptParserTests: XCTestCase {
    func testLastNameWinsUsesLastAliasOccurrenceAsTrigger() {
        let detection = TriggerTranscriptParser.detect(
            transcript: "Zeus this stays content atlas convert to email the weekly recap",
            activeAliases: ["zeus", "atlas"]
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: "Zeus this stays content atlas convert to email the weekly recap",
                matchedAlias: "atlas"
            )
        )
    }

    func testDetectReturnsFullTranscriptWhenAliasAppearsInMiddle() {
        let detection = TriggerTranscriptParser.detect(
            transcript: "Draft note for finance team. ZEUS polish this into an email update",
            activeAliases: ["zeus"]
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: "Draft note for finance team. ZEUS polish this into an email update",
                matchedAlias: "zeus"
            )
        )
    }

    func testCommaAfterTriggerStillActivatesNamedAssistantInstruction() {
        let transcript = """
        Okay, I have a couple of meetings tomorrow. I have one about my Q3 and Q4 bigger features that we need to commit to and iron those out. There's like five or six things on that list and then I have a call with a different customer later about a different feature and I have like a business lineage feature working on as well. Zeus, can you put that in the format of an email just for an update that I'm going to send to my team?
        """
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            activeAliases: ["zeus"]
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: transcript,
                matchedAlias: "zeus"
            )
        )
    }

    func testNoAliasMatchReturnsNoTriggerPassthrough() {
        let transcript = "Please send this to finance before noon."
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            activeAliases: ["zeus", "atlas"]
        )

        XCTAssertEqual(detection, .noTrigger(transcript: transcript))
    }

    func testSingleWordAfterAliasStillActivates() {
        let detection = TriggerTranscriptParser.detect(
            transcript: "atlas email",
            activeAliases: ["atlas"]
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: "atlas email",
                matchedAlias: "atlas"
            )
        )
    }

    func testContentMentionsWithoutValidBoundaryDoNotActivate() {
        let transcript = "The atlases are in the office drawer."
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            activeAliases: ["atlas"]
        )

        XCTAssertEqual(detection, .noTrigger(transcript: transcript))
    }

    func testAssistantNameAtStartTriggers() {
        let transcript = "zeus summarize this as three bullets"
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            activeAliases: ["zeus"]
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: transcript,
                matchedAlias: "zeus"
            )
        )
    }
}
