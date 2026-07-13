import XCTest
@testable import MouthKeyboard

final class ExternalTextPromptBuilderTests: XCTestCase {
    private func singleSourceDecision(
        _ targetMode: AssistantContextTargetMode
    ) -> AssistantContextRoutingDecision {
        AssistantContextRoutingDecision(
            matchedSources: [
                AssistantContextMatchedSource(targetMode: targetMode)
            ],
            decisionSource: .modelClassifier
        )
    }

    // MARK: - Word-boundary matching

    func testInformalDoesNotTriggerProfessionalRewrite() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "rewrite my clipboard in an informal way",
            selectedText: nil,
            clipboardText: "Hey team, big news.",
            routingDecision: singleSourceDecision(.clipboard)
        )

        XCTAssertFalse(body.contains("more professional and polished"))
    }

    func testMeansDoesNotTriggerToneSoftening() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "explain what my clipboard means",
            selectedText: nil,
            clipboardText: "API rate limit exceeded.",
            routingDecision: singleSourceDecision(.clipboard)
        )

        XCTAssertFalse(body.contains("kinder"))
        XCTAssertFalse(body.contains("Remove insults"))
    }

    func testSlackingDoesNotTriggerSlackFormat() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "summarize my clipboard about people slacking off",
            selectedText: nil,
            clipboardText: "Notes about the team.",
            routingDecision: singleSourceDecision(.clipboard)
        )

        XCTAssertFalse(body.contains("Slack-ready update"))
    }

    // MARK: - No-context direct shaping

    func testDirectBodyAppendsBulletShaping() {
        let body = ExternalTextPromptBuilder.buildDirectBody(
            dictatedContent: "write a thank you note and give me three bullets"
        )

        XCTAssertTrue(body.contains("write a thank you note"))
        XCTAssertTrue(body.contains("Format the result as 3 short bullet points."))
        XCTAssertTrue(body.contains("Return only the bullet list."))
    }

    func testDirectBodyAppendsProfessionalShaping() {
        let body = ExternalTextPromptBuilder.buildDirectBody(
            dictatedContent: "draft an email asking for an extension, keep it professional"
        )

        XCTAssertTrue(body.contains("Make the result professional and polished."))
    }

    func testDirectBodyAppendsShortShaping() {
        let body = ExternalTextPromptBuilder.buildDirectBody(
            dictatedContent: "write a short apology note for missing a customer meeting"
        )

        XCTAssertTrue(body.contains("Keep the result short and direct"))
        XCTAssertTrue(body.contains("Preserve concrete facts and constraints from the request"))
        XCTAssertTrue(body.contains("Return only the requested result."))
    }

    func testDirectBodyUnchangedWithoutShapingKeywords() {
        let dictation = "write an email to my boss about the schedule"
        let body = ExternalTextPromptBuilder.buildDirectBody(dictatedContent: dictation)

        XCTAssertEqual(body, dictation)
    }

    // MARK: - Multi-source shaping

    func testMultiSourceRetainsFormatShaping() {
        let decision = AssistantContextRoutingDecision(
            matchedSources: [
                AssistantContextMatchedSource(
                    targetMode: .lastTranscription
                ),
                AssistantContextMatchedSource(
                    targetMode: .clipboard
                ),
            ],
            decisionSource: .modelClassifier
        )

        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "combine my last transcription and my clipboard into bullets",
            selectedText: nil,
            clipboardText: "Clipboard contents.",
            lastTranscription: "Transcript contents.",
            routingDecision: decision
        )

        XCTAssertTrue(body.contains("bullet"))
        XCTAssertTrue(body.contains("Return only the bullet list."))
        // Neutral context labels are preserved so the model does not try to fetch sources.
        XCTAssertTrue(body.contains("transcript context provided below"))
        XCTAssertTrue(body.contains("copied context provided below"))
    }

    func testActionItemPromptOmitsCompletedOrExcludedItems() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "turn my last transcription into a clean action-item list",
            selectedText: nil,
            clipboardText: nil,
            lastTranscription: "Finance already cleared the export blocker, so do not list that as open.",
            routingDecision: singleSourceDecision(.lastTranscription)
        )

        XCTAssertTrue(body.contains("Only include actions that are still open or need follow-up."))
        XCTAssertTrue(body.contains("Do not include completed, resolved, cleared, already-done, informational, or explicitly excluded items as action items."))
        XCTAssertTrue(body.contains("If the source says not to list something as open, omit that item entirely."))
    }

    func testPossessiveSelectedTextRequestBecomesAnExplicitOneSentenceTransformation() {
        let dictation = "Buddy, can you take the text I've got selected and condense it a little more? It needs to be like a sentence."
        let decision = AssistantContextRoutingDecision(
            matchedSources: [AssistantContextMatchedSource(targetMode: .selectedText)],
            decisionSource: .modelClassifier
        )

        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: dictation,
            selectedText: "The next call should focus on how our data-source definitions, aliases, and lineage mappings work across clouds.",
            clipboardText: nil,
            routingDecision: decision
        )

        XCTAssertTrue(body.contains("User request:\nBuddy, can you take the text I've got selected and condense it a little more? It needs to be like a sentence."))
        XCTAssertTrue(body.contains("Use the selected context provided below as the exact text to transform."))
        XCTAssertTrue(body.contains("Condense it into one direct sentence."))
        XCTAssertTrue(body.contains("Return exactly one sentence."))
        XCTAssertTrue(body.contains("selected context provided below:\n\"The next call should focus"))
    }

    // MARK: - Captured-context grounding

    /// The LLM router routes any phrasing, so the raw request — including
    /// access-implying wording like "read my clipboard" — reaches the rewrite
    /// model verbatim. The grounding lines must always accompany injected
    /// context so the model never claims it lacks access to the source.
    func testAccessImpliedRequestStaysVerbatimAndCarriesGroundingLines() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, read my clipboard and fix the grammar",
            selectedText: nil,
            clipboardText: "we shipped teh fix yesterday",
            routingDecision: singleSourceDecision(.clipboard)
        )

        XCTAssertTrue(body.contains("User request:\nBuddy, read my clipboard and fix the grammar"))
        XCTAssertTrue(body.contains("All of that text was already captured and is included in full below."))
        XCTAssertTrue(body.contains("Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text."))
    }

    func testMultiSourceBodyCarriesGroundingLines() {
        let decision = AssistantContextRoutingDecision(
            matchedSources: [
                AssistantContextMatchedSource(targetMode: .clipboard),
                AssistantContextMatchedSource(targetMode: .selectedText),
            ],
            decisionSource: .modelClassifier
        )

        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, compare what I highlighted with what's on my clipboard",
            selectedText: "Launch stays on Friday.",
            clipboardText: "Launch moved to Monday.",
            routingDecision: decision
        )

        XCTAssertTrue(body.contains("User request:\nBuddy, compare what I highlighted with what's on my clipboard"))
        XCTAssertTrue(body.contains("All of that text was already captured and is included in full below."))
        XCTAssertTrue(body.contains("Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text."))
    }
}
