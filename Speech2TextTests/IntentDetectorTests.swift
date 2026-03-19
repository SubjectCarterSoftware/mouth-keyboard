import XCTest
@testable import Speech2Text

final class IntentDetectorTests: XCTestCase {
    private let allModes = ConvertMode.allCases

    // MARK: - MODE metadata tests (MODE-01 through MODE-06)

    func testCleanEnglishHasActivationPhrase() {
        XCTAssertEqual(ConvertMode.cleanEnglish.defaultActivationPhrase, "convert to clean english")
    }

    func testCleanEnglishHasSystemPrompt() {
        XCTAssertEqual(ConvertMode.cleanEnglish.defaultSystemPrompt, "You are a transcription editor. The user will provide raw dictated text. Remove filler words (um, uh, like, you know, so), fix grammar and punctuation, and preserve the speaker's natural voice and vocabulary. Do not add, remove, or rephrase the meaning. Return only the cleaned text, no commentary.")
    }

    func testEmailHasActivationPhrase() {
        XCTAssertEqual(ConvertMode.email.defaultActivationPhrase, "convert to email")
    }

    func testEmailHasSystemPrompt() {
        XCTAssertEqual(ConvertMode.email.defaultSystemPrompt, "You are an email writer. Convert the user's raw dictated text into a professional email with: a subject line (prefixed \"Subject:\"), a professional body, and an appropriate sign-off (e.g. \"Best,\" or \"Thanks,\"). Keep the tone professional but natural. Return only the formatted email, no commentary.")
    }

    func testSlackHasActivationPhrase() {
        XCTAssertEqual(ConvertMode.slack.defaultActivationPhrase, "convert to slack")
    }

    func testSlackHasSystemPrompt() {
        XCTAssertEqual(ConvertMode.slack.defaultSystemPrompt, "You are a Slack message writer. Convert the user's raw dictated text into a concise Slack message: casual tone, short and scannable, no greeting or sign-off, use line breaks for readability on longer messages. Return only the message text, no commentary.")
    }

    func testTeamsHasActivationPhrase() {
        XCTAssertEqual(ConvertMode.teams.defaultActivationPhrase, "convert to teams")
    }

    func testTeamsHasSystemPrompt() {
        XCTAssertEqual(ConvertMode.teams.defaultSystemPrompt, "You are a Microsoft Teams message writer. Convert the user's raw dictated text into a concise Teams message: casual tone, short and scannable, no greeting or sign-off, use line breaks for readability on longer messages. Return only the message text, no commentary.")
    }

    func testActionItemsHasActivationPhrase() {
        XCTAssertEqual(ConvertMode.actionItems.defaultActivationPhrase, "convert to action items")
    }

    func testActionItemsHasSystemPrompt() {
        XCTAssertEqual(ConvertMode.actionItems.defaultSystemPrompt, "You are an action item extractor. Extract all action items from the user's raw dictated text as a bullet list. For each item include the owner (if mentioned) and deadline (if mentioned), formatted as \"• [Action] — [Owner] by [Deadline]\" (omit fields not mentioned). Return only the bullet list, no commentary.")
    }

    func testAiPromptHasActivationPhrase() {
        XCTAssertEqual(ConvertMode.aiPrompt.defaultActivationPhrase, "convert to ai prompt")
    }

    func testAiPromptHasSystemPrompt() {
        XCTAssertEqual(ConvertMode.aiPrompt.defaultSystemPrompt, "You are an AI prompt writer. Structure the user's raw dictated text as a well-formed AI prompt with three sections: 1) Context (background the AI needs), 2) Task (the specific ask), 3) Output format (how the response should look). Return only the structured prompt, no commentary.")
    }

    func testEmailHasAllActivationPhraseCandidates() {
        XCTAssertEqual(
            ConvertMode.email.activationPhraseCandidates,
            ["convert to email", "format to email", "convert email", "format email"]
        )
    }

    func testPassthroughHasNoActivationPhraseCandidates() {
        XCTAssertEqual(ConvertMode.passthrough.activationPhraseCandidates, [])
    }

    func testPassthroughHasEmptyPhraseAndPrompt() {
        XCTAssertEqual(ConvertMode.passthrough.defaultActivationPhrase, "")
        XCTAssertEqual(ConvertMode.passthrough.defaultSystemPrompt, "")
    }

    func testAllCasesHasSevenCases() {
        XCTAssertEqual(ConvertMode.allCases.count, 7)
    }

    func testConvertIntentStoresAllFields() {
        let intent = ConvertIntent(mode: .email, strippedBody: "hello", originalTranscript: "convert to email hello")

        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "hello")
        XCTAssertEqual(intent.originalTranscript, "convert to email hello")
    }

    func testDetectStubReturnsConvertIntent() {
        let intent = IntentDetector.detect(transcript: "convert to email hello", modes: allModes)

        XCTAssertEqual(intent.mode, .passthrough)
        XCTAssertEqual(intent.strippedBody, "convert to email hello")
        XCTAssertEqual(intent.originalTranscript, "convert to email hello")
    }

    // MARK: - INTENT-01: Leading trigger detection

    func testLeadingTriggerEmail() {
        let intent = IntentDetector.detect(
            transcript: "Convert to email send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
        XCTAssertEqual(intent.originalTranscript, "Convert to email send this to the team")
    }

    func testLeadingTriggerUppercase() {
        let intent = IntentDetector.detect(
            transcript: "CONVERT TO EMAIL send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
    }

    func testLeadingTriggerMixedCase() {
        let intent = IntentDetector.detect(
            transcript: "Convert To Email send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
    }

    func testLeadingTriggerFormatToPrefix() {
        let intent = IntentDetector.detect(
            transcript: "format to slack quick update here",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .slack)
        XCTAssertEqual(intent.strippedBody, "quick update here")
    }

    func testLeadingTriggerConvertShortPrefix() {
        let intent = IntentDetector.detect(
            transcript: "convert clean english this needs fixing",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .cleanEnglish)
        XCTAssertEqual(intent.strippedBody, "this needs fixing")
    }

    func testLeadingTriggerFormatShortPrefix() {
        let intent = IntentDetector.detect(
            transcript: "format action items call bob tomorrow",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .actionItems)
        XCTAssertEqual(intent.strippedBody, "call bob tomorrow")
    }

    func testLeadingTriggerTwoWordModeActionItems() {
        let intent = IntentDetector.detect(
            transcript: "Convert to action items call bob tomorrow",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .actionItems)
        XCTAssertEqual(intent.strippedBody, "call bob tomorrow")
    }

    func testLeadingTriggerAiPrompt() {
        let intent = IntentDetector.detect(
            transcript: "Convert to ai prompt make me a story",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .aiPrompt)
        XCTAssertEqual(intent.strippedBody, "make me a story")
    }

    func testLeadingTriggerWithWhisperLeadingSpace() {
        let intent = IntentDetector.detect(
            transcript: " Convert to email send this",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this")
    }

    // MARK: - INTENT-02: Trailing trigger detection

    func testTrailingTriggerEmail() {
        let intent = IntentDetector.detect(
            transcript: "send this to the team convert to email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
        XCTAssertEqual(intent.originalTranscript, "send this to the team convert to email")
    }

    func testTrailingTriggerWithPeriod() {
        let intent = IntentDetector.detect(
            transcript: "send this to the team convert to email.",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
    }

    func testTrailingTriggerTwoWordModeCleanEnglish() {
        let intent = IntentDetector.detect(
            transcript: "this needs cleanup convert to clean english",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .cleanEnglish)
        XCTAssertEqual(intent.strippedBody, "this needs cleanup")
    }

    func testTrailingTriggerFormatToPrefix() {
        let intent = IntentDetector.detect(
            transcript: "quick update for the channel format to slack",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .slack)
        XCTAssertEqual(intent.strippedBody, "quick update for the channel")
    }

    func testTrailingTriggerConvertShortPrefix() {
        let intent = IntentDetector.detect(
            transcript: "this draft needs cleanup convert clean english",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .cleanEnglish)
        XCTAssertEqual(intent.strippedBody, "this draft needs cleanup")
    }

    func testTrailingTriggerFormatShortPrefixWithPunctuation() {
        let intent = IntentDetector.detect(
            transcript: "call bob tomorrow format action items!",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .actionItems)
        XCTAssertEqual(intent.strippedBody, "call bob tomorrow")
    }

    // MARK: - INTENT-03: Case-insensitive, end-wins, passthrough

    func testEndWinsWhenBothLeadingAndTrailingPresent() {
        let intent = IntentDetector.detect(
            transcript: "convert to email body text convert to slack",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .slack)
        XCTAssertEqual(intent.strippedBody, "body text")
    }

    func testNoTriggerReturnsPassthrough() {
        let intent = IntentDetector.detect(
            transcript: "send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .passthrough)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
        XCTAssertEqual(intent.originalTranscript, "send this to the team")
    }

    func testBareModenameNoPrefix() {
        let intent = IntentDetector.detect(
            transcript: "email send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .passthrough)
    }

    func testTrailingBareModeNameNoPrefix() {
        let intent = IntentDetector.detect(
            transcript: "send this to the team email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .passthrough)
    }

    func testOnlyTriggerPhraseReturnsEmptyBody() {
        let intent = IntentDetector.detect(
            transcript: "convert to email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "")
    }

    func testEmptyTranscriptReturnsPassthrough() {
        let intent = IntentDetector.detect(
            transcript: "",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .passthrough)
        XCTAssertEqual(intent.strippedBody, "")
    }

    func testOriginalTranscriptPreservedOnMatch() {
        let raw = "Convert To Email send this to the team"
        let intent = IntentDetector.detect(transcript: raw, modes: allModes)
        XCTAssertEqual(intent.originalTranscript, raw)
    }
}
