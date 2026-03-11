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

    func testLaunchAtLoginDefaultsToFalse() {
        let (_, preferences) = makePreferences()
        XCTAssertFalse(preferences.launchAtLogin)
    }

    func testResetRestoresWhisperModelToTinyEN() {
        let (_, preferences) = makePreferences()
        preferences.whisperModel = .baseEN
        preferences.reset()
        XCTAssertEqual(preferences.whisperModel, .tinyEN)
    }

    // MARK: - Auto Model Selection

    func testAutoModelSelectionDefaultsToTrue() {
        let (_, preferences) = makePreferences()
        XCTAssertTrue(preferences.autoModelSelection)
    }

    func testSettingAutoModelSelectionPersistsToDefaults() {
        let (defaults, preferences) = makePreferences()
        preferences.autoModelSelection = false
        let reloaded = ShellPreferences(userDefaults: defaults)
        XCTAssertFalse(reloaded.autoModelSelection)
    }

    func testResetRestoresAutoModelSelectionToTrue() {
        let (_, preferences) = makePreferences()
        preferences.autoModelSelection = false
        preferences.reset()
        XCTAssertTrue(preferences.autoModelSelection)
    }

    // MARK: - WhisperModelChoice.forDuration

    func testForDurationReturnsTinyForShortRecordings() {
        XCTAssertEqual(WhisperModelChoice.forDuration(0), .tinyEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(2.5), .tinyEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(4.99), .tinyEN)
    }

    func testForDurationReturnsBaseForMediumRecordings() {
        XCTAssertEqual(WhisperModelChoice.forDuration(5.0), .baseEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(10), .baseEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(14.99), .baseEN)
    }

    func testForDurationReturnsSmallForLongRecordings() {
        XCTAssertEqual(WhisperModelChoice.forDuration(15.0), .smallEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(30), .smallEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(120), .smallEN)
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
