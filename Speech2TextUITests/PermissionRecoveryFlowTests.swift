import XCTest

final class PermissionRecoveryFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBlockedMicrophoneStateShowsRecoveryAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mark-microphone-requested",
            "-mock-microphone-status", "denied",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["statusCard.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["statusCard.title"].value as? String, "Setup Blocked")
        XCTAssertTrue(app.buttons["permission.microphone.action"].exists)
    }

    func testKeyboardChecklistShowsOutstandingSetupWork() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "notDetermined",
        ]

        app.launch()

        let action = app.buttons["permission.keyboardMonitoring.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
    }

    func testBlockedKeyboardMonitoringStateShowsRecoveryAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "authorized",
            "-mark-keyboard-requested",
            "-mock-keyboard-status", "denied",
        ]

        app.launch()

        let row = app.descendants(matching: .group).matching(identifier: "permission.keyboardMonitoring.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["permission.keyboardMonitoring.action"].exists)
    }

    func testMicrophonePermissionFailureShowsRecoveryMessageAndActions() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-complete-shell-setup",
            "-ui-testing-open-status-window",
            "-ui-testing-capture-failure", "microphonePermissionDenied",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        let recoveryMessage = app.staticTexts["statusMenu.recoveryMessage"]
        XCTAssertTrue(recoveryMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["statusMenu.openMicrophoneSettings"].exists)
        XCTAssertTrue(app.buttons["statusMenu.openMicrophoneRecovery"].exists)
    }

    func testSelectedMicrophoneDisconnectShowsRecoveryRouteWithoutSettingsButton() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-complete-shell-setup",
            "-ui-testing-open-status-window",
            "-ui-testing-capture-failure", "selectedInputDisconnected",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        let recoveryMessage = app.staticTexts["statusMenu.recoveryMessage"]
        XCTAssertTrue(recoveryMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["statusMenu.openMicrophoneRecovery"].exists)
        XCTAssertFalse(app.buttons["statusMenu.openMicrophoneSettings"].exists)
    }
}
