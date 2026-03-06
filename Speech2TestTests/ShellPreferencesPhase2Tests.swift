import XCTest
@testable import Speech2Test

@MainActor
final class ShellPreferencesPhase2Tests: XCTestCase {
    func testTapModeDefaultsToDouble() {
        let (_, preferences) = makePreferences()

        XCTAssertEqual(preferences.tapMode, .double)
    }

    func testTapModePersistsSingleSelection() {
        let (defaults, preferences) = makePreferences()

        preferences.tapMode = .single

        let reloaded = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(reloaded.tapMode, .single)
    }

    func testActivationSoundEnabledDefaultsToTrue() {
        let (_, preferences) = makePreferences()

        XCTAssertTrue(preferences.activationSoundEnabled)
    }

    func testMicDeviceUIDDefaultsToNil() {
        let (_, preferences) = makePreferences()

        XCTAssertNil(preferences.micDeviceUID)
    }

    func testResetClearsPhase2KeysBackToDefaults() {
        let (defaults, preferences) = makePreferences()
        preferences.tapMode = .single
        preferences.activationSoundEnabled = false
        preferences.micDeviceUID = "BuiltInMic"

        preferences.reset()

        XCTAssertEqual(preferences.tapMode, .double)
        XCTAssertTrue(preferences.activationSoundEnabled)
        XCTAssertNil(preferences.micDeviceUID)
        XCTAssertNil(defaults.object(forKey: ShellPreferences.Keys.tapMode))
        XCTAssertNil(defaults.object(forKey: ShellPreferences.Keys.activationSoundEnabled))
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
