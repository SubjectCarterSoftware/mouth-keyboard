import XCTest
@testable import Speech2Text

@MainActor
final class ShellPreferencesPhase2Tests: XCTestCase {
    func testMicDeviceUIDDefaultsToNil() {
        let (_, preferences) = makePreferences()

        XCTAssertNil(preferences.micDeviceUID)
    }

    func testResetClearsPhase2KeysBackToDefaults() {
        let (defaults, preferences) = makePreferences()
        preferences.micDeviceUID = "BuiltInMic"

        preferences.reset()

        XCTAssertNil(preferences.micDeviceUID)
        XCTAssertNil(defaults.object(forKey: ShellPreferences.Keys.micDeviceUID))
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
