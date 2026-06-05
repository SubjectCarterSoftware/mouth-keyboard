import XCTest
@testable import TypeLessBuddy

final class ExternalTextSourceClassifierTests: XCTestCase {
    private func context(
        selected: Bool = false,
        clipboard: Bool = false,
        transcription: Bool = false
    ) -> ExternalTextSourceContext {
        ExternalTextSourceContext(
            selectedTextAvailable: selected,
            clipboardTextAvailable: clipboard,
            lastTranscriptionAvailable: transcription
        )
    }

    func testWholeWordSourcePhraseMatches() {
        let decision = ExternalTextSourceClassifier.classify(
            message: "summarize my clipboard",
            availableSources: context(clipboard: true)
        )

        XCTAssertEqual(decision.decisionSource, .explicitFastPath)
        XCTAssertEqual(decision.targetModes, [.clipboard])
    }

    func testSubstringDoesNotMatchSourcePhrase() {
        // "the selections" must not match the "the selection" phrase via substring.
        let decision = ExternalTextSourceClassifier.classify(
            message: "open the selections page",
            availableSources: context(selected: true)
        )

        XCTAssertEqual(decision.decisionSource, .noDeterministicMatch)
        XCTAssertTrue(decision.matchedSources.isEmpty)
    }

    func testPluralTranscriptionWordDoesNotMatch() {
        let decision = ExternalTextSourceClassifier.classify(
            message: "review the transcriptions later",
            availableSources: context(transcription: true)
        )

        XCTAssertEqual(decision.decisionSource, .noDeterministicMatch)
        XCTAssertTrue(decision.matchedSources.isEmpty)
    }

    func testMultipleSourcesMatchInAppendOrder() {
        let decision = ExternalTextSourceClassifier.classify(
            message: "combine my last transcription and my clipboard",
            availableSources: context(clipboard: true, transcription: true)
        )

        XCTAssertEqual(decision.decisionSource, .explicitFastPath)
        XCTAssertEqual(decision.targetModes, [.lastTranscription, .clipboard])
    }
}
