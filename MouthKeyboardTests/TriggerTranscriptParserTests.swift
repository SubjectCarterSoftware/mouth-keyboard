import XCTest
@testable import MouthKeyboard

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
            transcript: "Draft note for finance team. BUDDY polish this into an email update",
            triggerName: "buddy"
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: "Draft note for finance team. BUDDY polish this into an email update",
                matchedAlias: "buddy"
            )
        )
    }

    func testCommaAfterTriggerStillActivatesNamedAssistantInstruction() {
        let transcript = """
        Okay, I have a couple of meetings tomorrow. I have one about my Q3 and Q4 bigger features that we need to commit to and iron those out. There's like five or six things on that list and then I have a call with a different customer later about a different feature and I have like a business lineage feature working on as well. Buddy, can you put that in the format of an email just for an update that I'm going to send to my team?
        """
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            triggerName: "buddy"
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: transcript,
                matchedAlias: "buddy"
            )
        )
    }

    func testNoTriggerMatchReturnsNoTriggerPassthrough() {
        let transcript = "Please send this to finance before noon."
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            triggerName: "buddy"
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
        let transcript = "buddy summarize this as three bullets"
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            triggerName: "buddy"
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: transcript,
                matchedAlias: "buddy"
            )
        )
    }

    func testNormalizeTranscriptRemovesBlankAudioMarkers() {
        let normalized = TriggerTranscriptParser.normalizeTranscript(
            "buddy [BLANK_AUDIO] summarize this (blank audio) <blank_audio> please"
        )

        XCTAssertEqual(normalized, "buddy summarize this please")
    }

    func testDetectUsesNormalizedTranscriptForTriggerMatching() {
        let detection = TriggerTranscriptParser.detect(
            transcript: "[BLANK_AUDIO] buddy summarize this",
            triggerName: "buddy"
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: "buddy summarize this",
                matchedAlias: "buddy"
            )
        )
    }

    func testDefaultAlternateSpellingStillTriggers() {
        let transcript = "buddie summarize this as three bullets"
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            triggerNames: TriggerProfile.defaultProfile.allCanonicalNames
        )

        XCTAssertEqual(
            detection,
            .triggered(
                transcript: transcript,
                matchedAlias: "buddie"
            )
        )
    }

    func testEmptyTriggerNameDoesNotMatch() {
        let transcript = "buddy summarize this"
        let detection = TriggerTranscriptParser.detect(
            transcript: transcript,
            triggerName: ""
        )

        XCTAssertEqual(detection, .noTrigger(transcript: transcript))
    }
}
