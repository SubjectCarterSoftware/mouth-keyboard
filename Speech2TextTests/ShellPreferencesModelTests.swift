import XCTest
@testable import Speech2Text

@MainActor
final class ShellPreferencesModelTests: XCTestCase {

    func testWhisperModelDefaultsToTinyEN() {
        let (_, preferences) = makePreferences()
        XCTAssertEqual(preferences.whisperModel, .tinyEN)
    }

    func testSettingWhisperModelPersistsToDefaults() {
        let (defaults, preferences) = makePreferences()
        preferences.whisperModel = .smallEN
        let reloaded = ShellPreferences(userDefaults: defaults)
        XCTAssertEqual(reloaded.whisperModel, .smallEN)
    }

    func testResetRestoresWhisperModelToTinyEN() {
        let (_, preferences) = makePreferences()
        preferences.whisperModel = .baseEN
        preferences.reset()
        XCTAssertEqual(preferences.whisperModel, .tinyEN)
    }

    private func makePreferences(file: StaticString = #filePath, line: UInt = #line) -> (UserDefaults, ShellPreferences) {
        let suiteName = "ShellPreferencesModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test defaults", file: file, line: line)
            fatalError("Unable to create test defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, ShellPreferences(userDefaults: defaults))
    }
}
