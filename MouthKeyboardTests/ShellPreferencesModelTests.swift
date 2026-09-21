import AppKit
import Combine
import ServiceManagement
import XCTest
@testable import MouthKeyboard

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

    func testDuckSystemAudioWhileRecordingDefaultsToTrue() {
        let (_, preferences) = makePreferences()
        XCTAssertTrue(preferences.duckSystemAudioWhileRecording)
    }

    func testDuckSystemAudioWhileRecordingPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.duckSystemAudioWhileRecording = false

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertFalse(preferences2.duckSystemAudioWhileRecording)
    }

    func testCollectScreenshotsWhileRecordingDefaultsToTrue() {
        let (_, preferences) = makePreferences()
        XCTAssertTrue(preferences.collectScreenshotsWhileRecording)
    }

    func testCollectScreenshotsWhileRecordingPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.collectScreenshotsWhileRecording = false

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertFalse(preferences2.collectScreenshotsWhileRecording)
    }

    func testSaveScreenshotsToHistoryDefaultsToTrue() {
        let (_, preferences) = makePreferences()
        XCTAssertTrue(preferences.saveScreenshotsToHistory)
    }

    func testSaveScreenshotsToHistoryPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.saveScreenshotsToHistory = false

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertFalse(preferences2.saveScreenshotsToHistory)
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

        XCTAssertTrue(preferences.startMouseButtonBindings.isEmpty)
        XCTAssertTrue(preferences.stopMouseButtonBindings.isEmpty)
        XCTAssertTrue(preferences.holdMouseButtonBindings.isEmpty)
    }

    func testMouseButtonBindingsPersistRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.startMouseButtonBindings = .single(MouseButtonBinding(buttonNumber: 4), slot: .primary)
        preferences.stopMouseButtonBindings = .single(MouseButtonBinding(buttonNumber: 5), slot: .secondary)
        preferences.holdMouseButtonBindings = .single(MouseButtonBinding(buttonNumber: 3), slot: .tertiary)

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences2.startMouseButtonBindings.binding(for: .primary), MouseButtonBinding(buttonNumber: 4))
        XCTAssertEqual(preferences2.stopMouseButtonBindings.binding(for: .secondary), MouseButtonBinding(buttonNumber: 5))
        XCTAssertEqual(preferences2.holdMouseButtonBindings.binding(for: .tertiary), MouseButtonBinding(buttonNumber: 3))
    }

    func testLegacyMouseButtonBindingsMigrateToThirdSlot() {
        let (defaults, _) = makePreferences()
        defaults.set(try? JSONEncoder().encode(MouseButtonBinding(buttonNumber: 4)), forKey: ShellPreferences.Keys.startMouseButtonBinding)
        defaults.set(try? JSONEncoder().encode(MouseButtonBinding(buttonNumber: 5)), forKey: ShellPreferences.Keys.stopMouseButtonBinding)
        defaults.set(try? JSONEncoder().encode(MouseButtonBinding(buttonNumber: 3)), forKey: ShellPreferences.Keys.holdMouseButtonBinding)

        let preferences = ShellPreferences(userDefaults: defaults)

        XCTAssertEqual(preferences.startMouseButtonBindings.binding(for: .tertiary), MouseButtonBinding(buttonNumber: 4))
        XCTAssertEqual(preferences.stopMouseButtonBindings.binding(for: .tertiary), MouseButtonBinding(buttonNumber: 5))
        XCTAssertEqual(preferences.holdMouseButtonBindings.binding(for: .tertiary), MouseButtonBinding(buttonNumber: 3))
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
        preferences.noteSavingEnabled = true
        preferences.assistantNoteMode = .newFile
        preferences.assistantNoteFolderPath = "/tmp/notes-folder"
        preferences.assistantNoteAppendFilePath = "/tmp/notes.md"
        XCTAssertEqual(
            preferences.assistantNoteConfiguration,
            AssistantNoteConfiguration(
                isEnabled: true,
                mode: .newFile,
                folderPath: "/tmp/notes-folder",
                appendFilePath: "/tmp/notes.md"
            )
        )

        preferences.assistantNoteMode = .appendToFile
        XCTAssertEqual(
            preferences.assistantNoteConfiguration,
            AssistantNoteConfiguration(
                isEnabled: true,
                mode: .appendToFile,
                folderPath: "/tmp/notes-folder",
                appendFilePath: "/tmp/notes.md"
            )
        )
    }

    func testNoteSavingEnabledDefaultsToFalseOnCleanInstall() {
        let (defaults, preferences) = makePreferences()

        XCTAssertFalse(preferences.noteSavingEnabled)
        // The derived value is written back so it stays stable across launches.
        XCTAssertNotNil(defaults.object(forKey: ShellPreferences.Keys.noteSavingEnabled))
    }

    func testNoteSavingEnabledPersistsRoundTrip() {
        let (defaults, preferences) = makePreferences()
        preferences.noteSavingEnabled = true

        let preferences2 = ShellPreferences(userDefaults: defaults)
        XCTAssertTrue(preferences2.noteSavingEnabled)
    }

    func testNoteSavingEnabledMigratesFromConfiguredNewFileDestination() {
        let (defaults, _) = makePreferences()
        defaults.removeObject(forKey: ShellPreferences.Keys.noteSavingEnabled)
        defaults.set(AssistantNoteMode.newFile.rawValue, forKey: ShellPreferences.Keys.assistantNoteMode)
        defaults.set("/tmp/notes-folder", forKey: ShellPreferences.Keys.assistantNoteFolderPath)

        let preferences = ShellPreferences(userDefaults: defaults)

        XCTAssertTrue(preferences.noteSavingEnabled)
        XCTAssertEqual(defaults.object(forKey: ShellPreferences.Keys.noteSavingEnabled) as? Bool, true)
    }

    func testNoteSavingEnabledMigratesFromConfiguredAppendDestination() {
        let (defaults, _) = makePreferences()
        defaults.removeObject(forKey: ShellPreferences.Keys.noteSavingEnabled)
        defaults.set(AssistantNoteMode.appendToFile.rawValue, forKey: ShellPreferences.Keys.assistantNoteMode)
        defaults.set("/tmp/notes.md", forKey: ShellPreferences.Keys.assistantNoteAppendFilePath)

        let preferences = ShellPreferences(userDefaults: defaults)

        XCTAssertTrue(preferences.noteSavingEnabled)
    }

    func testNoteSavingEnabledMigrationIgnoresInactiveModeDestination() {
        let (defaults, _) = makePreferences()
        defaults.removeObject(forKey: ShellPreferences.Keys.noteSavingEnabled)
        defaults.set(AssistantNoteMode.newFile.rawValue, forKey: ShellPreferences.Keys.assistantNoteMode)
        defaults.set("/tmp/notes.md", forKey: ShellPreferences.Keys.assistantNoteAppendFilePath)

        let preferences = ShellPreferences(userDefaults: defaults)

        XCTAssertFalse(preferences.noteSavingEnabled)
    }

    func testNoteSavingEnabledExplicitDisableWinsOverConfiguredDestination() {
        let (defaults, _) = makePreferences()
        defaults.set(false, forKey: ShellPreferences.Keys.noteSavingEnabled)
        defaults.set(AssistantNoteMode.newFile.rawValue, forKey: ShellPreferences.Keys.assistantNoteMode)
        defaults.set("/tmp/notes-folder", forKey: ShellPreferences.Keys.assistantNoteFolderPath)

        let preferences = ShellPreferences(userDefaults: defaults)

        XCTAssertFalse(preferences.noteSavingEnabled)
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
            LocalRewriteService.defaultAssistantSystemPromptTemplate
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
            LocalRewriteService.defaultAssistantSystemPromptTemplate
        )
    }

    func testLegacyStoredRewritePromptPrefixMigratesToAssistantDefault() {
        let (defaults, _) = makePreferences()
        defaults.set(
            LocalRewriteService.legacyDefaultRewritePromptPrefix,
            forKey: ShellPreferences.Keys.rewriteSystemPromptPrefix
        )

        let preferences = ShellPreferences(userDefaults: defaults)

        XCTAssertEqual(
            preferences.rewriteSystemPromptPrefix,
            LocalRewriteService.defaultAssistantSystemPromptTemplate
        )
        XCTAssertEqual(
            defaults.string(forKey: ShellPreferences.Keys.rewriteSystemPromptPrefix),
            LocalRewriteService.defaultAssistantSystemPromptTemplate
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
        preferences.duckSystemAudioWhileRecording = false
        preferences.collectScreenshotsWhileRecording = false
        preferences.recordingPillPosition = .centerLeft

        preferences.restoreDefaultGeneralSettings()

        XCTAssertTrue(preferences.micDeviceUIDs.isEmpty)
        XCTAssertTrue(preferences.alwaysAutoPaste)
        XCTAssertTrue(preferences.restorePreviousClipboardAfterAutoPaste)
        XCTAssertFalse(preferences.muteSoundEffects)
        XCTAssertTrue(preferences.duckSystemAudioWhileRecording)
        XCTAssertTrue(preferences.collectScreenshotsWhileRecording)
        XCTAssertEqual(preferences.recordingPillPosition, .bottomCenter)
    }

    func testRestoreDefaultHoldShortcutsRestoresDefaults() {
        let (_, preferences) = makePreferences()
        preferences.holdShortcutKeyCode = 105
        preferences.holdShortcutModifiers = NSEvent.ModifierFlags.control.rawValue
        preferences.holdShortcutKeyCodeAlt = 106
        preferences.holdShortcutModifiersAlt = NSEvent.ModifierFlags.shift.rawValue
        preferences.holdShortcutKeyCodeTertiary = 107
        preferences.holdShortcutModifiersTertiary = NSEvent.ModifierFlags.option.rawValue

        preferences.restoreDefaultHoldShortcuts()

        XCTAssertEqual(preferences.holdShortcutKeyCode, ShellPreferences.defaultHoldShortcutKeyCode)
        XCTAssertEqual(preferences.holdShortcutModifiers, ShellPreferences.defaultHoldShortcutModifiers)
        XCTAssertEqual(preferences.holdShortcutKeyCodeAlt, ShellPreferences.defaultHoldShortcutKeyCodeAlt)
        XCTAssertEqual(preferences.holdShortcutModifiersAlt, ShellPreferences.defaultHoldShortcutModifiersAlt)
        XCTAssertEqual(preferences.holdShortcutKeyCodeTertiary, ShellPreferences.defaultHoldShortcutKeyCodeTertiary)
        XCTAssertEqual(preferences.holdShortcutModifiersTertiary, ShellPreferences.defaultHoldShortcutModifiersTertiary)
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
