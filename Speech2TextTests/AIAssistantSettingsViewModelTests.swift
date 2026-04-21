import Combine
import XCTest
@testable import Speech2Text

@MainActor
private func makePreferences(
    activeProfile: TriggerNamePreset = .default,
    customPrimary: String = TriggerProfile.defaultCustomPrimary
) -> ShellPreferences {
    let suiteName = "AIAssistantSettingsViewModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let profile = TriggerProfile(
        activeProfile: activeProfile,
        customPrimary: customPrimary
    )

    return ShellPreferences(
        userDefaults: defaults,
        triggerProfileStore: TriggerProfileStore(
            storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        ),
        initialTriggerProfile: profile
    )
}

@MainActor
final class AIAssistantSettingsViewModelTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testDefaultProfileShowsDefaultInlineName() {
        let preferences = makePreferences(activeProfile: .default)
        let viewModel = AIAssistantSettingsViewModel(preferences: preferences)

        XCTAssertEqual(viewModel.activeName, AssistantDefaults.defaultAssistantName)
        XCTAssertEqual(viewModel.displayedName, AssistantDefaults.defaultAssistantName)
        XCTAssertTrue(viewModel.isUsingDefaultName)
        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertFalse(viewModel.isRecordControlPresented)
        XCTAssertFalse(viewModel.isPreparingRecordControl)
    }

    func testCustomProfileShowsRecordedName() {
        let preferences = makePreferences(activeProfile: .custom, customPrimary: "Nova Prime")
        let viewModel = AIAssistantSettingsViewModel(preferences: preferences)

        XCTAssertEqual(viewModel.activeName, "Nova Prime")
        XCTAssertEqual(viewModel.displayedName, "Nova Prime")
        XCTAssertFalse(viewModel.isUsingDefaultName)
    }

    func testPreviewRecordedNamePreservesSpokenCaseAndTrimsTrailingPunctuation() {
        let preferences = makePreferences(activeProfile: .default)
        let viewModel = AIAssistantSettingsViewModel(preferences: preferences)

        viewModel.previewRecordedName("  Project Copilot.  ")

        XCTAssertEqual(viewModel.pendingRecordedName, "Project Copilot")
        XCTAssertEqual(viewModel.displayedName, "Project Copilot")
        XCTAssertEqual(viewModel.activeName, AssistantDefaults.defaultAssistantName)
        XCTAssertEqual(viewModel.renameState, .preview)
        XCTAssertTrue(viewModel.isPreviewingRecordedName)
    }

    func testPreviewRecordedNameIgnoresWhitespaceOnlyTranscription() {
        let preferences = makePreferences(activeProfile: .default)
        let viewModel = AIAssistantSettingsViewModel(preferences: preferences)

        viewModel.previewRecordedName("   ")

        XCTAssertNil(viewModel.pendingRecordedName)
        XCTAssertEqual(viewModel.displayedName, AssistantDefaults.defaultAssistantName)
        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertTrue(viewModel.isUsingDefaultName)
    }

    func testShowRecordControlWarmsModelBeforeRevealingHoldToRecordButton() async {
        let preferences = makePreferences(activeProfile: .default)
        var continuation: CheckedContinuation<Bool, Never>?
        let viewModel = AIAssistantSettingsViewModel(
            preferences: preferences,
            prepareWhisperModel: {
                await withCheckedContinuation { capturedContinuation in
                    continuation = capturedContinuation
                }
            }
        )

        viewModel.showRecordControl()

        XCTAssertTrue(viewModel.isRecordControlPresented)
        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertTrue(viewModel.isPreparingRecordControl)
        await Task.yield()
        XCTAssertNotNil(continuation)

        let warmupExpectation = expectation(description: "Record control warmed")
        viewModel.$isPreparingRecordControl
            .dropFirst()
            .sink { isPreparing in
                if !isPreparing {
                    warmupExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        continuation?.resume(returning: true)

        await fulfillment(of: [warmupExpectation], timeout: 1.0)
        XCTAssertFalse(viewModel.isPreparingRecordControl)
    }

    func testStartRecordingStopRecordingStagesCapturedNameForSubmission() async {
        let preferences = makePreferences(activeProfile: .default)
        var continuation: CheckedContinuation<String?, Error>?
        let viewModel = AIAssistantSettingsViewModel(
            preferences: preferences,
            transcriptCapture: {
                try await withCheckedThrowingContinuation { capturedContinuation in
                    continuation = capturedContinuation
                }
            },
            prepareWhisperModel: {
                true
            }
        )

        viewModel.startRecording()
        XCTAssertEqual(viewModel.renameState, .recording)
        XCTAssertTrue(viewModel.isRecordControlPresented)
        await Task.yield()
        XCTAssertNotNil(continuation)

        let previewExpectation = expectation(description: "Preview recorded name")
        viewModel.$pendingRecordedName
            .dropFirst()
            .sink { value in
                if value == "Nova Prime" {
                    previewExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.stopRecording()
        XCTAssertEqual(viewModel.renameState, .transcribing)

        continuation?.resume(returning: "Nova Prime")

        await fulfillment(of: [previewExpectation], timeout: 1.0)
        XCTAssertEqual(viewModel.pendingRecordedName, "Nova Prime")
        XCTAssertEqual(viewModel.displayedName, "Nova Prime")
        XCTAssertEqual(viewModel.activeName, AssistantDefaults.defaultAssistantName)
        XCTAssertEqual(viewModel.renameState, .preview)
        XCTAssertEqual(preferences.activeTriggerProfile.activeProfile, .default)
    }

    func testStopRecordingStagesCapturedNameWhenCaptureReturnsAfterCancellation() async {
        let preferences = makePreferences(activeProfile: .default)
        let viewModel = AIAssistantSettingsViewModel(
            preferences: preferences,
            transcriptCapture: {
                do {
                    try await Task.sleep(for: .seconds(3))
                    return nil
                } catch is CancellationError {
                    return "Nova Prime"
                }
            },
            prepareWhisperModel: {
                true
            }
        )

        let previewExpectation = expectation(description: "Preview recorded name")
        viewModel.$pendingRecordedName
            .dropFirst()
            .sink { value in
                if value == "Nova Prime" {
                    previewExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.startRecording()
        XCTAssertEqual(viewModel.renameState, .recording)

        viewModel.stopRecording()
        XCTAssertEqual(viewModel.renameState, .transcribing)

        await fulfillment(of: [previewExpectation], timeout: 1.0)
        XCTAssertEqual(viewModel.pendingRecordedName, "Nova Prime")
        XCTAssertEqual(viewModel.displayedName, "Nova Prime")
        XCTAssertEqual(viewModel.activeName, AssistantDefaults.defaultAssistantName)
        XCTAssertEqual(viewModel.renameState, .preview)
    }

    func testStopRecordingPreparesWhisperModelBeforeCancelledCaptureReturnsTranscript() async {
        let preferences = makePreferences(activeProfile: .default)
        var didPrepareModel = false
        let viewModel = AIAssistantSettingsViewModel(
            preferences: preferences,
            transcriptCapture: {
                do {
                    try await Task.sleep(for: .seconds(3))
                    return nil
                } catch is CancellationError {
                    return didPrepareModel ? "Nova Prime" : nil
                }
            },
            prepareWhisperModel: {
                didPrepareModel = true
                return true
            }
        )

        let previewExpectation = expectation(description: "Preview recorded name")
        viewModel.$pendingRecordedName
            .dropFirst()
            .sink { value in
                if value == "Nova Prime" {
                    previewExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.startRecording()
        XCTAssertEqual(viewModel.renameState, .recording)

        viewModel.stopRecording()
        XCTAssertEqual(viewModel.renameState, .transcribing)

        await fulfillment(of: [previewExpectation], timeout: 1.0)
        XCTAssertTrue(didPrepareModel)
        XCTAssertEqual(viewModel.pendingRecordedName, "Nova Prime")
        XCTAssertEqual(viewModel.renameState, .preview)
    }

    func testSubmitPendingRecordedNamePersistsStagedName() async {
        let preferences = makePreferences(activeProfile: .default)
        let viewModel = AIAssistantSettingsViewModel(preferences: preferences)
        viewModel.previewRecordedName("Nova Prime")

        let updatedProfile = await waitForProfileUpdate(on: preferences) {
            viewModel.submitPendingRecordedName()
        }

        XCTAssertEqual(updatedProfile.activeProfile, .custom)
        XCTAssertEqual(updatedProfile.customPrimary, "Nova Prime")
        XCTAssertEqual(viewModel.pendingRecordedName, nil)
        XCTAssertEqual(viewModel.activeName, "Nova Prime")
        XCTAssertEqual(viewModel.displayedName, "Nova Prime")
        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertFalse(viewModel.isUsingDefaultName)
        XCTAssertFalse(viewModel.isRecordControlPresented)
    }

    func testDiscardPendingRecordedNameReturnsToIdle() {
        let preferences = makePreferences(activeProfile: .default)
        let viewModel = AIAssistantSettingsViewModel(preferences: preferences)
        viewModel.previewRecordedName("Nova Prime")

        viewModel.discardPendingRecordedName()

        XCTAssertNil(viewModel.pendingRecordedName)
        XCTAssertEqual(viewModel.displayedName, AssistantDefaults.defaultAssistantName)
        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertTrue(viewModel.isRecordControlPresented)
    }

    func testCancelRenameFlowFromWarmupHidesControlAndSchedulesUnload() {
        let preferences = makePreferences(activeProfile: .default)
        var unloadScheduleCount = 0
        let viewModel = AIAssistantSettingsViewModel(
            preferences: preferences,
            prepareWhisperModel: { true },
            scheduleWhisperIdleUnload: {
                unloadScheduleCount += 1
            },
            cancelWhisperIdleUnload: {}
        )

        viewModel.showRecordControl()
        XCTAssertTrue(viewModel.isPreparingRecordControl)
        XCTAssertTrue(viewModel.isRecordControlPresented)

        viewModel.cancelRenameFlow()

        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertFalse(viewModel.isPreparingRecordControl)
        XCTAssertFalse(viewModel.isRecordControlPresented)
        XCTAssertNil(viewModel.pendingRecordedName)
        XCTAssertEqual(unloadScheduleCount, 1)
    }

    func testCancelRenameFlowFromPreviewRestoresActiveNameAndSchedulesUnload() {
        let preferences = makePreferences(activeProfile: .custom, customPrimary: "Nova Prime")
        var unloadScheduleCount = 0
        let viewModel = AIAssistantSettingsViewModel(
            preferences: preferences,
            scheduleWhisperIdleUnload: {
                unloadScheduleCount += 1
            },
            cancelWhisperIdleUnload: {}
        )
        viewModel.previewRecordedName("Project Copilot")

        viewModel.cancelRenameFlow()

        XCTAssertNil(viewModel.pendingRecordedName)
        XCTAssertEqual(viewModel.displayedName, "Nova Prime")
        XCTAssertEqual(viewModel.activeName, "Nova Prime")
        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertFalse(viewModel.isRecordControlPresented)
        XCTAssertEqual(unloadScheduleCount, 1)
    }

    func testHandleSettingsDismissedCancelsRenameFlowAndSchedulesUnload() {
        let preferences = makePreferences(activeProfile: .default)
        var unloadScheduleCount = 0
        let viewModel = AIAssistantSettingsViewModel(
            preferences: preferences,
            prepareWhisperModel: { true },
            scheduleWhisperIdleUnload: {
                unloadScheduleCount += 1
            },
            cancelWhisperIdleUnload: {}
        )

        viewModel.showRecordControl()
        viewModel.handleSettingsDismissed()

        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertFalse(viewModel.isPreparingRecordControl)
        XCTAssertFalse(viewModel.isRecordControlPresented)
        XCTAssertEqual(unloadScheduleCount, 1)
    }

    func testStartRecordingShowsBusyMessageWhenCaptureIsUnavailable() async {
        let preferences = makePreferences(activeProfile: .default)
        let viewModel = AIAssistantSettingsViewModel(
            preferences: preferences,
            transcriptCapture: {
                throw AudioCaptureError.captureBusy
            },
            prepareWhisperModel: {
                true
            }
        )

        let busyMessageExpectation = expectation(description: "Capture busy message appears")
        viewModel.$captureMessage
            .dropFirst()
            .sink { message in
                if message != nil {
                    busyMessageExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.startRecording()

        await fulfillment(of: [busyMessageExpectation], timeout: 1.0)
        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertEqual(viewModel.captureMessage, "Assistant renaming must wait until the current recording ends.")
    }

    func testResetToDefaultClearsCustomName() async {
        let preferences = makePreferences(activeProfile: .custom, customPrimary: "Nova Prime")
        let viewModel = AIAssistantSettingsViewModel(preferences: preferences)

        let updatedProfile = await waitForProfileUpdate(on: preferences) {
            viewModel.resetToDefault()
        }

        XCTAssertEqual(updatedProfile, .defaultProfile)
        XCTAssertNil(viewModel.pendingRecordedName)
        XCTAssertEqual(viewModel.activeName, AssistantDefaults.defaultAssistantName)
        XCTAssertEqual(viewModel.displayedName, AssistantDefaults.defaultAssistantName)
        XCTAssertEqual(viewModel.renameState, .idle)
        XCTAssertTrue(viewModel.isUsingDefaultName)
        XCTAssertFalse(viewModel.isRecordControlPresented)
    }

    private func waitForProfileUpdate(
        on preferences: ShellPreferences,
        action: () -> Void
    ) async -> TriggerProfile {
        let updatedExpectation = expectation(description: "Trigger profile updated")

        preferences.$activeTriggerProfile
            .dropFirst()
            .sink { _ in
                updatedExpectation.fulfill()
            }
            .store(in: &cancellables)

        action()

        await fulfillment(of: [updatedExpectation], timeout: 1.0)
        return preferences.activeTriggerProfile
    }
}
