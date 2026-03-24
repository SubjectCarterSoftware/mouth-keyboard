import Combine
import ServiceManagement
import XCTest
@testable import Speech2Text

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

    func testLegacyAtlasTriggerProfileMigratesToZeusOnLoad() {
        let (_, preferences) = makePreferences(
            initialTriggerProfile: TriggerProfile(
                activeProfile: .atlas,
                customPrimary: TriggerProfile.defaultCustomPrimary,
                customAliases: []
            )
        )

        XCTAssertEqual(preferences.activeTriggerProfile.activeProfile, .zeus)
        XCTAssertEqual(preferences.activeTriggerProfile.activePrimary, "Zeus")
    }

    func testResetAssistantNameToDefaultClearsCustomTrigger() async {
        let (_, preferences) = makePreferences(
            initialTriggerProfile: TriggerProfile(
                activeProfile: .custom,
                customPrimary: "Nova Prime",
                customAliases: []
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
