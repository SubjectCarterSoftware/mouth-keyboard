import XCTest
@testable import Speech2Text

// MARK: - Helpers

@MainActor
private func makePreferences(
    activeProfile: TriggerNamePreset = .zeus,
    customPrimary: String = TriggerProfile.defaultCustomPrimary
) -> ShellPreferences {
    let suiteName = "AIAssistantSettingsViewModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let profile = TriggerProfile(
        activeProfile: activeProfile,
        customPrimary: customPrimary,
        customAliases: []
    )
    return ShellPreferences(
        userDefaults: defaults,
        triggerProfileStore: TriggerProfileStore(storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")),
        initialTriggerProfile: profile
    )
}

// MARK: - Tests

@MainActor
final class AIAssistantSettingsViewModelTests: XCTestCase {

    // MARK: Tile state

    func testDefaultZeusProfileRendersTileWithDefaultStatusCopy() {
        let preferences = makePreferences(activeProfile: .zeus)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        XCTAssertEqual(vm.activeName, "Zeus")
        XCTAssertEqual(vm.profileKind, .default)
        XCTAssert(vm.tileStatusLine.contains("Default"), "Expected 'Default' in '\(vm.tileStatusLine)'")
    }

    func testAtlasPresetProfileRendersTileWithPresetStatusCopy() {
        let preferences = makePreferences(activeProfile: .atlas)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        XCTAssertEqual(vm.activeName, "Atlas")
        XCTAssertEqual(vm.profileKind, .preset)
        XCTAssert(vm.tileStatusLine.contains("Preset"), "Expected 'Preset' in '\(vm.tileStatusLine)'")
    }

    func testGaiaPresetProfileRendersTileWithPresetStatusCopy() {
        let preferences = makePreferences(activeProfile: .gaia)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        XCTAssertEqual(vm.activeName, "Gaia")
        XCTAssertEqual(vm.profileKind, .preset)
        XCTAssert(vm.tileStatusLine.contains("Preset"), "Expected 'Preset' in '\(vm.tileStatusLine)'")
    }

    func testCustomProfileRendersTileWithCustomStatusCopy() {
        let preferences = makePreferences(activeProfile: .custom, customPrimary: "Nova")
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        XCTAssertEqual(vm.activeName, "Nova")
        XCTAssertEqual(vm.profileKind, .custom)
        XCTAssert(vm.tileStatusLine.contains("Custom"), "Expected 'Custom' in '\(vm.tileStatusLine)'")
    }

    // MARK: Sheet selection state

    func testSelectingAtlasUpdatesSelectionImmediately() {
        let preferences = makePreferences(activeProfile: .zeus)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        XCTAssertEqual(vm.pendingSelection, .zeus)
        vm.pendingSelection = .atlas
        XCTAssertEqual(vm.pendingSelection, .atlas)
    }

    func testSelectingGaiaUpdatesSelectionImmediately() {
        let preferences = makePreferences(activeProfile: .zeus)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        vm.pendingSelection = .gaia
        XCTAssertEqual(vm.pendingSelection, .gaia)
    }

    func testCalibrationRemainsOptionalForPresetChanges() {
        let preferences = makePreferences(activeProfile: .zeus)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        vm.pendingSelection = .atlas
        XCTAssertFalse(vm.isCalibrationRequired, "Calibration should never be required for preset changes")
    }

    // MARK: Custom name save

    func testSavingCustomNameNormalizesWhitespace() {
        let preferences = makePreferences(activeProfile: .zeus)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        vm.customNameInput = "  Nova  "
        let normalized = vm.normalizedCustomName
        XCTAssertEqual(normalized, "Nova")
    }

    func testSavingCustomNameWithExcessWhitespaceActivatesCustomProfile() {
        let preferences = makePreferences(activeProfile: .zeus)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        vm.customNameInput = "  Nova  "
        vm.saveCustomName()

        XCTAssertEqual(vm.pendingSelection, .custom)
    }

    func testEmptyCustomNameDoesNotActivateCustomProfile() {
        let preferences = makePreferences(activeProfile: .zeus)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        vm.customNameInput = "   "
        vm.saveCustomName()

        // Should not switch to custom when input is blank
        XCTAssertNotEqual(vm.pendingSelection, .custom)
    }

    func testCustomNameCanSaveOnlyThroughExplicitSaveAction() {
        let preferences = makePreferences(activeProfile: .zeus)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        vm.customNameInput = "Nova"
        // Setting input alone does not change pendingSelection to .custom
        XCTAssertNotEqual(vm.pendingSelection, .custom)

        vm.saveCustomName()
        // After explicit save, pendingSelection must be .custom
        XCTAssertEqual(vm.pendingSelection, .custom)
    }

    // MARK: Alias summary

    func testAliasSummaryIsEmptyBeforeCalibration() {
        let preferences = makePreferences(activeProfile: .zeus)
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        XCTAssertNil(vm.aliasSummary)
    }

    func testAliasSummaryUpdatesAfterCalibrationAliasesApplied() {
        let suiteName = "AIAssistantSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let profile = TriggerProfile(
            activeProfile: .zeus,
            customPrimary: TriggerProfile.defaultCustomPrimary,
            customAliases: [],
            zeusAliases: ["zeus", "hey zeus", "assistant zeus"]
        )
        let preferences = ShellPreferences(
            userDefaults: defaults,
            triggerProfileStore: TriggerProfileStore(storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")),
            initialTriggerProfile: profile
        )
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        XCTAssertNotNil(vm.aliasSummary)
        let summary = vm.aliasSummary!
        XCTAssert(summary.contains("hey zeus") || summary.contains("assistant zeus"),
                  "Expected alias variants in summary: \(summary)")
    }

    func testAliasSummaryShowsVariantsNotJustPrimary() {
        let suiteName = "AIAssistantSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Profile with canonical only — should produce nil or empty summary
        let profile = TriggerProfile(
            activeProfile: .zeus,
            customPrimary: TriggerProfile.defaultCustomPrimary,
            customAliases: [],
            zeusAliases: ["zeus"]   // only canonical — no calibration variants
        )
        let preferences = ShellPreferences(
            userDefaults: defaults,
            triggerProfileStore: TriggerProfileStore(storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")),
            initialTriggerProfile: profile
        )
        let vm = AIAssistantSettingsViewModel(preferences: preferences)

        // With only the canonical alias, there are no extra variants to show
        XCTAssertNil(vm.aliasSummary)
    }
}
