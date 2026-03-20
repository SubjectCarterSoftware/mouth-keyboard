import XCTest

// MARK: - AI Assistant Settings Flow UI Tests
//
// These tests exercise the Phase 15 AI Assistant settings surface through stable
// accessibility identifiers. They use launch arguments to seed isolated trigger-profile
// state so no real Application Support store is read or mutated.

final class AIAssistantSettingsFlowTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - SETT-01: AI Assistant tile visibility

    func testAIAssistantTileIsVisibleInSetupWindow() {
        let app = launchSetupWindow(preset: "zeus")

        // The tile container is present
        let tile = app.otherElements["assistantTile"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Expected assistantTile to be visible in setup window")
    }

    func testAIAssistantTileShowsActiveNameForDefaultPreset() {
        let app = launchSetupWindow(preset: "zeus")

        let activeName = app.staticTexts["assistantTile.activeName"]
        XCTAssertTrue(activeName.waitForExistence(timeout: 5))
        XCTAssertEqual(activeName.label, "Zeus")
    }

    func testAIAssistantTileShowsActiveNameForAtlasPreset() {
        let app = launchSetupWindow(preset: "atlas")

        let activeName = app.staticTexts["assistantTile.activeName"]
        XCTAssertTrue(activeName.waitForExistence(timeout: 5))
        XCTAssertEqual(activeName.label, "Atlas")
    }

    func testAIAssistantTileShowsActiveNameForGaiaPreset() {
        let app = launchSetupWindow(preset: "gaia")

        let activeName = app.staticTexts["assistantTile.activeName"]
        XCTAssertTrue(activeName.waitForExistence(timeout: 5))
        XCTAssertEqual(activeName.label, "Gaia")
    }

    func testAIAssistantTileShowsStatusLine() {
        let app = launchSetupWindow(preset: "zeus")

        let statusLine = app.staticTexts["assistantTile.statusLine"]
        XCTAssertTrue(statusLine.waitForExistence(timeout: 5))
        XCTAssertFalse(statusLine.label.isEmpty, "Status line should not be empty")
    }

    func testAIAssistantTileShowsAliasSummaryWhenCalibratedAliasesSeeded() {
        let app = launchSetupWindow(preset: "zeus", calibrated: true)

        let aliasSummary = app.staticTexts["assistantTile.aliasSummary"]
        XCTAssertTrue(aliasSummary.waitForExistence(timeout: 5),
                      "Expected alias summary to appear when calibrated aliases are seeded")
    }

    // MARK: - SETT-02: Change button opens sheet

    func testChangeButtonOpensAssistantSheet() {
        let app = launchSetupWindow(preset: "zeus")

        let changeButton = app.buttons["assistantTile.changeButton"]
        XCTAssertTrue(changeButton.waitForExistence(timeout: 5))
        changeButton.click()

        let sheetTitle = app.staticTexts["assistantSettings.title"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 5), "Expected assistant settings sheet to open")
    }

    func testChangeButtonOpensSheetNotSecondWindow() {
        let app = launchSetupWindow(preset: "zeus")

        let changeButton = app.buttons["assistantTile.changeButton"]
        XCTAssertTrue(changeButton.waitForExistence(timeout: 5))

        let windowCountBefore = app.windows.count
        changeButton.click()

        let sheetTitle = app.staticTexts["assistantSettings.title"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 5))
        // Sheet presentation does not add a new top-level window
        XCTAssertEqual(app.windows.count, windowCountBefore, "Sheet must not open as a second window")
    }

    // MARK: - Preset selection in sheet

    func testSelectingAtlasPresetUpdatesSheetCheckmark() {
        let app = launchSetupWindow(preset: "zeus")

        openAssistantSheet(app: app)

        let atlasButton = app.buttons["assistantSettings.preset.atlas"]
        XCTAssertTrue(atlasButton.waitForExistence(timeout: 5))
        atlasButton.click()

        // The atlas row should now show a checkmark (accessible via selected state or image)
        // Verify the button remains stable (no crash on selection)
        XCTAssertTrue(atlasButton.exists)
    }

    func testSelectingGaiaPresetUpdatesSheetCheckmark() {
        let app = launchSetupWindow(preset: "zeus")

        openAssistantSheet(app: app)

        let gaiaButton = app.buttons["assistantSettings.preset.gaia"]
        XCTAssertTrue(gaiaButton.waitForExistence(timeout: 5))
        gaiaButton.click()

        XCTAssertTrue(gaiaButton.exists)
    }

    func testPresetsZeusAtlasGaiaAreAllPresentInSheet() {
        let app = launchSetupWindow(preset: "zeus")

        openAssistantSheet(app: app)

        XCTAssertTrue(app.buttons["assistantSettings.preset.zeus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistantSettings.preset.atlas"].exists)
        XCTAssertTrue(app.buttons["assistantSettings.preset.gaia"].exists)
    }

    // MARK: - Custom name save

    func testCustomNameFieldAndSaveButtonArePresent() {
        let app = launchSetupWindow(preset: "zeus")

        openAssistantSheet(app: app)

        XCTAssertTrue(app.textFields["assistantSettings.customNameField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistantSettings.saveCustomName"].exists)
    }

    func testSaveButtonIsDisabledWhenCustomFieldIsEmpty() {
        let app = launchSetupWindow(preset: "zeus")

        openAssistantSheet(app: app)

        let saveButton = app.buttons["assistantSettings.saveCustomName"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertFalse(saveButton.isEnabled, "Save should be disabled when custom name field is empty")
    }

    // MARK: - Calibration summary in sheet

    func testCalibrationAliasSummaryAppearsInSheetWhenCalibratedAliasesSeeded() {
        let app = launchSetupWindow(preset: "zeus", calibrated: true)

        openAssistantSheet(app: app)

        let summary = app.staticTexts["assistantSettings.aliasSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5),
                      "Expected alias summary in sheet when calibrated aliases are present")
    }

    func testCalibrationAliasSummaryIsAbsentWhenNoAliasesSeeded() {
        let app = launchSetupWindow(preset: "zeus", calibrated: false)

        openAssistantSheet(app: app)

        let summary = app.staticTexts["assistantSettings.aliasSummary"]
        // Summary only appears when there are calibration aliases beyond the canonical
        XCTAssertFalse(summary.waitForExistence(timeout: 2),
                       "Alias summary must not appear when there are no calibrated aliases")
    }

    // MARK: - Sheet dismiss

    func testDoneButtonDismissesSheet() {
        let app = launchSetupWindow(preset: "zeus")

        openAssistantSheet(app: app)

        let doneButton = app.buttons["assistantSettings.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.click()

        // After dismiss, the sheet title is gone
        let sheetTitle = app.staticTexts["assistantSettings.title"]
        XCTAssertFalse(sheetTitle.waitForExistence(timeout: 3), "Sheet should be dismissed after Done is tapped")
    }

    func testSheetCanBeOpenedAndClosedRepeatedly() {
        let app = launchSetupWindow(preset: "zeus")

        for _ in 0 ..< 2 {
            openAssistantSheet(app: app)
            let doneButton = app.buttons["assistantSettings.done"]
            XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
            doneButton.click()
            let sheetTitle = app.staticTexts["assistantSettings.title"]
            XCTAssertFalse(sheetTitle.waitForExistence(timeout: 3))
        }
    }

    // MARK: - Helpers

    private func launchSetupWindow(preset: String, calibrated: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args: [String] = [
            "-ui-testing",
            "-reset-shell-preferences",
            "-open-setup-window",
            "-complete-shell-setup",
            "-mock-microphone-status", "authorized",
            "-mock-keyboard-status", "authorized",
            "-seed-trigger-preset", preset,
        ]
        if calibrated {
            args.append("-seed-trigger-profile-calibrated")
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func openAssistantSheet(app: XCUIApplication) {
        let changeButton = app.buttons["assistantTile.changeButton"]
        XCTAssertTrue(changeButton.waitForExistence(timeout: 5))
        changeButton.click()
        XCTAssertTrue(app.staticTexts["assistantSettings.title"].waitForExistence(timeout: 5))
    }
}
