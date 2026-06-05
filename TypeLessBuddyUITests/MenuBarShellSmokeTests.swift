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
            "-mock-microphone-status", "notDetermined",
            "-mock-keyboard-status", "notDetermined",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setupWindow.primaryAction"].exists)
        XCTAssertTrue(app.otherElements["setupWindow.sidebar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setupWindow.sidebar.setup"].exists)
        XCTAssertTrue(app.buttons["setupWindow.sidebar.general"].exists)
        XCTAssertTrue(app.buttons["setupWindow.sidebar.assistant"].exists)
        XCTAssertTrue(app.buttons["setupWindow.sidebar.notes"].exists)
        XCTAssertTrue(app.buttons["setupWindow.sidebar.shortcuts"].exists)
        XCTAssertTrue(app.buttons["setupWindow.sidebar.history"].exists)
        XCTAssertTrue(app.buttons["setupWindow.sidebar.advanced"].exists)

        let promptEditButton = app.buttons["setupWindow.rewriteSystemPrompt.open"]
        XCTAssertTrue(promptEditButton.waitForExistence(timeout: 2))

        let promptEditor = app.descendants(matching: .any)
            .matching(identifier: "setupWindow.rewriteSystemPrompt.editor")
            .firstMatch
        XCTAssertFalse(promptEditor.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Say Buddy")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Play sound effects"].exists)
    }

    func testAssistantSettingsExposeRewriteSystemPromptEditor() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        XCTAssertTrue(app.staticTexts["setupWindow.title"].waitForExistence(timeout: 5))
        app.buttons["setupWindow.sidebar.assistant"].click()
        app.buttons["setupWindow.rewriteSystemPrompt.open"].click()

        let editor = app.descendants(matching: .any)
            .matching(identifier: "setupWindow.rewriteSystemPrompt.editor")
            .firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 2))

        let resetButton = app.buttons["setupWindow.rewriteSystemPrompt.reset"]
        XCTAssertTrue(resetButton.exists)
    }

    func testSidebarClickUpdatesSelection() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        let shortcutsButton = app.buttons["setupWindow.sidebar.shortcuts"]
        XCTAssertTrue(shortcutsButton.waitForExistence(timeout: 5))
        shortcutsButton.click()
        XCTAssertEqual(shortcutsButton.value as? String, "Selected")

        let setupButton = app.buttons["setupWindow.sidebar.setup"]
        setupButton.click()
        XCTAssertEqual(setupButton.value as? String, "Selected")
    }

    func testNotesSettingsExposeNoteCaptureControls() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
        ]

        app.launch()

        let notesButton = app.buttons["setupWindow.sidebar.notes"]
        XCTAssertTrue(notesButton.waitForExistence(timeout: 5))
        notesButton.click()

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "setupWindow.notes.mode")
                .firstMatch
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "setupWindow.notes.destination.path")
                .firstMatch
                .exists
        )
        XCTAssertTrue(app.buttons["setupWindow.notes.destination.browse"].exists)
        let historyButton = app.buttons["setupWindow.sidebar.history"]
        XCTAssertTrue(historyButton.exists)
        historyButton.click()

        let historySwitch = app.switches["setupWindow.history.enabled"]
        XCTAssertTrue(historySwitch.exists)
        historySwitch.click()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "setupWindow.history.path")
                .firstMatch
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["setupWindow.history.openFolder"].exists)
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
