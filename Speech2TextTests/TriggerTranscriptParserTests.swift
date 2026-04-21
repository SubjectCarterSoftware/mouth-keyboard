import XCTest
@testable import Speech2Text

final class TriggerTranscriptParserTests: XCTestCase {
    func testDetectReturnsLastOccurrenceWhenTriggerAppearsMultipleTimes() {
        let detection = TriggerTranscriptParser.detect(
            transcript: "atlas think of something and then atlas convert it to email",
            triggerName: "atlas"
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: "atlas think of something and then atlas convert it to email",
                matchedAlias: "atlas"
            )
        )
    }

    func testDetectReturnsFullTranscriptWhenTriggerAppearsInMiddle() {
        let detection = TriggerTranscriptParser.detect(
            transcript: "Draft note for finance team. CLANKER polish this into an email update",
            triggerName: "clanker"
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: "Draft note for finance team. CLANKER polish this into an email update",
                matchedAlias: "clanker"
            )
        )
    }

    func testCommaAfterTriggerStillActivatesNamedAssistantInstruction() {
        let transcript = """
        Okay, I have a couple of meetings tomorrow. I have one about my Q3 and Q4 bigger features that we need to commit to and iron those out. There's like five or six things on that list and then I have a call with a different customer later about a different feature and I have like a business lineage feature working on as well. Clanker, can you put that in the format of an email just for an update that I'm going to send to my team?
        """
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            triggerName: "clanker"
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: transcript,
                matchedAlias: "clanker"
            )
        )
    }

    func testNoTriggerMatchReturnsNoTriggerPassthrough() {
        let transcript = "Please send this to finance before noon."
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            triggerName: "clanker"
        )

        XCTAssertEqual(detection, .noTrigger(transcript: transcript))
    }

    func testSingleWordAfterTriggerStillActivates() {
        let detection = TriggerTranscriptParser.detect(
            transcript: "atlas email",
            triggerName: "atlas"
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
            triggerName: "atlas"
        )

        XCTAssertEqual(detection, .noTrigger(transcript: transcript))
    }

    func testAssistantNameAtStartTriggers() {
        let transcript = "clanker summarize this as three bullets"
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            triggerName: "clanker"
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: transcript,
                matchedAlias: "clanker"
            )
        )
    }

    func testEmptyTriggerNameDoesNotMatch() {
        let transcript = "clanker summarize this"
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            triggerName: ""
        )

        XCTAssertEqual(detection, .noTrigger(transcript: transcript))
    }
}
