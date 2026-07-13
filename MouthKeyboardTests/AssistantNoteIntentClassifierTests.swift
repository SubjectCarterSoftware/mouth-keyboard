import XCTest
@testable import MouthKeyboard

final class AssistantNoteIntentClassifierTests: XCTestCase {
    func testPositivePhrasesRequestAutomaticNoteSave() {
        for phrase in AssistantNoteIntentClassifier.positivePhrases {
            let classification = AssistantNoteIntentClassifier.classify(
                message: "Buddy \(phrase) turn this into a task list",
                matchedAlias: "Buddy"
            )

            XCTAssertTrue(
                classification.requestsAutomaticNoteSave,
                "Expected phrase to match: \(phrase)"
            )
            XCTAssertEqual(classification.matchedPhrase, phrase)
        }
    }

    func testGenericNotePhrasesDoNotMatch() {
        let nonMatches = [
            "Buddy write a note thanking the team",
            "Buddy draft a note for the release",
            "Buddy write a thank-you note to Sam",
            "Buddy summarize the release notes",
            "Buddy summarize my meeting notes",
            "Buddy create notes for the presentation",
            "Buddy create a note to self",
            "Buddy take note of the risks",
            "Buddy remember this for later",
            "Buddy remember that for next time",
        ]

        for message in nonMatches {
            let classification = AssistantNoteIntentClassifier.classify(
                message: message,
                matchedAlias: "Buddy"
            )

            XCTAssertFalse(
                classification.requestsAutomaticNoteSave,
                "Expected message to avoid note-save matching: \(message)"
            )
            XCTAssertNil(classification.matchedPhrase)
            XCTAssertEqual(classification.sanitizedPrompt, message)
        }
    }

    func testLongestPhraseWinsWhenMultiplePhrasesAppear() {
        let classification = AssistantNoteIntentClassifier.classify(
            message: "Buddy note this down and save this as a note for later",
            matchedAlias: "Buddy"
        )

        XCTAssertEqual(classification.matchedPhrase, "save this as a note")
        XCTAssertEqual(classification.sanitizedPrompt, "Buddy note this down for later")
    }

    func testSanitizedPromptRemovesMatchedPhraseFromStart() {
        let classification = AssistantNoteIntentClassifier.classify(
            message: "Make a note of this turn this into bullets",
            matchedAlias: "Buddy"
        )

        XCTAssertEqual(classification.sanitizedPrompt, "turn this into bullets")
    }

    func testSanitizedPromptRemovesMatchedPhraseFromMiddle() {
        let classification = AssistantNoteIntentClassifier.classify(
            message: "Buddy please make a note of this and turn this into bullets",
            matchedAlias: "Buddy"
        )

        XCTAssertEqual(classification.sanitizedPrompt, "Buddy please turn this into bullets")
    }

    func testSanitizedPromptRemovesMatchedPhraseFromEnd() {
        let classification = AssistantNoteIntentClassifier.classify(
            message: "Buddy turn this into bullets and make a note of this",
            matchedAlias: "Buddy"
        )

        XCTAssertEqual(classification.sanitizedPrompt, "Buddy turn this into bullets")
    }

    func testSanitizedPromptFallsBackWhenStrippingLeavesOnlyAlias() {
        let classification = AssistantNoteIntentClassifier.classify(
            message: "Buddy make a note of this",
            matchedAlias: "Buddy"
        )

        XCTAssertEqual(classification.matchedPhrase, "make a note of this")
        XCTAssertEqual(classification.sanitizedPrompt, "Buddy make a note of this")
    }
}
