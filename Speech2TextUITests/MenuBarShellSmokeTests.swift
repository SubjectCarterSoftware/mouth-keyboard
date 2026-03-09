import XCTest

final class MenuBarShellSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchShowsSetupWindow() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "notDetermined",
            "-mock-keyboard-status", "notDetermined",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setupWindow.primaryAction"].exists)
    }

    func testCompletedSetupSuppressesSetupWindowOnLaunch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-complete-shell-setup",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        XCTAssertFalse(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 2))
    }

    func testCompletedSetupStillLaunchesWhenIndicatorHidden() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-complete-shell-setup",
            "-hide-recording-indicator",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        XCTAssertFalse(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 2))
    }

    func testIndicatorHiddenModeStillExposesLongSessionStatusInMenu() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-complete-shell-setup",
            "-hide-recording-indicator",
            "-ui-testing-open-status-window",
            "-ui-testing-long-session-status", "finalizing",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        let status = app.staticTexts["statusMenu.longSessionStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
    }

    func testLongSessionFailureFlagStillExposesWarningIdentifier() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-complete-shell-setup",
            "-ui-testing-open-status-window",
            "-ui-testing-long-session-fail-segment", "2",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        let warning = app.staticTexts["statusMenu.longSessionWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
    }
}
