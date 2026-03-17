import XCTest
@testable import Speech2Text

@MainActor
final class ShellPreferencesModelTests: XCTestCase {

    func testWhisperModelDefaultsToBaseEN() {
        let (_, preferences) = makePreferences()
        XCTAssertEqual(preferences.whisperModel, .baseEN)
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

    func testResetRestoresWhisperModelToBaseEN() {
        let (_, preferences) = makePreferences()
        preferences.whisperModel = .smallEN
        preferences.reset()
        XCTAssertEqual(preferences.whisperModel, .baseEN)
    }

    // MARK: - Auto Model Selection

    func testAutoModelSelectionDefaultsToFalse() {
        let (_, preferences) = makePreferences()
        XCTAssertFalse(preferences.autoModelSelection)
    }

    func testSettingAutoModelSelectionPersistsToDefaults() {
        let (defaults, preferences) = makePreferences()
        preferences.autoModelSelection = true
        let reloaded = ShellPreferences(userDefaults: defaults)
        XCTAssertTrue(reloaded.autoModelSelection)
    }

    func testResetRestoresAutoModelSelectionToFalse() {
        let (_, preferences) = makePreferences()
        preferences.autoModelSelection = true
        preferences.reset()
        XCTAssertFalse(preferences.autoModelSelection)
    }

    // MARK: - WhisperModelChoice.forDuration

    func testForDurationReturnsTinyForShortRecordings() {
        XCTAssertEqual(WhisperModelChoice.forDuration(0), .tinyEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(30), .tinyEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(59.99), .tinyEN)
    }

    func testForDurationReturnsBaseForMediumRecordings() {
        XCTAssertEqual(WhisperModelChoice.forDuration(60.0), .baseEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(180), .baseEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(299.99), .baseEN)
    }

    func testForDurationReturnsSmallForLongRecordings() {
        XCTAssertEqual(WhisperModelChoice.forDuration(300.0), .smallEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(600), .smallEN)
        XCTAssertEqual(WhisperModelChoice.forDuration(1200), .smallEN)
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
