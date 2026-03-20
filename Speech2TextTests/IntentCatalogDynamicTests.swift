import XCTest
@testable import Speech2Text

// MARK: - IntentCatalog.effective(store:) tests

final class IntentCatalogDynamicTests: XCTestCase {

    // MARK: - effective(store:) — no overrides

    func testEffectiveWithEmptyStoreReturnsSixDefinitions() {
        let result = IntentCatalog.effective(store: [])
        XCTAssertEqual(result.count, 6, "Should match IntentCatalog.all count")
    }

    func testEffectiveWithEmptyStoreMatchesAll() {
        let all = IntentCatalog.all
        let result = IntentCatalog.effective(store: [])
        XCTAssertEqual(result.map(\.mode), all.map(\.mode), "Modes should match all when no overrides")
    }

    // MARK: - effective(store:) — built-in override replaces phrasePatterns and keywordSignal

    func testEffectiveBuiltInOverrideReplacesPhrasePatterns() {
        let emailOverride = UserIntentEntry(
            id: ConvertMode.email.rawValue,
            modeName: "Email",
            systemPrompt: "custom email prompt",
            phrasePatterns: ["custom phrase one", "custom phrase two"],
            keywordSignal: "mail",
            isBuiltIn: true
        )
        let result = IntentCatalog.effective(store: [emailOverride])

        // Email definition should have overridden phrasePatterns
        let emailDef = result.first(where: { $0.mode == .email })
        XCTAssertNotNil(emailDef, "Email definition should exist")
        XCTAssertEqual(emailDef?.phrasePatterns, ["custom phrase one", "custom phrase two"],
                       "phrasePatterns should be replaced by store override")
        XCTAssertEqual(emailDef?.keywordSignal, "mail",
                       "keywordSignal should be replaced by store override")
    }

    func testEffectiveBuiltInOverrideDoesNotAffectOtherDefinitions() {
        let emailOverride = UserIntentEntry(
            id: ConvertMode.email.rawValue,
            modeName: "Email",
            systemPrompt: "custom email prompt",
            phrasePatterns: ["custom phrase"],
            keywordSignal: "mail",
            isBuiltIn: true
        )
        let result = IntentCatalog.effective(store: [emailOverride])
        let original = IntentCatalog.all

        // All other 5 definitions should be unchanged
        for def in original where def.mode != .email {
            let resultDef = result.first(where: { $0.mode == def.mode })
            XCTAssertNotNil(resultDef, "Definition for \(def.mode) should exist")
            XCTAssertEqual(resultDef?.phrasePatterns, def.phrasePatterns,
                           "phrasePatterns for \(def.mode) should be unchanged")
            XCTAssertEqual(resultDef?.keywordSignal, def.keywordSignal,
                           "keywordSignal for \(def.mode) should be unchanged")
        }
    }

    // MARK: - effective(store:) — custom (non-built-in) entries appended

    func testEffectiveCustomEntryAppendsSeventhDefinition() {
        let customEntry = UserIntentEntry(
            id: "my-custom-mode",
            modeName: "My Custom Mode",
            systemPrompt: "custom system prompt",
            phrasePatterns: ["custom trigger phrase"],
            keywordSignal: "custom",
            isBuiltIn: false
        )
        let result = IntentCatalog.effective(store: [customEntry])
        XCTAssertEqual(result.count, 7, "Custom entry should be appended making total 7")
    }

    func testEffectiveCustomEntryIsLast() {
        let customEntry = UserIntentEntry(
            id: "my-custom-mode",
            modeName: "My Custom Mode",
            systemPrompt: "custom system prompt",
            phrasePatterns: ["custom trigger phrase"],
            keywordSignal: "custom",
            isBuiltIn: false
        )
        let result = IntentCatalog.effective(store: [customEntry])
        XCTAssertEqual(result.last?.aliases.first, "My Custom Mode",
                       "Custom entry should be last in result")
    }

    func testEffectiveCustomEntryGetPassthroughMode() {
        let customEntry = UserIntentEntry(
            id: "my-custom-mode",
            modeName: "My Custom Mode",
            systemPrompt: "custom system prompt",
            phrasePatterns: ["custom trigger phrase"],
            keywordSignal: "custom",
            isBuiltIn: false
        )
        let result = IntentCatalog.effective(store: [customEntry])
        let customDef = result.last
        XCTAssertEqual(customDef?.mode, .passthrough,
                       "Custom entry gets .passthrough as mode (no new ConvertMode cases)")
    }

    func testEffectiveCustomEntryPhrasePatternsComeFromStore() {
        let customEntry = UserIntentEntry(
            id: "my-custom-mode",
            modeName: "My Custom Mode",
            systemPrompt: "custom system prompt",
            phrasePatterns: ["trigger alpha", "trigger beta"],
            keywordSignal: "custom",
            isBuiltIn: false
        )
        let result = IntentCatalog.effective(store: [customEntry])
        let customDef = result.last
        XCTAssertEqual(customDef?.phrasePatterns, ["trigger alpha", "trigger beta"],
                       "Custom entry phrasePatterns should come from store")
    }

    func testEffectiveCustomEntryKeywordSignalComeFromStore() {
        let customEntry = UserIntentEntry(
            id: "my-custom-mode",
            modeName: "My Custom Mode",
            systemPrompt: "custom system prompt",
            phrasePatterns: ["trigger alpha"],
            keywordSignal: "mycustom",
            isBuiltIn: false
        )
        let result = IntentCatalog.effective(store: [customEntry])
        let customDef = result.last
        XCTAssertEqual(customDef?.keywordSignal, "mycustom",
                       "Custom entry keywordSignal should come from store")
    }

    // MARK: - ConvertIntent.effectiveSystemPrompt and customIntentID

    func testConvertIntentEffectiveSystemPromptDefaultsToNil() {
        let intent = ConvertIntent(mode: .passthrough, strippedBody: "hello", originalTranscript: "hello")
        XCTAssertNil(intent.effectiveSystemPrompt, "effectiveSystemPrompt should be nil for passthrough")
    }

    func testConvertIntentEffectiveSystemPromptIsAccessible() {
        let intent = ConvertIntent(
            mode: .email,
            strippedBody: "hello",
            originalTranscript: "hello email",
            effectiveSystemPrompt: "custom prompt"
        )
        XCTAssertEqual(intent.effectiveSystemPrompt, "custom prompt",
                       "effectiveSystemPrompt should be accessible")
    }

    func testConvertIntentCustomIntentIDDefaultsToNil() {
        let intent = ConvertIntent(mode: .email, strippedBody: "hello", originalTranscript: "hello")
        XCTAssertNil(intent.customIntentID, "customIntentID should be nil by default")
    }

    func testConvertIntentBackwardCompatInit() {
        // Verify 3-arg init still compiles and sets nil fields
        let intent = ConvertIntent(mode: .email, strippedBody: "hello", originalTranscript: "original")
        XCTAssertEqual(intent.mode, .email)
        XCTAssertEqual(intent.strippedBody, "hello")
        XCTAssertEqual(intent.originalTranscript, "original")
        XCTAssertNil(intent.effectiveSystemPrompt)
        XCTAssertNil(intent.customIntentID)
    }

    // MARK: - IntentDetector.detect(transcript:definitions:) overload

    func testDetectWithDefinitionsReturnsPassthroughForEmptyDefinitions() {
        let result = IntentDetector.detect(transcript: "hello world", definitions: [])
        XCTAssertEqual(result.mode, .passthrough,
                       "Should return passthrough when no definitions provided")
    }

    func testDetectWithDefinitionsMatchesCustomDefinition() {
        let customDef = IntentDefinition(
            mode: .email,
            aliases: ["Email"],
            phrasePatterns: ["send as email", "email this"],
            keywordSignal: "email",
            confidenceThreshold: 0.82
        )
        // An exact match phrase from the custom definition
        let result = IntentDetector.detect(
            transcript: "send as email this is my content",
            definitions: [customDef]
        )
        XCTAssertEqual(result.mode, .email,
                       "Should detect email mode from custom definition")
    }

    func testDetectWithDefinitionsStripsMatchedTrigger() {
        let customDef = IntentDefinition(
            mode: .slack,
            aliases: ["Slack"],
            phrasePatterns: ["post to slack"],
            keywordSignal: "slack",
            confidenceThreshold: 0.82
        )
        let result = IntentDetector.detect(
            transcript: "post to slack hey team what is the status",
            definitions: [customDef]
        )
        XCTAssertEqual(result.mode, .slack)
        XCTAssertFalse(result.strippedBody.lowercased().contains("post to slack"),
                       "strippedBody should not contain the trigger phrase")
    }
}
