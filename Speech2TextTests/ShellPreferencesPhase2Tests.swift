import XCTest
@testable import Speech2Text

@MainActor
final class ShellPreferencesPhase2Tests: XCTestCase {
    func testMicDeviceUIDsDefaultsToEmpty() {
        let (_, preferences) = makePreferences()

        XCTAssertEqual(preferences.micDeviceUIDs, [])
    }

    func testResetClearsPhase2KeysBackToDefaults() {
        let (defaults, preferences) = makePreferences()
        preferences.micDeviceUIDs = ["BuiltInMic"]

        preferences.reset()

        XCTAssertEqual(preferences.micDeviceUIDs, [])
        XCTAssertNil(defaults.object(forKey: ShellPreferences.Keys.micDeviceUIDs))
    }

    func testMigratesLegacyMicDeviceUID() {
        let suiteName = "ShellPreferencesPhase2Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Simulate old single-UID value stored under the legacy key.
        defaults.set("legacy-uid", forKey: ShellPreferences.Keys.micDeviceUID)

        let preferences = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences.micDeviceUIDs, ["legacy-uid"])

        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makePreferences(file: StaticString = #filePath, line: UInt = #line) -> (UserDefaults, ShellPreferences) {
        let suiteName = "ShellPreferencesPhase2Tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test defaults", file: file, line: line)
            fatalError("Unable to create test defaults")
        }

        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, ShellPreferences(userDefaults: defaults))
    }
}
