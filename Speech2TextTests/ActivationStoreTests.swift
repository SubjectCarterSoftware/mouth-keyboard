import Combine
import XCTest
@testable import Speech2Text

@MainActor
final class ActivationStoreTests: XCTestCase {
    func testInitialStateIsIdle() {
        let store = makeStore(permissionsAuthorized: true)

        XCTAssertEqual(store.state, .idle)
    }

    func testArmTransitionsToRecordingSynchronouslyWhenReady() {
        let store = makeStore(permissionsAuthorized: true)

        store.arm()

        XCTAssertEqual(store.state, .recording)
    }

    func testArmStartsRewriteModelWarmupForSelectedTier() async throws {
        let defaults = UserDefaults(suiteName: "ActivationStoreTests.RewriteWarmup.\(UUID().uuidString)") ?? .standard
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.rewriteModelTier = .high9B
        let mockRewriter = MockLLMRewriter(result: .success("unused"))
        let store = makeStore(
            permissionsAuthorized: true,
            llmRewriter: mockRewriter,
            preferences: preferences
        )

        store.arm()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state, .recording)
        XCTAssertEqual(mockRewriter.setTierCalls, [.high9B])
        XCTAssertEqual(mockRewriter.cancelScheduledUnloadCallCount, 1)
        XCTAssertEqual(mockRewriter.prewarmCallCount, 1)
    }

    func testStopTransitionsToIdle() {
        let store = makeStore(permissionsAuthorized: true)
        store.arm()

        store.stop()

        XCTAssertEqual(store.state, .idle)
    }

    func testBeginHoldSessionTransitionsToRecordingSynchronouslyWhenReady() {
        let store = makeStore(permissionsAuthorized: true)

        let didStart = store.beginHoldSession()

        XCTAssertTrue(didStart)
        XCTAssertEqual(store.state, .recording)
    }

    func testBeginHoldSessionReturnsFalseWhenPermissionsNotAuthorized() {
        let store = makeStore(permissionsAuthorized: false)

        let didStart = store.beginHoldSession()

        XCTAssertFalse(didStart)
        XCTAssertEqual(store.state, .idle)
    }

    func testFinishHoldSessionStopsOnlyHoldOriginRecording() {
        let store = makeStore(permissionsAuthorized: true)
        XCTAssertTrue(store.beginHoldSession())

        store.finishHoldSession()

        XCTAssertEqual(store.state, .processing)
    }

    func testFinishHoldSessionIgnoresToggleOriginRecording() {
        let store = makeStore(permissionsAuthorized: true)
        store.arm()

        store.finishHoldSession()

        XCTAssertEqual(store.state, .recording)
    }

    // arm() is blocked when permissions are not yet authorized — readiness
    // state alone is not the gate; the individual permission items are checked.
    func testArmDoesNotTransitionWhenPermissionsNotAuthorized() {
        let store = makeStore(permissionsAuthorized: false)

        store.arm()

        XCTAssertEqual(store.state, .idle)
    }

    // arm() succeeds when all permissions are authorized, even if the initial
    // setup launch check has not marked onboarding complete yet.
    // Setup completion is an onboarding UX gate, not a runtime gate.
    func testArmSucceedsWhenPermissionsAuthorizedRegardlessOfSetupCompletion() {
        let store = makeStore(permissionsAuthorized: true)

        store.arm()

        XCTAssertEqual(store.state, .recording)
    }

    // MARK: - finish() tests

    func test_finish_transitions_to_processing() {
        let store = makeStore(permissionsAuthorized: true)
        store.arm()
        XCTAssertEqual(store.state, .recording)

        store.finish()

        XCTAssertEqual(store.state, .processing)
    }

    func testFinishShowsSelectedModelDownloadProgressWhileWaitingForPrepare() async throws {
        let suiteName = "ActivationStoreTests.ModelDownloadProgress.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.whisperModel = .smallEN

        let loadState = StubWhisperModelLoadState()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: DelayedPrepareWhisperTranscriber(
                prepareDelayNanoseconds: 300_000_000,
                result: .success("Hello world")
            ),
            whisperModelLoadState: loadState,
            preferences: preferences
        )

        store.arm()
        store.finish()
        XCTAssertEqual(store.state, .processing)

        try await Task.sleep(nanoseconds: 50_000_000)
        loadState.phase = .downloading(model: .smallEN, progress: 0.42)
        try await Task.sleep(nanoseconds: 50_000_000)

        guard case .modelDownloading(let model, let progress) = store.state else {
            XCTFail("Expected model-download progress state, got \(store.state)")
            return
        }
        XCTAssertEqual(model, .smallEN)
        XCTAssertEqual(progress, 0.42, accuracy: 0.001)

        loadState.phase = .ready(model: .smallEN)
        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(store.lastTranscription, "Hello world")
        if case .success(let text, _, _, _, _) = store.state {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .success state after prepare completed, got \(store.state)")
        }
    }

    func testCancelDuringModelDownloadReturnsToIdle() async throws {
        let suiteName = "ActivationStoreTests.CancelDuringModelDownload.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.whisperModel = .mediumEN

        let loadState = StubWhisperModelLoadState()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: DelayedPrepareWhisperTranscriber(
                prepareDelayNanoseconds: 500_000_000,
                result: .success("unused")
            ),
            whisperModelLoadState: loadState,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 50_000_000)

        loadState.phase = .downloading(model: .mediumEN, progress: 0.25)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(store.state.isModelDownloading)

        store.cancelCurrentSession()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.recoveryFeedback, .canceled)
    }

    func test_finish_no_op_when_not_recording() {
        let store = makeStore(permissionsAuthorized: true)
        // state is .idle
        store.finish()

        XCTAssertEqual(store.state, .idle)
    }

    func test_finish_succeeds_writes_clipboard() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success("Hello world"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        // Wait for async transcription
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
        XCTAssertEqual(store.lastTranscription, "Hello world")
        if case .success(let text, _, _, _, _) = store.state {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
        let startedAt = try XCTUnwrap(store.successDismissStartedAt)
        let deadline = try XCTUnwrap(store.successDismissDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(startedAt), 6, accuracy: 0.05)
    }

    func testPasteFallbackReportsCopiedOnly() async throws {
        let pasteStub = StubCopyOnlyPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Fallback text")),
            clipboard: mockClipboard,
            pasteService: pasteStub
        )

        store.armAndPaste()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(mockClipboard.lastWrittenText)
        if case .success(_, let pasted, let converted, _, _) = store.state {
            XCTAssertFalse(pasted, "Synthetic paste failed so UI should show copied-only state")
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state after fallback")
        }
        XCTAssertEqual(pasteStub.pasteCount, 1)
        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Fallback text"])
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
    }

    func testAlwaysAutoPastePastesRawTranscriptionWhenPermissionIsGranted() async throws {
        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Hello world")),
            clipboard: mockClipboard,
            pasteService: pasteStub
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertEqual(pasteStub.pasteCount, 1)
        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Hello world"])
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
        if case .success(_, let pasted, let converted, _, _) = store.state {
            XCTAssertTrue(pasted)
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state after auto paste")
        }
    }

    func testAlwaysAutoPastePastesConvertedOutputWhenPermissionIsGranted() async throws {
        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("clanker Please schedule a meeting for Friday convert to email")
            ),
            llmRewriter: MockLLMRewriter(result: .success("Converted output")),
            clipboard: mockClipboard,
            pasteService: pasteStub
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertEqual(pasteStub.pasteCount, 1)
        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Converted output"])
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
        if case .success(let text, let pasted, let converted, _, _) = store.state {
            XCTAssertEqual(text, "Converted output")
            XCTAssertTrue(pasted)
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state after converted auto paste")
        }
    }

    func testAlwaysAutoPasteRewriteFailurePreservesOriginalClipboard() async throws {
        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "original clipboard"
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("clanker Please schedule a meeting for Friday convert to email")
            ),
            llmRewriter: MockLLMRewriter(result: .failure(LLMRewriteError.generationFailed)),
            clipboard: mockClipboard,
            pasteService: pasteStub
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertTrue(mockClipboard.temporaryWriteTexts.isEmpty)
        XCTAssertEqual(mockClipboard.restoreCallCount, 0)
        XCTAssertEqual(pasteStub.pasteCount, 0)
        XCTAssertEqual(store.lastTranscription, "clanker Please schedule a meeting for Friday convert to email")
    }

    func testAlwaysAutoPasteOffKeepsClipboardOnlyBehavior() async throws {
        let suiteName = "ActivationStoreTests.AlwaysAutoPasteOff.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.alwaysAutoPaste = false

        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Clipboard only")),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mockClipboard.lastWrittenText, "Clipboard only")
        XCTAssertEqual(pasteStub.pasteCount, 0)
        if case .success(_, let pasted, let converted, _, _) = store.state {
            XCTAssertFalse(pasted)
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state after clipboard-only finish")
        }
    }

    func testCancelDuringRecordingReturnsToIdleWithoutClipboardWrite() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let mockRewriter = MockLLMRewriter(result: .success("unused"))
        let store = makeStore(
            permissionsAuthorized: true,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard
        )
        store.arm()

        store.cancelCurrentSession()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.recoveryFeedback, .canceled)
        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertEqual(
            mockRewriter.scheduledIdleUnloadDurations.last,
            LLMRewriteService.idleUnloadDelayNanoseconds
        )
    }

    func testSuccessfulPassthroughSessionSchedulesRewriteModelIdleUnloadAfterReturningToIdle() async throws {
        let mockRewriter = MockLLMRewriter(result: .success("unused"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Hello world")),
            llmRewriter: mockRewriter
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 6_300_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(
            mockRewriter.scheduledIdleUnloadDurations.last,
            LLMRewriteService.idleUnloadDelayNanoseconds
        )
    }

    func testCancelDuringProcessingSuppressesLateSuccessPublication() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: DelayedWhisperTranscriber(delayNanoseconds: 300_000_000, result: .success("late result")),
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        XCTAssertEqual(store.state, .processing)

        store.cancelCurrentSession()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.recoveryFeedback, .canceled)
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testCancelDuringConvertingSuppressesLateConversion() async throws {
        let transcript = "team update clanker make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let preferences = makePreferencesWithTriggerStore()
        preferences.allowClipboardAccess = false
        let delayedRewriter = DelayedLLMRewriter(
            delayNanoseconds: 500_000_000,
            result: .success("Converted output")
        )
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: delayedRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.state, .converting)

        store.cancelCurrentSession()
        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.recoveryFeedback, .canceled)
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testImmediateRewriteHoldsConvertingStateBeforeSuccess() async throws {
        let transcript = "team update clanker make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: MockLLMRewriter(result: .success("Refined output")),
            clipboard: mockClipboard
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(store.state, .converting)
        XCTAssertNil(mockClipboard.lastWrittenText)

        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Refined output")
        if case .success(let text, _, let converted, _, _) = store.state {
            XCTAssertEqual(text, "Refined output")
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state after minimum converting display")
        }
    }

    func testDelayedRewriteDoesNotAddExtraDelayAfterMinimumConvertingDisplay() async throws {
        let transcript = "team update clanker make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let preferences = makePreferencesWithTriggerStore()
        preferences.allowClipboardAccess = false
        let delayedRewriter = DelayedLLMRewriter(
            delayNanoseconds: 300_000_000,
            result: .success("Delayed refined output")
        )
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: delayedRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let enteredConverting = try await waitUntil(timeoutNanoseconds: 400_000_000) {
            await MainActor.run {
                store.state == .converting
            }
        }
        XCTAssertTrue(enteredConverting, "Expected assistant-triggered flow to enter .converting")

        let reachedSuccess = try await waitUntil(timeoutNanoseconds: 900_000_000) {
            await MainActor.run {
                if case .success = store.state {
                    return true
                }
                return false
            }
        }
        XCTAssertTrue(
            reachedSuccess,
            "Expected delayed rewrite to complete without an extra minimum-display delay"
        )

        guard let rewriteCompletedAt = delayedRewriter.lastCompletionUptimeNanoseconds else {
            XCTFail("Expected delayed rewriter to record its completion time")
            return
        }

        let successObservedAt = DispatchTime.now().uptimeNanoseconds
        XCTAssertLessThan(successObservedAt - rewriteCompletedAt, 180_000_000)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Delayed refined output")
        if case .success(let text, _, let converted, _, _) = store.state {
            XCTAssertEqual(text, "Delayed refined output")
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state once delayed rewrite completed")
        }
    }

    func testCancelDuringMinimumConvertingDisplaySuppressesClipboardWrite() async throws {
        let transcript = "team update clanker make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: MockLLMRewriter(result: .success("Refined output")),
            clipboard: mockClipboard
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(store.state, .converting)

        store.cancelCurrentSession()
        try await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.recoveryFeedback, .canceled)
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testRestartKeepsRecordingResetsBufferAndClearsFeedback() async throws {
        let buffer = TrackingBufferAccumulator()
        let resetTracker = ResetHookTracker()
        let store = makeStore(
            permissionsAuthorized: true,
            bufferAccumulator: buffer,
            resetSessionMonitoring: { resetTracker.callCount += 1 }
        )
        store.arm()
        XCTAssertEqual(buffer.resetCount, 1)

        store.restartCurrentSession()

        XCTAssertEqual(store.state, .recording)
        XCTAssertEqual(store.recoveryFeedback, .restarted)
        XCTAssertEqual(buffer.resetCount, 2)
        XCTAssertEqual(resetTracker.callCount, 1)

        try await Task.sleep(nanoseconds: 1_700_000_000)

        XCTAssertNil(store.recoveryFeedback)
        XCTAssertEqual(store.state, .recording)
    }

    func testRestartLeavesClipboardUntouched() {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            clipboard: mockClipboard
        )
        store.arm()

        store.restartCurrentSession()

        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testEmptyOrWhitespaceOnlyTranscriptionDoesNotReachClipboard() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("   \n  ")),
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.state, .failure(reason: .noSpeechDetected))
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testOverflowFailureMapsToWordLimitExceeded() async throws {
        let overflowAccumulator = OverflowingAccumulator()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Convert to Slack")),
            bufferAccumulator: overflowAccumulator
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.state, .failure(reason: .wordLimitExceeded))
    }

    func testHandleCaptureFailureMapsPermissionDeniedAndAvoidsClipboardWrite() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            clipboard: mockClipboard
        )
        store.arm()

        store.handleCaptureFailure(.microphonePermissionDenied)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state, .failure(reason: .microphonePermissionDenied))
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testHandleCaptureFailureDuringProcessingSuppressesLateClipboardWrite() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: DelayedWhisperTranscriber(delayNanoseconds: 300_000_000, result: .success("late result")),
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        XCTAssertEqual(store.state, .processing)

        store.handleCaptureFailure(.selectedInputDisconnected)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(store.state, .failure(reason: .selectedMicrophoneDisconnected))
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func test_finish_fails_no_speech() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .failure(TranscriptionError.noSpeechDetected))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.state, .failure(reason: .noSpeechDetected))
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func test_copyLastTranscription_writes_to_clipboard() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        // Clear clipboard mock to isolate behavior
        mockClipboard.clearWriteCount()

        store.copyLastTranscription()

        XCTAssertEqual(mockClipboard.lastWrittenText, "Target text")
        XCTAssertEqual(mockClipboard.writeCount, 1)
    }

    func test_pasteCurrentSuccessResult_usesTapTimeClipboardSnapshot() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 200_000_000)

        mockClipboard.clearWriteCount()
        mockClipboard.stubbedClipboardContent = "user changed clipboard"

        store.pasteCurrentSuccessResult()
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Target text"])
        XCTAssertEqual(mockClipboard.lastRestoredSnapshot?.plainText, "user changed clipboard")
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
        XCTAssertEqual(pasteStub.pasteCount, 1)
    }

    func test_pasteCurrentSuccessResult_withoutPostEventPermission_requestsGuidance() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        var permissionPromptCount = 0
        store.onPastePermissionNeeded = {
            permissionPromptCount += 1
        }

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 200_000_000)

        mockClipboard.clearWriteCount()

        store.pasteCurrentSuccessResult()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(permissionPromptCount, 1)
        XCTAssertEqual(pasteStub.pasteCount, 0)
        XCTAssertTrue(mockClipboard.temporaryWriteTexts.isEmpty)
        XCTAssertEqual(mockClipboard.restoreCallCount, 0)
        XCTAssertTrue(store.state.isSuccess)
    }

    func test_copyCurrentSuccessResult_usesConvertedText() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("clanker make this formal")),
            llmRewriter: MockLLMRewriter(result: .success("Converted output")),
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        mockClipboard.clearWriteCount()

        store.copyCurrentSuccessResult()

        XCTAssertEqual(mockClipboard.lastWrittenText, "Converted output")
        XCTAssertEqual(mockClipboard.writeCount, 1)
    }

    func test_convertedSuccess_setsDismissTiming() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false
        preferences.allowClipboardAccess = false

        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("clanker make this formal")),
            llmRewriter: MockLLMRewriter(result: .success("Converted output")),
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        if case .success(let text, _, let converted, _, _) = store.state {
            XCTAssertEqual(text, "Converted output")
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected converted success state")
        }

        let startedAt = try XCTUnwrap(store.successDismissStartedAt)
        let deadline = try XCTUnwrap(store.successDismissDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(startedAt), 6, accuracy: 0.05)
    }

    func test_successStatePersistsBeyondTwoSeconds() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 200_000_000)
        try await Task.sleep(nanoseconds: 2_200_000_000)

        XCTAssertTrue(store.state.isSuccess)
    }

    func test_successActionResetsDismissTimer() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 200_000_000)
        let originalStartedAt = try XCTUnwrap(store.successDismissStartedAt)
        let originalDeadline = try XCTUnwrap(store.successDismissDeadline)
        try await Task.sleep(nanoseconds: 5_500_000_000)

        store.copyCurrentSuccessResult()
        let refreshedStartedAt = try XCTUnwrap(store.successDismissStartedAt)
        let refreshedDeadline = try XCTUnwrap(store.successDismissDeadline)
        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertGreaterThan(refreshedStartedAt, originalStartedAt)
        XCTAssertGreaterThan(refreshedDeadline, originalDeadline)
        XCTAssertTrue(store.state.isSuccess)
    }

    func test_successDismissTimingClearsWhenReturningToIdle() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(store.successDismissStartedAt)
        XCTAssertNotNil(store.successDismissDeadline)

        try await Task.sleep(nanoseconds: 6_200_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertNil(store.successDismissStartedAt)
        XCTAssertNil(store.successDismissDeadline)
    }

    func test_dismissCurrentSuccess_transitionsImmediatelyToIdleAndClearsDismissTiming() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(store.state.isSuccess)
        XCTAssertNotNil(store.successDismissStartedAt)
        XCTAssertNotNil(store.successDismissDeadline)

        store.dismissCurrentSuccess()

        XCTAssertEqual(store.state, .idle)
        XCTAssertNil(store.successDismissStartedAt)
        XCTAssertNil(store.successDismissDeadline)
    }

    func test_dismissCurrentSuccess_isNoOpOutsideSuccess() {
        let store = makeStore(permissionsAuthorized: true)
        store.arm()

        store.dismissCurrentSuccess()

        XCTAssertEqual(store.state, .recording)
    }

    func test_successCountdownStyle_progressAndColorRamp() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 100)
        let deadline = startedAt.addingTimeInterval(6)

        XCTAssertEqual(
            SuccessPillCountdownStyle.remainingProgress(
                startedAt: startedAt,
                deadline: deadline,
                now: startedAt
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SuccessPillCountdownStyle.remainingProgress(
                startedAt: startedAt,
                deadline: deadline,
                now: deadline
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SuccessPillCountdownStyle.warningProgress(
                startedAt: startedAt,
                now: startedAt.addingTimeInterval(4)
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SuccessPillCountdownStyle.warningProgress(
                startedAt: startedAt,
                now: startedAt.addingTimeInterval(6)
            ),
            1,
            accuracy: 0.001
        )

        let startBoundary = SuccessPillCountdownStyle.boundaryColor(progress: 0)
        XCTAssertEqual(startBoundary.red, 183 / 255, accuracy: 0.001)
        XCTAssertEqual(startBoundary.green, 246 / 255, accuracy: 0.001)
        XCTAssertEqual(startBoundary.blue, 214 / 255, accuracy: 0.001)

        let endBoundary = SuccessPillCountdownStyle.boundaryColor(progress: 1)
        XCTAssertEqual(endBoundary.red, 1, accuracy: 0.001)
        XCTAssertEqual(endBoundary.green, 132 / 255, accuracy: 0.001)
        XCTAssertEqual(endBoundary.blue, 132 / 255, accuracy: 0.001)
    }

    func test_arm_while_recording_is_ignored() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success("toggled"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: ActivationStoreMockClipboard()
        )
        store.arm() // -> .recording
        XCTAssertEqual(store.state, .recording)

        store.arm() // second arm while recording should be ignored

        XCTAssertEqual(store.state, .recording)
    }

    func test_arm_while_processing_is_ignored() async throws {
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: DelayedWhisperTranscriber(delayNanoseconds: 500_000_000)
        )
        store.arm()
        store.finish()
        XCTAssertEqual(store.state, .processing)

        store.arm()

        XCTAssertEqual(store.state, .processing)
    }

    func testRapidRepeatedHotkeyAfterSuccessDoesNotSilentlyRearm() async throws {
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("ready")),
            clipboard: ActivationStoreMockClipboard()
        )
        var timestamps = [0.0, 0.2, 0.7].makeIterator()
        let hotkeyService = HotkeyService(
            minimumActivationInterval: 0.35,
            currentState: {
                store.state
            },
            onArm: {
                store.arm()
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(hotkeyService.handleKeyDown()) // start

        // In production the same physical Ctrl-V press routes through the
        // separate .stopSession shortcut handler while recording.
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        if case .success(let text, _, _, _, _) = store.state {
            XCTAssertEqual(text, "ready")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }

        XCTAssertTrue(hotkeyService.handleKeyDown()) // stale repeat should be ignored
        if case .success(let text, _, _, _, _) = store.state {
            XCTAssertEqual(text, "ready")
        } else {
            XCTFail("Expected .success state after ignored repeat, got \(store.state)")
        }

        XCTAssertTrue(hotkeyService.handleKeyDown()) // later press should start a fresh session
        XCTAssertEqual(store.state, .recording)
    }

    // MARK: - Re-arm after terminal state (bug fix regression test)

    /// Verifies that pressing Ctrl-V during .success state correctly transitions
    /// back to .recording without errors — the core crash-on-relaunch fix.
    func test_arm_after_success_rearms_cleanly() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("first")),
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        if case .success(let text, _, _, _, _) = store.state {
            XCTAssertEqual(text, "first")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }

        // Re-arm while still in .success (before auto-dismiss timer fires)
        store.arm()

        XCTAssertEqual(store.state, .recording, "Re-arming during .success should transition cleanly to .recording")
    }

    /// Verifies that pressing Ctrl-V during .failure state correctly transitions
    /// back to .recording without errors.
    func test_arm_after_failure_rearms_cleanly() {
        let store = makeStore(permissionsAuthorized: true)
        store.arm()
        store.handleCaptureFailure(.noUsableInputDevice)

        XCTAssertEqual(store.state, .failure(reason: .microphoneUnavailable))

        // Re-arm while in .failure
        store.arm()

        XCTAssertEqual(store.state, .recording, "Re-arming during .failure should transition cleanly to .recording")
    }

    func test_failure_does_not_write_clipboard() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .failure(TranscriptionError.inferenceFailed))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(mockClipboard.lastWrittenText)
        if case .failure = store.state {
            // pass
        } else {
            XCTFail("Expected .failure state, got \(store.state)")
        }
    }

    func test_trigger_dictation_produces_converted_clipboard_output() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("clanker Please schedule a meeting for Friday convert to email")
        )
        let mockRewriter = MockLLMRewriter(result: .success("Subject: Meeting Request\n\nPlease schedule..."))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Subject: Meeting Request\n\nPlease schedule...")
        XCTAssertEqual(store.lastConvertedTranscription, "Subject: Meeting Request\n\nPlease schedule...")
        if case .success(_, _, let converted, _, _) = store.state {
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testConfiguredRewriteSystemPromptPrefixIsPassedToAssistantGenerate() async throws {
        let suiteName = "ActivationStoreTests.RewritePromptPrefix.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.rewriteSystemPromptPrefix = "Custom rewrite prefix"
        preferences.allowClipboardAccess = false

        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("clanker Please schedule a meeting for Friday convert to email")
        )
        let mockRewriter = MockLLMRewriter(result: .success("Converted output"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGenerateSystemPrompt, "Custom rewrite prefix")
    }

    func test_finalize_rewrite_failure_surfaces_model_error_not_silent_success() async throws {
        let transcript = "team update clanker make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .failure(LLMRewriteError.generationFailed))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        // Raw transcript should still be in clipboard as safety net
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        // State should be .failure, NOT .success
        if case .failure(let reason) = store.state {
            if case .modelError(let message) = reason {
                XCTAssertTrue(message.contains("Rewrite failed"), "Error message should contain 'Rewrite failed', got: \(message)")
            } else {
                XCTFail("Expected .modelError reason, got \(reason)")
            }
        } else {
            XCTFail("Expected .failure state when rewrite throws, got \(store.state)")
        }
    }

    func test_passthrough_dictation_is_completely_unchanged() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success("Hello world"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
        XCTAssertNil(store.lastConvertedTranscription)
        if case .success(_, _, let converted, _, _) = store.state {
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    // MARK: - Assistant fallback behavior

    func test_trigger_name_mutation_does_not_change_passthrough_finalize_behavior() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Hello world")),
            clipboard: mockClipboard,
            preferences: preferences
        )
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
        if case .success(_, _, let converted, _, _) = store.state {
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_custom_trigger_mutation_keeps_assistant_generation_active() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Helios")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("helios Please schedule a meeting convert to email")
        )
        let mockRewriter = MockLLMRewriter(result: .success("Email output"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, "helios Please schedule a meeting convert to email")
        XCTAssertEqual(
            mockRewriter.lastGenerateSystemPrompt,
            LLMRewriteService.resolveAssistantSystemPrompt(
                promptTemplate: preferences.rewriteSystemPromptPrefix,
                assistantName: "Helios"
            )
        )
    }

    // MARK: - Full-transcript assistant trigger behavior

    func test_finalize_triggered_alias_routes_full_transcript_through_generate() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "capture these notes atlas send this to the team convert to email"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Converted output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
        XCTAssertEqual(
            mockRewriter.lastGenerateSystemPrompt,
            LLMRewriteService.resolveAssistantSystemPrompt(
                promptTemplate: preferences.rewriteSystemPromptPrefix,
                assistantName: "Atlas"
            )
        )
    }

    func test_finalize_no_trigger_alias_keeps_passthrough_behavior() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "convert to email send this to the team"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Should not be called"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(mockRewriter.lastCalledOverload)
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        if case .success(_, _, let converted, _, _) = store.state {
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_single_word_after_alias_still_activates_conversion() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "convert to email weekly update atlas ok"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Assistant output")
        if case .success(_, _, let converted, _, _) = store.state {
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_repeated_alias_mentions_still_route_full_transcript() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas convert to email first draft atlas final update convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
    }

    func test_finalize_alias_at_start_routes_full_transcript() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas please send this update to the team convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Assistant output")
        if case .success(let text, _, let converted, _, _) = store.state {
            XCTAssertEqual(text, "Assistant output")
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_alias_in_middle_routes_full_transcript() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "status update for engineering atlas convert to email or convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Assistant output")
    }

    func test_finalize_triggered_assistant_prompt_preserves350WordGate() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let longBody = Array(repeating: "word", count: 351).joined(separator: " ")
        let transcript = "\(longBody) atlas rewrite this as a concise executive update"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Should not be called"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(store.state, .failure(reason: .wordLimitExceeded))
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        XCTAssertEqual(mockRewriter.generateCallCount, 0)
    }

    // MARK: - Clipboard-aware assistant tests

    func test_clipboardIntent_detected_injectsClipboardContent() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.allowClipboardAccess = true
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "clanker format what I copied"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Formatted clipboard text"))
        mockRewriter.queuedGenerateResults = [
            .success("YES"),
            .success("Formatted clipboard text")
        ]
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "some raw clipboard text"
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.generateCallCount, 2)
        XCTAssertEqual(mockRewriter.generatePrompts.first, transcript)
        XCTAssertTrue(mockRewriter.generateSystemPrompts.first?.contains("binary intent classifier") ?? false)
        XCTAssertTrue(mockRewriter.generatePrompts.last?.contains("Clipboard content:") ?? false)
        XCTAssertTrue(mockRewriter.generatePrompts.last?.contains("some raw clipboard text") ?? false)

        if case .success(let text, _, _, _, let clipboardInjected) = store.state {
            XCTAssertEqual(text, "Formatted clipboard text")
            XCTAssertTrue(clipboardInjected)
        } else {
            XCTFail("Expected success state, got \(store.state)")
        }
    }

    func test_clipboardIntent_usesSessionStartSnapshotInsteadOfLiveClipboard() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.allowClipboardAccess = true
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "clanker format what I copied"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Formatted clipboard text"))
        mockRewriter.queuedGenerateResults = [
            .success("YES"),
            .success("Formatted clipboard text")
        ]
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "original snapshot clipboard text"
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        mockClipboard.stubbedClipboardContent = "clipboard changed before rewrite"
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(mockRewriter.generatePrompts.last?.contains("original snapshot clipboard text") ?? false)
        XCTAssertFalse(mockRewriter.generatePrompts.last?.contains("clipboard changed before rewrite") ?? true)
    }

    func test_clipboardIntent_notDetected_skipsClipboard() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.allowClipboardAccess = true
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "clanker make this more formal"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Formal output"))
        mockRewriter.queuedGenerateResults = [
            .success("NO"),
            .success("Formal output")
        ]
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "should not appear"
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.generateCallCount, 2)
        XCTAssertEqual(mockRewriter.generatePrompts.first, transcript)
        XCTAssertFalse(mockRewriter.generatePrompts.last?.contains("Clipboard content:") ?? true)

        if case .success(_, _, _, _, let clipboardInjected) = store.state {
            XCTAssertFalse(clipboardInjected)
        } else {
            XCTFail("Expected success state, got \(store.state)")
        }
    }

    func test_clipboardAccess_disabled_skipsClassification() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "clanker format what I copied"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Plain rewrite"))
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "should not be read"
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.generateCallCount, 1)
        XCTAssertEqual(mockRewriter.generatePrompts.first, transcript)
        XCTAssertFalse(mockRewriter.generatePrompts.first?.contains("Clipboard content:") ?? true)

        if case .success(_, _, _, _, let clipboardInjected) = store.state {
            XCTAssertFalse(clipboardInjected)
        } else {
            XCTFail("Expected success state, got \(store.state)")
        }
    }

    func test_clipboardAccessDisabled_autoPasteStillRestoresOriginalClipboard() async throws {
        let suiteName = "ActivationStoreTests.ClipboardProtection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.allowClipboardAccess = false

        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "original clipboard"
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Hello world")),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Hello world"])
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
        XCTAssertEqual(pasteStub.pasteCount, 1)
    }

    func test_clipboardIntent_detected_emptyClipboard_proceedsNormally() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.allowClipboardAccess = true
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "clanker format what I copied"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Rewrite of empty input"))
        mockRewriter.queuedGenerateResults = [
            .success("YES"),
            .success("Rewrite of empty input")
        ]
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = nil  // empty clipboard
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.generateCallCount, 2)
        XCTAssertEqual(mockRewriter.generatePrompts.last, transcript)
        if case .success(_, _, _, _, let clipboardInjected) = store.state {
            XCTAssertFalse(clipboardInjected)
        } else {
            XCTFail("Expected success state, got \(store.state)")
        }
    }

    func test_finalize_triggered_generation_failure_fallsBackToRawClipboard() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas please send this update to the team convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .failure(LLMRewriteError.generationFailed))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        if case .failure(let reason) = store.state {
            if case .modelError(let message) = reason {
                XCTAssertTrue(message.contains("Rewrite failed"))
            } else {
                XCTFail("Expected .modelError reason, got \(reason)")
            }
        } else {
            XCTFail("Expected .failure state, got \(store.state)")
        }
    }

    func test_finalize_triggered_generation_failure_in_middle_fallsBackToRawClipboard() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "weekly update on launch metrics atlas make this casual and concise"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .failure(LLMRewriteError.generationFailed))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        if case .failure(let reason) = store.state {
            if case .modelError(let message) = reason {
                XCTAssertTrue(message.contains("Rewrite failed"))
            } else {
                XCTFail("Expected .modelError reason, got \(reason)")
            }
        } else {
            XCTFail("Expected .failure state, got \(store.state)")
        }
    }

    // MARK: - Phase 15 — no-restart trigger updates

    /// After resetAssistantNameToDefault, the default assistant name activates
    /// trigger parsing in the very next session without restarting the app.
    func test_finalize_resetAssistantNameToDefault_updatesAliasesUsedInNextSession() async throws {
        let preferences = makePreferencesWithTriggerStore()
        // Start on a custom name.
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        // Switch back to the default assistant name — no restart.
        preferences.resetAssistantNameToDefault()
        try await Task.sleep(nanoseconds: 80_000_000)

        // The default trigger must now be the active trigger.
        let triggerWord = AssistantDefaults.defaultAssistantName.lowercased()
        let transcript = "please draft a message \(triggerWord) convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload,
                       "Default trigger must activate trigger parsing after resetAssistantNameToDefault without restart")
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
    }

    /// After setCustomTrigger, the new custom primary activates trigger parsing
    /// in the next session without restarting the app.
    func test_finalize_setCustomTrigger_updatesAliasesUsedInNextSession() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.resetAssistantNameToDefault()
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        // Switch to custom name "Helios"
        preferences.setCustomTrigger(primary: "Helios")
        try await Task.sleep(nanoseconds: 80_000_000)

        // "helios" must now be the active trigger — use a clean trailing shortcut
        // so the built-in mode overload path is selected unambiguously.
        let transcript = "project update helios convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload,
                       "Custom trigger 'helios' must activate parsing after setCustomTrigger without restart")
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
    }

    func test_pillCopyControlConfiguration_usesStackedSquaresSymbol() {
        XCTAssertEqual(PillCopyControlConfiguration.symbolName, "square.on.square")
    }

    func test_pillCopyControlConfiguration_disablesNonSuccessStates() {
        XCTAssertEqual(
            PillCopyControlConfiguration.forState(.recording),
            .disabled
        )
        XCTAssertEqual(
            PillCopyControlConfiguration.forState(.processing),
            .disabled
        )
        XCTAssertEqual(
            PillCopyControlConfiguration.forState(.converting),
            .disabled
        )
    }

    func test_pillCopyControlConfiguration_enablesSuccessAndKeepsStableGeometry() {
        let successConfiguration = PillCopyControlConfiguration.forState(
            .success(text: "Hello world", pasted: false, converted: false)
        )

        XCTAssertEqual(successConfiguration, .enabled)
        XCTAssertEqual(PillCopyControlConfiguration.slotWidth, 34)
        XCTAssertEqual(PillCopyControlConfiguration.slotHeight, 34)
        XCTAssertEqual(PillCopyControlConfiguration.controlDiameter, 24)
        XCTAssertEqual(PillCopyControlConfiguration.iconSymbolSize, 12)
        XCTAssertEqual(
            successConfiguration.accessibilityIdentifier,
            PillCopyControlConfiguration.successAccessibilityIdentifier
        )
    }

    // MARK: - Retry from success (prior conversation injection)

    /// Core invariant: restarting from a converted success injects the prior
    /// transcript and LLM output into the next prompt as a <prior_conversation>
    /// block so the model has context for the follow-up request.
    func test_restartFromSuccess_injectsPriorConversationIntoRetryPrompt() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "atlas please make this formal weekly status update"
        let secondTranscript = "make it shorter"

        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockLLMRewriter(result: .success("Formal output"))
        mockRewriter.queuedGenerateResults = [.success("Formal output"), .success("Short output")]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
            preferences: preferences
        )

        // First session
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        guard case .success(_, _, let converted, _, _) = store.state, converted else {
            XCTFail("Expected converted success after first session, got \(store.state)")
            return
        }

        // Retry from success
        store.restartFromSuccess()
        XCTAssertEqual(store.state, .recording)

        // Second session — no trigger word, forceLLMNextSession routes it through LLM
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.generateCallCount, 2, "LLM must be called twice")

        let retryPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)
        XCTAssertTrue(
            retryPrompt.contains("<prior_conversation>"),
            "Retry prompt must contain opening <prior_conversation> tag. Prompt:\n\(retryPrompt)"
        )
        XCTAssertTrue(
            retryPrompt.contains("<user>\(firstTranscript)</user>"),
            "Retry prompt must embed first transcript as <user> turn. Prompt:\n\(retryPrompt)"
        )
        XCTAssertTrue(
            retryPrompt.contains("<assistant>Formal output</assistant>"),
            "Retry prompt must embed first LLM output as <assistant> turn. Prompt:\n\(retryPrompt)"
        )
        XCTAssertTrue(
            retryPrompt.contains("</prior_conversation>"),
            "Retry prompt must contain closing </prior_conversation> tag. Prompt:\n\(retryPrompt)"
        )
        XCTAssertTrue(
            retryPrompt.hasSuffix(secondTranscript),
            "Retry prompt must end with the new transcript. Prompt:\n\(retryPrompt)"
        )
    }

    /// Restarting from a non-converted success (plain transcription) must NOT
    /// add to the retry history — there was no LLM output to replay.
    func test_restartFromSuccess_withNoConversion_doesNotInjectPriorConversation() async throws {
        // No trigger word → plain transcription path (converted = false)
        let firstTranscript = "no trigger word just plain text"
        let secondTranscript = "atlas convert to email follow-up"

        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockLLMRewriter(result: .success("Converted output"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
            preferences: preferences
        )

        // First session — no trigger, goes through plain transcription
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        guard case .success(_, _, let converted, _, _) = store.state, !converted else {
            XCTFail("Expected unconverted success after first session, got \(store.state)")
            return
        }

        store.restartFromSuccess()
        XCTAssertEqual(store.state, .recording)

        // Second session — has trigger word, routes through LLM
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.generateCallCount, 1, "LLM must only be called once (second session)")

        let prompt = try XCTUnwrap(mockRewriter.generatePrompts.first)
        XCTAssertFalse(
            prompt.contains("<prior_conversation>"),
            "Prompt must NOT contain prior_conversation when first session was not converted. Prompt:\n\(prompt)"
        )
    }

    /// Dismissing a success (rather than restarting) must produce a clean prompt
    /// with no prior conversation carry-over.
    func test_dismissCurrentSuccess_nextSessionHasNoPriorConversation() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "atlas convert to slack status update"
        let secondTranscript = "atlas convert to email different request"

        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockLLMRewriter(result: .success("Slack output"))
        mockRewriter.queuedGenerateResults = [.success("Slack output"), .success("Email output")]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        guard case .success = store.state else {
            XCTFail("Expected success after first session, got \(store.state)")
            return
        }

        // Dismiss (not restart) — this must clear the retry history
        store.dismissCurrentSuccess()

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.generateCallCount, 2)

        let secondPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)
        XCTAssertFalse(
            secondPrompt.contains("<prior_conversation>"),
            "Prompt after dismiss must NOT carry prior conversation. Prompt:\n\(secondPrompt)"
        )
        XCTAssertEqual(secondPrompt, secondTranscript)
    }

    /// Appending from success must start a clean session with no prior conversation.
    func test_appendFromSuccess_nextSessionHasNoPriorConversation() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "atlas convert to email status update"
        let secondTranscript = "atlas convert to slack follow up"

        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockLLMRewriter(result: .success("Email output"))
        mockRewriter.queuedGenerateResults = [.success("Email output"), .success("Slack output")]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        guard case .success = store.state else {
            XCTFail("Expected success after first session, got \(store.state)")
            return
        }

        // Append from success — must clear retry history
        store.appendFromSuccess()

        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.generateCallCount, 2)

        let secondPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)
        XCTAssertFalse(
            secondPrompt.contains("<prior_conversation>"),
            "Prompt after appendFromSuccess must NOT carry prior conversation. Prompt:\n\(secondPrompt)"
        )
    }

    /// Multiple consecutive restarts must stack all prior turns in the prompt,
    /// most-recent turn last, so the model sees the full conversation thread.
    func test_multipleRestarts_accumulatePriorConversationTurnsInPrompt() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "atlas make this formal weekly update"
        let secondTranscript = "now make it shorter"
        let thirdTranscript = "add a subject line"

        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
            .success(thirdTranscript),
        ])
        let mockRewriter = MockLLMRewriter(result: .success("unused"))
        mockRewriter.queuedGenerateResults = [
            .success("Formal text"),
            .success("Short text"),
            .success("Final text"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
            preferences: preferences
        )

        // Session 1
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)
        guard case .success(_, _, let c1, _, _) = store.state, c1 else {
            XCTFail("Expected converted success after session 1, got \(store.state)"); return
        }

        // Session 2
        store.restartFromSuccess()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)
        guard case .success(_, _, let c2, _, _) = store.state, c2 else {
            XCTFail("Expected converted success after session 2, got \(store.state)"); return
        }

        // Session 3
        store.restartFromSuccess()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.generateCallCount, 3)

        let thirdPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)

        // Both prior turns must appear in order
        XCTAssertTrue(
            thirdPrompt.contains("<user>\(firstTranscript)</user>"),
            "Third prompt must contain first transcript. Prompt:\n\(thirdPrompt)"
        )
        XCTAssertTrue(
            thirdPrompt.contains("<assistant>Formal text</assistant>"),
            "Third prompt must contain first LLM output. Prompt:\n\(thirdPrompt)"
        )
        XCTAssertTrue(
            thirdPrompt.contains("<user>\(secondTranscript)</user>"),
            "Third prompt must contain second transcript. Prompt:\n\(thirdPrompt)"
        )
        XCTAssertTrue(
            thirdPrompt.contains("<assistant>Short text</assistant>"),
            "Third prompt must contain second LLM output. Prompt:\n\(thirdPrompt)"
        )

        // First turn must appear before second turn
        let firstTurnRange = try XCTUnwrap(thirdPrompt.range(of: "<user>\(firstTranscript)</user>"))
        let secondTurnRange = try XCTUnwrap(thirdPrompt.range(of: "<user>\(secondTranscript)</user>"))
        XCTAssertLessThan(
            firstTurnRange.lowerBound,
            secondTurnRange.lowerBound,
            "Prior turns must be ordered chronologically (first before second)"
        )

        XCTAssertTrue(
            thirdPrompt.hasSuffix(thirdTranscript),
            "Third prompt must end with the new transcript. Prompt:\n\(thirdPrompt)"
        )
    }

    /// The output stored in lastConvertedTranscription must be the raw LLM
    /// output — not decorated with XML tags or prior-conversation markup.
    /// This verifies the correct value gets stored in retry history.
    func test_lastConvertedTranscription_isRawLLMOutput() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        preferences.allowClipboardAccess = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas make this a professional email"
        let expectedOutput = "Dear Team,\n\nPlease find the update attached."

        let mockRewriter = MockLLMRewriter(result: .success(expectedOutput))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success(transcript)),
            llmRewriter: mockRewriter,
            preferences: preferences
        )

        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        let stored = try XCTUnwrap(store.lastConvertedTranscription)
        XCTAssertEqual(stored, expectedOutput,
            "lastConvertedTranscription must equal the raw LLM output, not wrapped in XML")
        XCTAssertFalse(stored.contains("<"), "lastConvertedTranscription must not contain XML markup")
    }

    // MARK: - Helpers

    private func makeStore(
        permissionsAuthorized: Bool,
        postEventAuthorized: Bool = false,
        transcriber: (any WhisperTranscribing)? = nil,
        llmRewriter: (any LLMRewriting)? = nil,
        whisperModelLoadState: (any WhisperModelLoadStateProviding)? = nil,
        clipboard: ClipboardService? = nil,
        pasteService: (any PasteServicing)? = nil,
        bufferAccumulator: AudioBufferAccumulator? = nil,
        resetSessionMonitoring: (@MainActor () -> Void)? = nil,
        preferences: ShellPreferences? = nil
    ) -> ActivationStore {
        let suiteName = "ActivationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let resolvedPreferences = preferences ?? ShellPreferences(userDefaults: defaults)

        return ActivationStore(
            preferences: resolvedPreferences,
            readinessProvider: StubReadinessProvider(
                permissionsAuthorized: permissionsAuthorized,
                postEventAuthorized: postEventAuthorized
            ),
            whisperModelLoadState: whisperModelLoadState ?? StubWhisperModelLoadState(),
            whisperService: transcriber ?? ActivationStoreMockTranscriber(result: .success("")),
            llmRewriteService: llmRewriter ?? MockLLMRewriter(result: .failure(LLMRewriteError.cancelled)),
            clipboardService: clipboard ?? ActivationStoreMockClipboard(),
            pasteService: pasteService ?? PasteService(),
            bufferAccumulator: bufferAccumulator ?? StubBufferAccumulator(),
            resetSessionMonitoring: resetSessionMonitoring ?? {}
        )
    }

    private func makePreferencesWithTriggerStore() -> ShellPreferences {
        let suiteName = "ActivationStoreTests.TriggerProfile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.TriggerProfile")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("TriggerProfileStore.json")
        let triggerStore = TriggerProfileStore(storeURL: storeURL)
        return ShellPreferences(
            userDefaults: defaults,
            triggerProfileStore: triggerStore,
            initialTriggerProfile: .defaultProfile
        )
    }

    private nonisolated func waitUntil(
        timeoutNanoseconds: UInt64,
        pollingNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @Sendable () async -> Bool
    ) async throws -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return true
            }
            try await Task.sleep(nanoseconds: pollingNanoseconds)
        }

        return await condition()
    }
}

// MARK: - Stubs / Mocks

@MainActor
private struct StubReadinessProvider: ReadinessProviding {
    let permissionsAuthorized: Bool
    let postEventAuthorized: Bool

    var snapshot: ReadinessSnapshot {
        let microphoneStatus: PermissionGrantState = permissionsAuthorized ? .authorized : .denied
        let postEventStatus: PermissionGrantState = postEventAuthorized ? .authorized : .notDetermined
        let permissions = [
            PermissionChecklistItem(kind: .microphone, status: microphoneStatus, message: "", isRequired: true),
            PermissionChecklistItem(kind: .postEvent, status: postEventStatus, message: "", isRequired: false),
        ]
        let state: ReadinessState = permissionsAuthorized ? .ready : .blocked
        return ReadinessSnapshot(
            state: state,
            title: "",
            message: "",
            permissions: permissions
        )
    }
}

@MainActor
private final class StubWhisperModelLoadState: WhisperModelLoadStateProviding {
    @Published var phase: WhisperModelLoadState.Phase

    init(phase: WhisperModelLoadState.Phase = .idle) {
        self.phase = phase
    }

    var phasePublisher: AnyPublisher<WhisperModelLoadState.Phase, Never> {
        $phase.eraseToAnyPublisher()
    }
}

/// Mock transcriber scoped to ActivationStoreTests to avoid conflict with WhisperServiceTests.MockWhisperTranscriber
final class ActivationStoreMockTranscriber: WhisperTranscribing, @unchecked Sendable {
    enum MockResult {
        case success(String)
        case failure(Error)
    }

    private let result: MockResult

    init(result: MockResult) {
        self.result = result
    }

    func transcribe(samples: [Float]) async throws -> String {
        switch result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

final class SequentialMockTranscriber: WhisperTranscribing, @unchecked Sendable {
    private let results: [ActivationStoreMockTranscriber.MockResult]
    private var callIndex = 0

    init(results: [ActivationStoreMockTranscriber.MockResult]) {
        self.results = results
    }

    func transcribe(samples: [Float]) async throws -> String {
        let result = callIndex < results.count ? results[callIndex] : results.last!
        callIndex += 1
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}

final class DelayedWhisperTranscriber: WhisperTranscribing, @unchecked Sendable {
    private let delayNanoseconds: UInt64
    private let result: ActivationStoreMockTranscriber.MockResult

    init(delayNanoseconds: UInt64, result: ActivationStoreMockTranscriber.MockResult = .success("delayed")) {
        self.delayNanoseconds = delayNanoseconds
        self.result = result
    }

    func transcribe(samples: [Float]) async throws -> String {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        switch result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

final class DelayedPrepareWhisperTranscriber: WhisperTranscribing, @unchecked Sendable {
    private let prepareDelayNanoseconds: UInt64
    private let result: ActivationStoreMockTranscriber.MockResult

    init(
        prepareDelayNanoseconds: UInt64,
        result: ActivationStoreMockTranscriber.MockResult = .success("delayed")
    ) {
        self.prepareDelayNanoseconds = prepareDelayNanoseconds
        self.result = result
    }

    func prepare(model: WhisperModelChoice) async throws {
        try await Task.sleep(nanoseconds: prepareDelayNanoseconds)
    }

    func transcribe(samples: [Float]) async throws -> String {
        switch result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

/// Mock clipboard service — subclasses ClipboardService (must be non-final) for test interception
class ActivationStoreMockClipboard: ClipboardService {
    private(set) var lastWrittenText: String?
    private(set) var writeCount = 0
    private(set) var temporaryWriteTexts: [String] = []
    private(set) var restoreCallCount = 0
    private(set) var lastRestoredSnapshot: ClipboardSnapshot?
    var stubbedClipboardContent: String?
    var stubbedSnapshotChangeCount = 1
    var didRestoreOriginalClipboard = false

    init() {
        // Use a named pasteboard to avoid polluting the general pasteboard
        let pb = NSPasteboard(name: NSPasteboard.Name("ActivationStoreMockClipboard.\(UUID().uuidString)"))
        super.init(pasteboard: pb)
    }

    @discardableResult
    override func writeToClipboard(_ text: String) -> Bool {
        writeCount += 1
        lastWrittenText = text
        return true
    }

    override func snapshotCurrentClipboard() -> ClipboardSnapshot {
        ClipboardSnapshot.empty(changeCount: stubbedSnapshotChangeCount, plainText: stubbedClipboardContent)
    }

    override func writeTemporaryText(_ text: String) -> ClipboardWriteReceipt? {
        temporaryWriteTexts.append(text)
        stubbedSnapshotChangeCount += 1
        return ClipboardWriteReceipt(changeCount: stubbedSnapshotChangeCount)
    }

    override func restoreClipboard(from snapshot: ClipboardSnapshot, ifUnchangedSince receipt: ClipboardWriteReceipt? = nil) -> Bool {
        restoreCallCount += 1
        lastRestoredSnapshot = snapshot
        didRestoreOriginalClipboard = true
        stubbedSnapshotChangeCount += 1
        return true
    }

    override func readFromClipboard() -> String? {
        stubbedClipboardContent
    }

    func clearWriteCount() {
        writeCount = 0
        lastWrittenText = nil
        temporaryWriteTexts = []
        restoreCallCount = 0
        lastRestoredSnapshot = nil
        didRestoreOriginalClipboard = false
    }
}

/// Stub accumulator returns minimal samples to satisfy the transcription pipeline
class StubBufferAccumulator: AudioBufferAccumulator {
    override func convertToWhisperFormat() throws -> [Float] {
        return [0.0, 0.0, 0.0] // non-empty, won't throw emptyBuffers
    }
}

class OverflowingAccumulator: StubBufferAccumulator {
    override func convertToWhisperFormat() throws -> [Float] {
        throw AudioBufferAccumulatorError.overflow
    }
}

class TrackingBufferAccumulator: StubBufferAccumulator {
    private(set) var resetCount = 0

    override func reset() {
        resetCount += 1
        super.reset()
    }
}

final class ResetHookTracker {
    var callCount = 0
}

final class MockLLMRewriter: LLMRewriting, @unchecked Sendable {
    enum MockResult { case success(String); case failure(Error) }
    enum CalledOverload: Equatable { case instructionsOverload, generateOverload }
    private let result: MockResult
    var generateResult: MockResult?
    var queuedGenerateResults: [MockResult] = []
    private(set) var lastBody: String?
    private(set) var lastInstructions: String?
    private(set) var lastPromptPrefix: String?
    private(set) var lastCalledOverload: CalledOverload?
    private(set) var generateCallCount = 0
    private(set) var lastGeneratePrompt: String?
    private(set) var lastGenerateSystemPrompt: String?
    private(set) var generatePrompts: [String] = []
    private(set) var generateSystemPrompts: [String] = []
    private(set) var setTierCalls: [RewriteModelTier] = []
    private(set) var prewarmCallCount = 0
    private(set) var scheduledIdleUnloadDurations: [UInt64] = []
    private(set) var cancelScheduledUnloadCallCount = 0
    init(result: MockResult) { self.result = result }
    func setTier(_ newTier: RewriteModelTier) async {
        setTierCalls.append(newTier)
    }
    func prewarm() async throws {
        prewarmCallCount += 1
    }
    func rewrite(body: String, instructions: String, promptPrefix: String) async throws -> String {
        lastCalledOverload = .instructionsOverload
        lastBody = body
        lastInstructions = instructions
        lastPromptPrefix = promptPrefix
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
    func generate(prompt: String, systemPrompt: String) async throws -> String {
        generateCallCount += 1
        lastCalledOverload = .generateOverload
        lastGeneratePrompt = prompt
        lastGenerateSystemPrompt = systemPrompt
        generatePrompts.append(prompt)
        generateSystemPrompts.append(systemPrompt)
        let effectiveResult: MockResult
        if !queuedGenerateResults.isEmpty {
            effectiveResult = queuedGenerateResults.removeFirst()
        } else {
            effectiveResult = generateResult ?? result
        }
        switch effectiveResult {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async {
        scheduledIdleUnloadDurations.append(duration)
    }
    func cancelScheduledUnload() async {
        cancelScheduledUnloadCallCount += 1
    }
}

final class DelayedLLMRewriter: LLMRewriting, @unchecked Sendable {
    private let delayNanoseconds: UInt64
    private let result: MockLLMRewriter.MockResult
    private let timingLock = NSLock()
    private var _lastCompletionUptimeNanoseconds: UInt64?

    var lastCompletionUptimeNanoseconds: UInt64? {
        timingLock.lock()
        defer { timingLock.unlock() }
        return _lastCompletionUptimeNanoseconds
    }

    init(delayNanoseconds: UInt64, result: MockLLMRewriter.MockResult) {
        self.delayNanoseconds = delayNanoseconds
        self.result = result
    }

    private func complete() throws -> String {
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }

    func rewrite(body: String, instructions: String, promptPrefix: String) async throws -> String {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let output = try complete()
        timingLock.lock()
        _lastCompletionUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        timingLock.unlock()
        return output
    }

    func generate(prompt: String, systemPrompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let output = try complete()
        timingLock.lock()
        _lastCompletionUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        timingLock.unlock()
        return output
    }
}

final class StubCopyOnlyPasteService: PasteServicing {
    private(set) var pasteCount = 0

    func pasteCurrentClipboard() -> PasteOutcome {
        pasteCount += 1
        return .copiedOnly
    }
}

final class StubSuccessfulPasteService: PasteServicing {
    private(set) var pasteCount = 0

    func pasteCurrentClipboard() -> PasteOutcome {
        pasteCount += 1
        return .pasted
    }
}
