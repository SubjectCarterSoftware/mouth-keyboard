import XCTest
@testable import Speech2Test

@MainActor
final class ShellPreferencesPhase3Tests: XCTestCase {

    func testAutoPasteEnabledDefaultsToTrue() {
        let (_, preferences) = makePreferences()
        XCTAssertTrue(preferences.autoPasteEnabled)
    }

    func testIndicatorVisibleDefaultsToTrue() {
        let (_, preferences) = makePreferences()
        XCTAssertTrue(preferences.indicatorVisible)
    }

    func testSettingAutoPastePersistsToDefaults() {
        let (defaults, preferences) = makePreferences()
        preferences.autoPasteEnabled = false
        let reloaded = ShellPreferences(userDefaults: defaults)
        XCTAssertFalse(reloaded.autoPasteEnabled)
    }

    func testSettingIndicatorVisiblePersistsToDefaults() {
        let (defaults, preferences) = makePreferences()
        preferences.indicatorVisible = false
        let reloaded = ShellPreferences(userDefaults: defaults)
        XCTAssertFalse(reloaded.indicatorVisible)
    }

    func testResetRestoresAutoPasteEnabledToTrue() {
        let (_, preferences) = makePreferences()
        preferences.autoPasteEnabled = false
        preferences.reset()
        XCTAssertTrue(preferences.autoPasteEnabled)
    }

    func testResetRestoresIndicatorVisibleToTrue() {
        let (_, preferences) = makePreferences()
        preferences.indicatorVisible = false
        preferences.reset()
        XCTAssertTrue(preferences.indicatorVisible)
    }

    private func makePreferences(file: StaticString = #filePath, line: UInt = #line) -> (UserDefaults, ShellPreferences) {
        let suiteName = "ShellPreferencesPhase3Tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test defaults", file: file, line: line)
            fatalError("Unable to create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, ShellPreferences(userDefaults: defaults))
    }
}
