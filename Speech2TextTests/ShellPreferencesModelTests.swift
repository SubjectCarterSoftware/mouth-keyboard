import XCTest
@testable import Speech2Text

@MainActor
final class ShellPreferencesModelTests: XCTestCase {

    func testLaunchAtLoginDefaultsToFalse() {
        let (_, preferences) = makePreferences()
        XCTAssertFalse(preferences.launchAtLogin)
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
