import AppKit
import Combine
import ServiceManagement
import XCTest
@testable import TypeLessBuddy

@MainActor
final class ShellPreferencesModelTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testLaunchAtLoginReflectsCurrentSystemRegistrationState() {
        let (_, preferences) = makePreferences()
        XCTAssertEqual(preferences.launchAtLogin, SMAppService.mainApp.status == .enabled)
    }

    // MARK: - rewriteModelTier tests (Phase 3)

    func testRewriteModelTierDefaultsToStandard2B() {
        let (_, preferences) = makePreferences()
        XCTAssertEqual(preferences.rewriteModelTier, .standard2B)
    }

    func testAlwaysAutoPasteDefaultsToTrue() {
        let (_, preferences) = makePreferences()
        XCTAssertTrue(preferences.alwaysAutoPaste)
    }

    func testAlwaysAutoPastePersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.alwaysAutoPaste = true

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertTrue(preferences2.alwaysAutoPaste)
    }

    func testAlwaysAutoPasteResetRestoresDefault() {
        let (_, preferences) = makePreferences()
        preferences.alwaysAutoPaste = false
        preferences.reset()
        XCTAssertTrue(preferences.alwaysAutoPaste)
    }

    func testRestorePreviousClipboardAfterAutoPasteDefaultsToTrue() {
        let (_, preferences) = makePreferences()
        XCTAssertTrue(preferences.restorePreviousClipboardAfterAutoPaste)
    }

    func testRestorePreviousClipboardAfterAutoPastePersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.restorePreviousClipboardAfterAutoPaste = false

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertFalse(preferences2.restorePreviousClipboardAfterAutoPaste)
    }

    func testRestorePreviousClipboardAfterAutoPasteResetRestoresDefault() {
        let (_, preferences) = makePreferences()
        preferences.restorePreviousClipboardAfterAutoPaste = false
        preferences.reset()
        XCTAssertTrue(preferences.restorePreviousClipboardAfterAutoPaste)
    }

    func testMuteSoundEffectsDefaultsToFalse() {
        let (_, preferences) = makePreferences()
        XCTAssertFalse(preferences.muteSoundEffects)
    }

    func testMuteSoundEffectsPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.muteSoundEffects = true

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertTrue(preferences2.muteSoundEffects)
    }

    func testMuteSoundEffectsResetRestoresDefault() {
        let (_, preferences) = makePreferences()
        preferences.muteSoundEffects = true
        preferences.reset()
        XCTAssertFalse(preferences.muteSoundEffects)
    }

    func testRecordingPillPositionDefaultsToBottomCenter() {
        let (_, preferences) = makePreferences()
        XCTAssertEqual(preferences.recordingPillPosition, .bottomCenter)
    }

    func testRecordingPillPositionPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.recordingPillPosition = .topRight

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences2.recordingPillPosition, .topRight)
    }

    func testRecordingPillPositionResetRestoresDefault() {
        let (_, preferences) = makePreferences()
        preferences.recordingPillPosition = .centerLeft
        preferences.reset()
        XCTAssertEqual(preferences.recordingPillPosition, .bottomCenter)
    }

    func testInvalidStoredRecordingPillPositionFallsBackToDefault() {
        let (defaults, _) = makePreferences()
        defaults.set("sideways", forKey: ShellPreferences.Keys.recordingPillPosition)

        let preferences = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences.recordingPillPosition, .bottomCenter)
    }

    func testRecordingPillPanelPositioningReturnsExpectedOrigins() {
        let visibleFrame = CGRect(x: 100, y: 200, width: 1000, height: 700)
        let panelSize = NSSize(width: 220, height: 44)

        XCTAssertEqual(
            RecordingPillPanelPositioning.origin(for: .topLeft, in: visibleFrame, panelSize: panelSize),
            CGPoint(x: 124, y: 828)
        )
        XCTAssertEqual(
            RecordingPillPanelPositioning.origin(for: .topCenter, in: visibleFrame, panelSize: panelSize),
            CGPoint(x: 490, y: 828)
        )
        XCTAssertEqual(
            RecordingPillPanelPositioning.origin(for: .topRight, in: visibleFrame, panelSize: panelSize),
            CGPoint(x: 856, y: 828)
        )
        XCTAssertEqual(
            RecordingPillPanelPositioning.origin(for: .centerLeft, in: visibleFrame, panelSize: panelSize),
            CGPoint(x: 124, y: 528)
        )
        XCTAssertEqual(
            RecordingPillPanelPositioning.origin(for: .centerRight, in: visibleFrame, panelSize: panelSize),
            CGPoint(x: 856, y: 528)
        )
        XCTAssertEqual(
            RecordingPillPanelPositioning.origin(for: .bottomLeft, in: visibleFrame, panelSize: panelSize),
            CGPoint(x: 124, y: 240)
        )
        XCTAssertEqual(
            RecordingPillPanelPositioning.origin(for: .bottomCenter, in: visibleFrame, panelSize: panelSize),
            CGPoint(x: 490, y: 240)
        )
        XCTAssertEqual(
            RecordingPillPanelPositioning.origin(for: .bottomRight, in: visibleFrame, panelSize: panelSize),
            CGPoint(x: 856, y: 240)
        )
    }

    func testRewriteSystemPromptPrefixDefaultsToBuiltInPrompt() {
        let (_, preferences) = makePreferences()
        XCTAssertEqual(
            preferences.rewriteSystemPromptPrefix,
            LLMRewriteService.defaultAssistantSystemPromptTemplate
        )
    }

    func testRewriteSystemPromptPrefixPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.rewriteSystemPromptPrefix = "Custom system prompt"

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences2.rewriteSystemPromptPrefix, "Custom system prompt")
    }

    func testRewriteSystemPromptPrefixResetRestoresDefault() {
        let (_, preferences) = makePreferences()
        preferences.rewriteSystemPromptPrefix = "Custom system prompt"
        preferences.reset()

        XCTAssertEqual(
            preferences.rewriteSystemPromptPrefix,
            LLMRewriteService.defaultAssistantSystemPromptTemplate
        )
    }

    func testBlankStoredRewriteSystemPromptPrefixResolvesToDefault() {
        let (defaults, _) = makePreferences()
        defaults.set("   ", forKey: ShellPreferences.Keys.rewriteSystemPromptPrefix)

        let preferences = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(
            preferences.rewriteSystemPromptPrefix,
            LLMRewriteService.defaultAssistantSystemPromptTemplate
        )
    }

    func testLegacyStoredRewritePromptPrefixMigratesToAssistantDefault() {
        let (defaults, _) = makePreferences()
        defaults.set(
            LLMRewriteService.legacyDefaultRewritePromptPrefix,
            forKey: ShellPreferences.Keys.rewriteSystemPromptPrefix
        )

        let preferences = ShellPreferences(userDefaults: defaults)

        XCTAssertEqual(
            preferences.rewriteSystemPromptPrefix,
            LLMRewriteService.defaultAssistantSystemPromptTemplate
        )
        XCTAssertEqual(
            defaults.string(forKey: ShellPreferences.Keys.rewriteSystemPromptPrefix),
            LLMRewriteService.defaultAssistantSystemPromptTemplate
        )
    }

    // MARK: - holdShortcut tests

    func testHoldShortcutDefaultsToRightOption() {
        let (_, preferences) = makePreferences()
        XCTAssertEqual(preferences.holdShortcutKeyCode, 61)
        XCTAssertEqual(preferences.holdShortcutModifiers, 0)
    }

    func testHoldShortcutPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.holdShortcutKeyCode = 105
        preferences.holdShortcutModifiers = NSEvent.ModifierFlags.control.rawValue

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences2.holdShortcutKeyCode, 105)
        XCTAssertEqual(preferences2.holdShortcutModifiers, NSEvent.ModifierFlags.control.rawValue)
    }

    func testHoldShortcutResetRestoresDefault() {
        let (_, preferences) = makePreferences()
        preferences.holdShortcutKeyCode = 105
        preferences.holdShortcutModifiers = 123
        preferences.reset()
        XCTAssertEqual(preferences.holdShortcutKeyCode, 61)
        XCTAssertEqual(preferences.holdShortcutModifiers, 0)
    }

    func testRewriteModelTierPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.rewriteModelTier = .high9B

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences2.rewriteModelTier, .high9B)
    }

    func testRewriteModelTierResetRestoresDefault() {
        let (_, preferences) = makePreferences()
        preferences.rewriteModelTier = .standard4B
        preferences.reset()
        XCTAssertEqual(preferences.rewriteModelTier, .standard2B)
    }

    func testRewriteModelTierResetRemovesStoredValue() {
        let (defaults, preferences) = makePreferences()
        preferences.rewriteModelTier = .standard4B
        preferences.reset()

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences2.rewriteModelTier, .standard2B)
    }

    func testLegacyLargeTurboWhisperPreferenceMigratesToMedium() {
        let (defaults, _) = makePreferences()
        defaults.set(WhisperModelChoice.legacyLargeTurboRawValue, forKey: ShellPreferences.Keys.whisperModel)

        let preferences = ShellPreferences(userDefaults: defaults)

        XCTAssertEqual(preferences.whisperModel, .mediumEN)
        XCTAssertEqual(
            defaults.string(forKey: ShellPreferences.Keys.whisperModel),
            WhisperModelChoice.mediumEN.rawValue
        )
    }

    func testResetAssistantNameToDefaultClearsCustomTrigger() async {
        let (_, preferences) = makePreferences(
            initialTriggerProfile: TriggerProfile(
                activeProfile: .custom,
                customPrimary: "Nova Prime"
            )
        )

        let didReset = await preferences.persistAssistantNameResetToDefault()
        XCTAssertTrue(didReset)
        XCTAssertEqual(preferences.activeTriggerProfile, .defaultProfile)
    }

    private func makePreferences(
        initialTriggerProfile: TriggerProfile? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (UserDefaults, ShellPreferences) {
        let suiteName = "ShellPreferencesModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test defaults", file: file, line: line)
            fatalError("Unable to create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (
            defaults,
            ShellPreferences(
                userDefaults: defaults,
                triggerProfileStore: TriggerProfileStore(
                    storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
                ),
                initialTriggerProfile: initialTriggerProfile
            )
        )
    }
}
