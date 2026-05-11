import XCTest

final class PermissionRecoveryFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBlockedMicrophoneStateShowsRecoveryActionInSetupWindow() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mark-microphone-requested",
            "-mock-microphone-status", "denied",
            "-mock-postevent-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["permission.microphone.action"].exists)
    }

    func testAccessibilityTileShowsAllowActionWhenUndetermined() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "authorized",
            "-mock-postevent-status", "notDetermined",
            "-mock-keyboard-status", "notDetermined",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["permission.postEvent.action"].exists)
    }

    func testAccessibilityTileGuideAppearsFromAllowAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "authorized",
            "-mock-postevent-status", "notDetermined",
            "-mock-keyboard-status", "notDetermined",
        ]

        app.launch()

        let action = app.buttons["permission.postEvent.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()

        XCTAssertTrue(app.staticTexts["How to enable Accessibility access"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
    }

    func testHoldToTranscribeRowShowsEnableActionWhenAccessibilityIsUndetermined() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "authorized",
            "-mock-postevent-status", "notDetermined",
            "-mock-keyboard-status", "notDetermined",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
        // Recorder button inherits row identifier; query by label (default shortcut after reset)
        XCTAssertTrue(app.buttons["Right ⌥"].exists)
        XCTAssertTrue(app.buttons["Enable Accessibility"].exists)
    }

    func testAlwaysAutoPasteSettingAppearsInSetupWindow() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "authorized",
            "-mock-postevent-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
        let toggle = app.descendants(matching: .any).matching(identifier: "setupWindow.alwaysAutoPaste.toggle").firstMatch
        XCTAssertTrue(toggle.exists)
        let restoreToggle = app.descendants(matching: .any).matching(identifier: "setupWindow.restorePreviousClipboard.toggle").firstMatch
        XCTAssertTrue(restoreToggle.exists)
    }

    func testPillPositionSettingAppearsInSetupWindow() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "authorized",
            "-mock-postevent-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setupWindow.pillPosition.topLeft"].exists)
        XCTAssertTrue(app.buttons["setupWindow.pillPosition.topCenter"].exists)
        XCTAssertTrue(app.buttons["setupWindow.pillPosition.topRight"].exists)
        XCTAssertTrue(app.buttons["setupWindow.pillPosition.centerLeft"].exists)
        XCTAssertTrue(app.buttons["setupWindow.pillPosition.centerRight"].exists)
        XCTAssertTrue(app.buttons["setupWindow.pillPosition.bottomLeft"].exists)
        XCTAssertTrue(app.buttons["setupWindow.pillPosition.bottomCenter"].exists)
        XCTAssertTrue(app.buttons["setupWindow.pillPosition.bottomRight"].exists)
    }

    func testHoldToTranscribeRowShowsRecoveryActionWhenAccessibilityIsBlocked() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "authorized",
            "-mark-postevent-requested",
            "-mock-postevent-status", "denied",
            "-mark-keyboard-requested",
            "-mock-keyboard-status", "denied",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
        // Recorder button inherits row identifier; query by label (default shortcut after reset)
        XCTAssertTrue(app.buttons["Right ⌥"].exists)
        XCTAssertTrue(app.buttons["Open Accessibility Setup"].exists)
    }

    func testHoldToTranscribeActionShowsAccessibilityGuide() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-mock-microphone-status", "authorized",
            "-mock-postevent-status", "notDetermined",
            "-mock-keyboard-status", "notDetermined",
        ]

        app.launch()

        let action = app.buttons["Enable Accessibility"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()

        XCTAssertTrue(app.staticTexts["How to enable Accessibility access"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
    }
}
