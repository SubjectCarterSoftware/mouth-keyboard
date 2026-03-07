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

        let row = app.descendants(matching: .group).matching(identifier: "permission.keyboardMonitoring.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["permission.keyboardMonitoring.action"].exists)
    }
}
