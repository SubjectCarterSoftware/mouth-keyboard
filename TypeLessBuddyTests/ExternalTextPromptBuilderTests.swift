import XCTest
@testable import TypeLessBuddy

final class ExternalTextPromptBuilderTests: XCTestCase {
    private func singleSourceDecision(
        _ targetMode: AssistantContextTargetMode,
        label: String
    ) -> AssistantContextRoutingDecision {
        AssistantContextRoutingDecision(
            matchedSources: [
                AssistantContextMatchedSource(targetMode: targetMode, promptLabel: label)
            ],
            decisionSource: .explicitFastPath
        )
    }

    // MARK: - Word-boundary matching

    func testInformalDoesNotTriggerProfessionalRewrite() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "rewrite my clipboard in an informal way",
            selectedText: nil,
            clipboardText: "Hey team, big news.",
            routingDecision: singleSourceDecision(.clipboard, label: "my clipboard")
        )

        XCTAssertFalse(body.contains("more professional and polished"))
    }

    func testMeansDoesNotTriggerToneSoftening() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "explain what my clipboard means",
            selectedText: nil,
            clipboardText: "API rate limit exceeded.",
            routingDecision: singleSourceDecision(.clipboard, label: "my clipboard")
        )

        XCTAssertFalse(body.contains("kinder"))
        XCTAssertFalse(body.contains("Remove insults"))
    }

    func testSlackingDoesNotTriggerSlackFormat() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "summarize my clipboard about people slacking off",
            selectedText: nil,
            clipboardText: "Notes about the team.",
            routingDecision: singleSourceDecision(.clipboard, label: "my clipboard")
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
                    targetMode: .lastTranscription,
                    promptLabel: "my last transcription"
                ),
                AssistantContextMatchedSource(
                    targetMode: .clipboard,
                    promptLabel: "my clipboard"
                ),
            ],
            decisionSource: .explicitFastPath
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
            routingDecision: singleSourceDecision(.lastTranscription, label: "my last transcription")
        )

        XCTAssertTrue(body.contains("Only include actions that are still open or need follow-up."))
        XCTAssertTrue(body.contains("Do not include completed, resolved, cleared, already-done, informational, or explicitly excluded items as action items."))
        XCTAssertTrue(body.contains("If the source says not to list something as open, omit that item entirely."))
    }
}
