import XCTest
@testable import Speech2Text

final class IntentDetectorTests: XCTestCase {
    private let allModes = ConvertMode.allCases

    // MARK: - MODE Metadata (keep GREEN)

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

    func testPassthroughHasEmptyPhraseAndPrompt() {
        XCTAssertEqual(ConvertMode.passthrough.defaultActivationPhrase, "")
        XCTAssertEqual(ConvertMode.passthrough.defaultSystemPrompt, "")
    }

    func testAllCasesHasFiveCases() {
        XCTAssertEqual(ConvertMode.allCases.count, 5)
    }

    func testConvertIntentStoresAllFields() {
        let intent = ConvertIntent(mode: .email, strippedBody: "hello", originalTranscript: "convert to email hello")
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "hello")
        XCTAssertEqual(intent.originalTranscript, "convert to email hello")
    }

    // MARK: - IntentCatalog Structure

    func testIntentCatalogHasFourEntries() {
        XCTAssertEqual(IntentCatalog.all.count, 4)
    }

    func testIntentCatalogContainsEmailEntry() {
        XCTAssertNotNil(IntentCatalog.all.first(where: { $0.mode == .email }))
    }

    func testEmailPhrasePatternContainsMakeThisAnEmail() {
        let emailDef = IntentCatalog.all.first(where: { $0.mode == .email })
        XCTAssertNotNil(emailDef)
        XCTAssertTrue(emailDef!.phrasePatterns.contains("make this an email"),
                      "Expected 'make this an email' in email phrasePatterns")
    }

    func testEmailPhrasePatternContainsBackwardCompatPhrase() {
        let emailDef = IntentCatalog.all.first(where: { $0.mode == .email })
        XCTAssertNotNil(emailDef)
        XCTAssertTrue(emailDef!.phrasePatterns.contains("convert to email"),
                      "Expected 'convert to email' in email phrasePatterns for backward compatibility")
    }

    func testEmailConfidenceThreshold() {
        let emailDef = IntentCatalog.all.first(where: { $0.mode == .email })
        XCTAssertNotNil(emailDef)
        XCTAssertEqual(emailDef!.confidenceThreshold, 0.82, accuracy: 0.001)
    }

    // MARK: - INTENT-01: Leading Zone Detection

    // These tests are RED until Plan 02 replaces hasPrefix/hasSuffix with fuzzy scoring

    func testLeadingParaphraseEmail() {
        // "make this an email" is a new paraphrase — hasPrefix won't match "convert to email" family
        let intent = IntentDetector.detect(
            transcript: "Make this an email send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
    }

    func testLeadingFillerPlusEmail() {
        // Filler "Okay" before paraphrase — OLD detector won't strip fillers
        let intent = IntentDetector.detect(
            transcript: "Okay make this an email send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
    }

    func testLeadingEmailMode() {
        // "Email mode" paraphrase — not in old candidate list
        let intent = IntentDetector.detect(
            transcript: "Email mode send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
    }

    func testLeadingBackwardCompatEmail() {
        // "convert to email" still works — MUST stay GREEN in Plan 02 too (backward compat)
        // Currently GREEN with old detector (exact phrase match)
        let intent = IntentDetector.detect(
            transcript: "convert to email send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
    }

    func testLeadingBackwardCompatEmailUppercase() {
        // Case-insensitive exact phrase — GREEN with old detector
        let intent = IntentDetector.detect(
            transcript: "CONVERT TO EMAIL send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
    }

    func testLeadingTurnIntoSlack() {
        // "Turn into slack" — new paraphrase
        let intent = IntentDetector.detect(
            transcript: "Turn into slack quick channel update",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .slack)
    }

    func testLeadingCleanEnglish() {
        // "Clean this up" — new paraphrase
        let intent = IntentDetector.detect(
            transcript: "Clean this up this draft needs work",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .cleanEnglish)
    }

    func testLeadingTeams() {
        // "Format for teams" — in catalog; old "format teams" was candidate but "format for teams" is new
        let intent = IntentDetector.detect(
            transcript: "Format for teams this is an update for the team channel",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .teams)
    }

    func testLeadingWhisperLeadingSpacePreserved() {
        // Whisper sometimes produces a leading space
        let intent = IntentDetector.detect(
            transcript: " Make this an email send this",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
    }

    // --- Fuzzy paraphrase tests (require real Jaro-Winkler in Plan 02) ---

    func testLeadingParaphraseEmailAsAMail() {
        // "As a mail" — paraphrase not in catalog; requires fuzzy matching
        let intent = IntentDetector.detect(
            transcript: "As a mail send this report to the board",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
    }

    func testLeadingParaphraseSlackUpdate() {
        // "Slack this update" — not in catalog; requires fuzzy matching
        let intent = IntentDetector.detect(
            transcript: "Slack this update quick note for the channel",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .slack)
    }

    func testLeadingNormalizationEMailVariant() {
        // "E mail mode" with space — requires normalization: "e mail" → "email"
        let intent = IntentDetector.detect(
            transcript: "E mail mode send this project update",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
    }

    // MARK: - INTENT-02: Trailing Zone Detection

    // These tests are RED until Plan 02 replaces hasSuffix with fuzzy scoring

    func testTrailingParaphraseEmail() {
        // "make this an email" trailing — new paraphrase
        let intent = IntentDetector.detect(
            transcript: "Send this to the team make this an email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "Send this to the team")
    }

    func testTrailingEmailModeWithPeriod() {
        // "email mode." trailing with terminal punctuation
        let intent = IntentDetector.detect(
            transcript: "Send this to the team email mode.",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "Send this to the team")
    }

    func testTrailingBackwardCompatEmail() {
        // "convert to email" trailing — GREEN with old detector
        let intent = IntentDetector.detect(
            transcript: "Send this to the team convert to email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "Send this to the team")
    }

    func testTrailingFormatToSlack() {
        // "format to slack" trailing backward compat — GREEN with old detector
        let intent = IntentDetector.detect(
            transcript: "Quick update for the channel format to slack",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .slack)
    }

    func testTrailingTurnIntoTeams() {
        // "turn into teams" trailing — new paraphrase
        let intent = IntentDetector.detect(
            transcript: "This update is for the team turn into teams",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .teams)
    }

    func testTrailingRewriteAsCleanEnglish() {
        // "rewrite as clean english" trailing — new paraphrase
        let intent = IntentDetector.detect(
            transcript: "This draft needs work rewrite as clean english",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .cleanEnglish)
    }

    func testTrailingFillerAfterEmailMode() {
        // "email mode please" trailing with filler word
        let intent = IntentDetector.detect(
            transcript: "Send this to the team email mode please",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "Send this to the team")
    }

    // --- Fuzzy trailing paraphrase tests (require real Jaro-Winkler in Plan 02) ---

    func testTrailingFuzzyParaphraseEmail() {
        // "send as an email" — not exact catalog match; requires fuzzy scoring
        let intent = IntentDetector.detect(
            transcript: "Here is the project summary send as an email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
    }

    func testTrailingNormalizationEMailSpace() {
        // "e mail mode" with space — requires normalization: "e mail" → "email"
        let intent = IntentDetector.detect(
            transcript: "This needs to go out e mail mode",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
    }

    // MARK: - INTENT-03: Case-Insensitive, Span Removal, originalTranscript

    // These tests are RED until Plan 02 provides case-insensitive fuzzy detection

    func testMixedCaseLeadingParaphrase() {
        let intent = IntentDetector.detect(
            transcript: "Make This An Email send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
    }

    func testUpperCaseLeadingParaphrase() {
        let intent = IntentDetector.detect(
            transcript: "MAKE THIS AN EMAIL send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
    }

    func testMixedCaseTrailingParaphrase() {
        let intent = IntentDetector.detect(
            transcript: "Send this to the team Make This An Email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
    }

    func testStrippedBodyHasNoCommandSpanTrailing() {
        // Trailing detection: strippedBody should be only the body content, not the command
        let intent = IntentDetector.detect(
            transcript: "Send this to the team make this an email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertFalse(intent.strippedBody.lowercased().contains("email"),
                       "strippedBody should not contain the command span")
    }

    func testOriginalTranscriptPreservedLeading() {
        let raw = "Make this an email send this to the team"
        let intent = IntentDetector.detect(transcript: raw, modes: allModes)
        XCTAssertEqual(intent.originalTranscript, raw)
    }

    func testOriginalTranscriptPreservedTrailing() {
        let raw = "Send this to the team make this an email"
        let intent = IntentDetector.detect(transcript: raw, modes: allModes)
        XCTAssertEqual(intent.originalTranscript, raw)
    }

    func testOnlyCommandTrailingReturnsEmptyBody() {
        // Only the command phrase → strippedBody = ""
        let intent = IntentDetector.detect(
            transcript: "make this an email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "")
    }

    func testOnlyCommandLeadingReturnsEmptyBody() {
        // "email mode" is the whole transcript
        let intent = IntentDetector.detect(
            transcript: "email mode",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "")
    }

    func testTrailingWinsWhenBothZonesDetect() {
        // "convert to email" leading, "convert to slack" trailing → slack wins
        let intent = IntentDetector.detect(
            transcript: "convert to email body text convert to slack",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .slack)
        XCTAssertEqual(intent.strippedBody, "convert to email body text")
    }

    func testTrailingWinnerPreservesLeadingCommandLikeContentForParserAlignedFlow() {
        let intent = IntentDetector.detect(
            transcript: "convert to email first draft convert to slack",
            modes: allModes
        )

        XCTAssertEqual(intent.mode, .slack)
        XCTAssertEqual(intent.strippedBody, "convert to email first draft")
    }

    // MARK: - Passthrough (false-positive guard)

    // These tests must stay GREEN after Plan 02 — they guard against false positives

    func testPlainDictationReturnsPassthrough() {
        let intent = IntentDetector.detect(
            transcript: "send this to the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .passthrough)
        XCTAssertEqual(intent.strippedBody, "send this to the team")
        XCTAssertEqual(intent.originalTranscript, "send this to the team")
    }

    func testIncidentalEmailMentionReturnsPassthrough() {
        // "email" in the body, not as a command — position guard prevents false positive
        let intent = IntentDetector.detect(
            transcript: "I got an email about the project and should reply",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .passthrough)
    }

    func testEmptyTranscriptReturnsPassthrough() {
        let intent = IntentDetector.detect(
            transcript: "",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .passthrough)
        XCTAssertEqual(intent.strippedBody, "")
    }

    func testBareKeywordEmailReturnsPassthrough() {
        // "email the team" — keyword without command framing, below threshold
        let intent = IntentDetector.detect(
            transcript: "email the team",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .passthrough)
    }

    func testSingleTokenEmailReturnsPassthrough() {
        // Single bare keyword "email" alone — too short, threshold not met
        let intent = IntentDetector.detect(
            transcript: "email",
            modes: allModes
        )
        XCTAssertEqual(intent.mode, .passthrough)
    }

    // MARK: - Phase 14 post-trigger shortcut policy (RED for 14-01 Task 1)

    func testTriggerInstructionLeadingShortcutFallsBackToPassthrough() {
        let intent = IntentDetector.detect(
            transcript: "convert to email send this update to the team",
            definitions: IntentCatalog.all
        )

        XCTAssertEqual(intent.mode, .passthrough)
    }

    func testTriggerInstructionMixedIntentStyleDirectiveFallsBackToPassthrough() {
        let intent = IntentDetector.detect(
            transcript: "make this an email but keep it casual and short",
            definitions: IntentCatalog.all
        )

        XCTAssertEqual(intent.mode, .passthrough)
    }

    func testTriggerInstructionAmbiguousBuiltInTieFallsBackToPassthrough() {
        let intent = IntentDetector.detect(
            transcript: "convert to email or convert to slack",
            definitions: IntentCatalog.all
        )

        XCTAssertEqual(intent.mode, .passthrough)
    }

    func testTriggerInstructionClearTrailingShortcutResolvesToBuiltIn() {
        let intent = IntentDetector.detect(
            transcript: "please send this update to the team convert to slack",
            definitions: IntentCatalog.all
        )

        XCTAssertEqual(intent.mode, .slack)
        XCTAssertEqual(intent.strippedBody, "please send this update to the team")
    }
}
