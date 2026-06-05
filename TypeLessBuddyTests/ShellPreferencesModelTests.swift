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

    func testLegacyRewriteTierMigrationKeepsBuiltInSelection() {
        let (defaults, _) = makePreferences()
        defaults.set(RewriteModelTier.high9B.rawValue, forKey: ShellPreferences.Keys.rewriteModelTier)
        defaults.set(Data("legacy-selection".utf8), forKey: "assistantModelSelection")
        defaults.set(Data("legacy-models".utf8), forKey: "customAssistantModels")

        let preferences = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences.rewriteModelTier, .high9B)
        XCTAssertNil(defaults.object(forKey: "assistantModelSelection"))
        XCTAssertNil(defaults.object(forKey: "customAssistantModels"))
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

    func testMouseButtonBindingsDefaultToUnset() {
        let (_, preferences) = makePreferences()

        XCTAssertNil(preferences.startMouseButtonBinding)
        XCTAssertNil(preferences.stopMouseButtonBinding)
        XCTAssertNil(preferences.holdMouseButtonBinding)
    }

    func testMouseButtonBindingsPersistRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.startMouseButtonBinding = MouseButtonBinding(buttonNumber: 4)
        preferences.stopMouseButtonBinding = MouseButtonBinding(buttonNumber: 5)
        preferences.holdMouseButtonBinding = MouseButtonBinding(buttonNumber: 3)

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences2.startMouseButtonBinding, MouseButtonBinding(buttonNumber: 4))
        XCTAssertEqual(preferences2.stopMouseButtonBinding, MouseButtonBinding(buttonNumber: 5))
        XCTAssertEqual(preferences2.holdMouseButtonBinding, MouseButtonBinding(buttonNumber: 3))
    }

    func testInvalidStoredRecordingPillPositionFallsBackToDefault() {
        let (defaults, _) = makePreferences()
        defaults.set("sideways", forKey: ShellPreferences.Keys.recordingPillPosition)

        let preferences = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences.recordingPillPosition, .bottomCenter)
    }

    func testAssistantNoteModeDefaultsToNewFile() {
        let (_, preferences) = makePreferences()
        XCTAssertEqual(preferences.assistantNoteMode, .newFile)
    }

    func testAssistantNoteSettingsPersistRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.assistantNoteMode = .appendToFile
        preferences.assistantNoteFolderPath = "/tmp/notes-folder"
        preferences.assistantNoteAppendFilePath = "/tmp/notes.md"

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences2.assistantNoteMode, .appendToFile)
        XCTAssertEqual(preferences2.assistantNoteFolderPath, "/tmp/notes-folder")
        XCTAssertEqual(preferences2.assistantNoteAppendFilePath, "/tmp/notes.md")
    }

    func testInvalidStoredAssistantNoteModeFallsBackToNewFile() {
        let (defaults, _) = makePreferences()
        defaults.set("sideways", forKey: ShellPreferences.Keys.assistantNoteMode)

        let preferences = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences.assistantNoteMode, .newFile)
    }

    func testAssistantNotePathsAreTrimmedWhenSet() {
        let (_, preferences) = makePreferences()
        preferences.assistantNoteFolderPath = "  /tmp/notes-folder  "
        preferences.assistantNoteAppendFilePath = "  /tmp/notes.md  "

        XCTAssertEqual(preferences.assistantNoteFolderPath, "/tmp/notes-folder")
        XCTAssertEqual(preferences.assistantNoteAppendFilePath, "/tmp/notes.md")
    }

    func testAssistantNoteConfigurationUsesActiveModeDestination() {
        let (_, preferences) = makePreferences()
        preferences.assistantNoteMode = .newFile
        preferences.assistantNoteFolderPath = "/tmp/notes-folder"
        preferences.assistantNoteAppendFilePath = "/tmp/notes.md"
        XCTAssertEqual(
            preferences.assistantNoteConfiguration,
            AssistantNoteConfiguration(
                mode: .newFile,
                folderPath: "/tmp/notes-folder",
                appendFilePath: "/tmp/notes.md"
            )
        )

        preferences.assistantNoteMode = .appendToFile
        XCTAssertEqual(
            preferences.assistantNoteConfiguration,
            AssistantNoteConfiguration(
                mode: .appendToFile,
                folderPath: "/tmp/notes-folder",
                appendFilePath: "/tmp/notes.md"
            )
        )
    }

    func testHistoryDefaultsToDisabledWithDefaultCap() {
        let (_, preferences) = makePreferences()

        XCTAssertFalse(preferences.historyEnabled)
        XCTAssertEqual(preferences.historyStorageLimitMB, 500)
        XCTAssertEqual(preferences.historyFolderPath, "")
    }

    func testHistorySettingsPersistRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.historyEnabled = true
        preferences.historyFolderPath = "/tmp/history-folder"
        preferences.historyStorageLimitMB = 250

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertTrue(preferences2.historyEnabled)
        XCTAssertEqual(preferences2.historyFolderPath, "/tmp/history-folder")
        XCTAssertEqual(preferences2.historyStorageLimitMB, 250)
    }

    func testHistoryFolderPathIsTrimmedWhenSet() {
        let (_, preferences) = makePreferences()
        preferences.historyFolderPath = "  /tmp/history-folder  "

        XCTAssertEqual(preferences.historyFolderPath, "/tmp/history-folder")
    }

    func testHistoryConfigurationResolvesDefaultFolderWhenUnset() {
        let (_, preferences) = makePreferences()

        XCTAssertEqual(
            preferences.historyConfiguration,
            HistoryConfiguration(
                isEnabled: false,
                folderPath: "",
                storageLimitMB: 500
            )
        )
        XCTAssertEqual(
            preferences.historyConfiguration.resolvedFolderPath,
            StoreURLResolver.directoryURL(named: "History").path
        )
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

    func testRewriteModelTierPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.rewriteModelTier = .high9B

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences2.rewriteModelTier, .high9B)
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

    func testOnboardingPresentsWhenBuildIdentifierChanges() {
        let (defaults, preferences) = makePreferences(currentBuildIdentifier: "build-A")
        preferences.acknowledgeOnboardingForCurrentBuild()

        let nextPreferences = ShellPreferences(
            userDefaults: defaults,
            currentBuildIdentifier: "build-B"
        )

        XCTAssertTrue(nextPreferences.shouldPresentOnboardingOnLaunch)
    }

    func testOnboardingDoesNotPresentAfterAcknowledgingCurrentBuild() {
        let (_, preferences) = makePreferences(currentBuildIdentifier: "build-A")
        preferences.acknowledgeOnboardingForCurrentBuild()

        XCTAssertFalse(preferences.shouldPresentOnboardingOnLaunch)
    }

    func testOnboardingResumeTokenPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences(currentBuildIdentifier: "build-A")
        preferences.setOnboardingResumeToken("speechEngine")

        let preferences2 = ShellPreferences(
            userDefaults: defaults,
            currentBuildIdentifier: "build-A"
        )

        XCTAssertEqual(preferences2.onboardingResumeToken, "speechEngine")
    }

    func testRestoreDefaultGeneralSettingsRestoresDefaults() {
        let (_, preferences) = makePreferences()
        preferences.promoteMicDevice("usb-mic")
        preferences.alwaysAutoPaste = false
        preferences.restorePreviousClipboardAfterAutoPaste = false
        preferences.muteSoundEffects = true
        preferences.recordingPillPosition = .centerLeft

        preferences.restoreDefaultGeneralSettings()

        XCTAssertTrue(preferences.micDeviceUIDs.isEmpty)
        XCTAssertTrue(preferences.alwaysAutoPaste)
        XCTAssertTrue(preferences.restorePreviousClipboardAfterAutoPaste)
        XCTAssertFalse(preferences.muteSoundEffects)
        XCTAssertEqual(preferences.recordingPillPosition, .bottomCenter)
    }

    func testRestoreDefaultHoldShortcutsRestoresDefaults() {
        let (_, preferences) = makePreferences()
        preferences.holdShortcutKeyCode = 105
        preferences.holdShortcutModifiers = NSEvent.ModifierFlags.control.rawValue
        preferences.holdShortcutKeyCodeAlt = 106
        preferences.holdShortcutModifiersAlt = NSEvent.ModifierFlags.shift.rawValue

        preferences.restoreDefaultHoldShortcuts()

        XCTAssertEqual(preferences.holdShortcutKeyCode, ShellPreferences.defaultHoldShortcutKeyCode)
        XCTAssertEqual(preferences.holdShortcutModifiers, ShellPreferences.defaultHoldShortcutModifiers)
        XCTAssertEqual(preferences.holdShortcutKeyCodeAlt, ShellPreferences.defaultHoldShortcutKeyCodeAlt)
        XCTAssertEqual(preferences.holdShortcutModifiersAlt, ShellPreferences.defaultHoldShortcutModifiersAlt)
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

    func testClearWordReplacementsRemovesAllEntries() async {
        let (_, preferences) = makePreferences()
        var data = DictionaryData.empty
        data.replacements = [
            WordReplacement(originals: ["gonna"], replacement: "going to"),
            WordReplacement(originals: ["wanna"], replacement: "want to"),
        ]
        _ = await preferences.persistDictionaryData(data)

        preferences.clearWordReplacements()

        for _ in 0..<50 {
            if preferences.activeDictionaryData.replacements.isEmpty {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(preferences.activeDictionaryData.replacements.isEmpty)
    }

    func testClearWordReplacementsKeepsPackContributedEntries() async {
        let (_, preferences) = makePreferences()
        var data = DictionaryData.empty
        data.replacements = [
            WordReplacement(originals: ["gonna"], replacement: "going to"),
            WordReplacement(
                originals: ["type script"],
                replacement: "TypeScript",
                sourcePackIDs: ["role.software-developer"]
            ),
        ]
        data.enabledPackIDs = ["role.software-developer"]
        _ = await preferences.persistDictionaryData(data)

        preferences.clearWordReplacements()

        for _ in 0..<50 {
            if preferences.activeDictionaryData.replacements.count == 1 {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(preferences.activeDictionaryData.replacements.map(\.replacement), ["TypeScript"])
        XCTAssertEqual(preferences.activeDictionaryData.enabledPackIDs, ["role.software-developer"])
    }

    private func makePreferences(
        initialTriggerProfile: TriggerProfile? = nil,
        initialDictionaryData: DictionaryData? = nil,
        currentBuildIdentifier: String = "test-build",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (UserDefaults, ShellPreferences) {
        let suiteName = "ShellPreferencesModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test defaults", file: file, line: line)
            fatalError("Unable to create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let tempDirectory = FileManager.default.temporaryDirectory
        return (
            defaults,
            ShellPreferences(
                userDefaults: defaults,
                triggerProfileStore: TriggerProfileStore(
                    storeURL: tempDirectory.appendingPathComponent(UUID().uuidString + ".json")
                ),
                dictionaryStore: DictionaryStore(
                    storeURL: tempDirectory.appendingPathComponent(UUID().uuidString + ".dictionary.json")
                ),
                initialTriggerProfile: initialTriggerProfile,
                initialDictionaryData: initialDictionaryData,
                currentBuildIdentifier: currentBuildIdentifier
            )
        )
    }
}
