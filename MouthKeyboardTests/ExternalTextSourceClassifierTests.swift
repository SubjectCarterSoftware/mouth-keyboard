import XCTest
@testable import MouthKeyboard

final class LocalModelAssistantContextRouterTests: XCTestCase {
    func testRoutesModelResponseInStableSourceOrderWithoutExposingSourceContents() async throws {
        let generator = ContextRoutingGenerator(response: "SOURCES: SELECTED_TEXT, LAST_TRANSCRIPTION")
        let router = LocalModelAssistantContextRouter(generator: generator)
        let secretSelectedText = "Customer contract renewal is at risk."
        let secretTranscript = "The VP asked us not to disclose this."
        let context = ExternalTextSourceContext(
            selectedText: secretSelectedText,
            clipboardText: nil,
            lastTranscription: secretTranscript
        )

        let decision = try await router.route(
            request: "Compare the highlighted paragraph with the last thing I said.",
            availableSources: context
        )
        let prompt = try await XCTUnwrap(generator.lastPrompt())

        XCTAssertEqual(decision.decisionSource, .modelClassifier)
        XCTAssertEqual(decision.targetModes, [.lastTranscription, .selectedText])
        XCTAssertFalse(prompt.contains(secretSelectedText))
        XCTAssertFalse(prompt.contains(secretTranscript))
        XCTAssertTrue(prompt.contains("SELECTED_TEXT: available"))
        XCTAssertTrue(prompt.contains("LAST_TRANSCRIPTION: available"))
    }

    func testUnavailableModelLabelIsRejectedRatherThanInjected() throws {
        let context = ExternalTextSourceContext(
            selectedTextAvailable: true,
            clipboardTextAvailable: false,
            lastTranscriptionAvailable: false
        )

        XCTAssertThrowsError(
            try LocalModelAssistantContextRouter.parseModes(
                from: "SOURCES: CLIPBOARD",
                availableSources: context
            )
        ) { error in
            XCTAssertEqual(error as? AssistantContextRoutingError, .invalidModelResponse)
        }
    }

    func testMalformedOrMultiLineModelResponseIsRejected() throws {
        let context = ExternalTextSourceContext(
            selectedTextAvailable: true,
            clipboardTextAvailable: true,
            lastTranscriptionAvailable: true
        )

        for response in [
            "SELECTED_TEXT",
            "SOURCES:",
            "SOURCES: NONE\nI selected no source.",
            "SOURCES: SELECTED_TEXT, SELECTED_TEXT",
            "SOURCES: NONE, SELECTED_TEXT",
        ] {
            XCTAssertThrowsError(
                try LocalModelAssistantContextRouter.parseModes(
                    from: response,
                    availableSources: context
                ),
                response
            )
        }
    }

    func testNoAvailableContextSkipsTheModel() async throws {
        let generator = ContextRoutingGenerator(response: "SOURCES: SELECTED_TEXT")
        let router = LocalModelAssistantContextRouter(generator: generator)
        let decision = try await router.route(
            request: "Tighten the highlighted text.",
            availableSources: ExternalTextSourceContext(
                selectedTextAvailable: false,
                clipboardTextAvailable: false,
                lastTranscriptionAvailable: false
            )
        )

        XCTAssertEqual(decision.decisionSource, .noAvailableContext)
        XCTAssertTrue(decision.matchedSources.isEmpty)
        XCTAssertNil(generator.lastPrompt())
    }

    func testUserPromptListsOnlyAvailableLabelsAsPermitted() {
        let prompt = LocalModelAssistantContextRouter.userPrompt(
            request: "Use the previous voice input.",
            availableSources: ExternalTextSourceContext(
                selectedTextAvailable: true,
                clipboardTextAvailable: true,
                lastTranscriptionAvailable: false
            )
        )

        XCTAssertTrue(prompt.contains("CLIPBOARD, SELECTED_TEXT"))
        XCTAssertFalse(prompt.contains("CLIPBOARD, SELECTED_TEXT, LAST_TRANSCRIPTION\n\nSpoken request"))
    }
}

private final class ContextRoutingGenerator: Rewriting, @unchecked Sendable {
    private let response: String
    private let lock = NSLock()
    private var recordedPrompt: String?

    init(response: String) {
        self.response = response
    }

    func rewrite(body _: String, instructions _: String, promptPrefix _: String) async throws -> String {
        response
    }

    func generate(prompt: String, systemPrompt _: String) async throws -> String {
        lock.lock()
        recordedPrompt = prompt
        lock.unlock()
        return response
    }

    func lastPrompt() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return recordedPrompt
    }
}
