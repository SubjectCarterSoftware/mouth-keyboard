import AppKit
import Combine
import MLXLMCommon
import XCTest
@testable import MouthKeyboard

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
        let mockRewriter = MockRewriter(result: .success("unused"))
        let store = makeStore(
            permissionsAuthorized: true,
            localRewriter: mockRewriter,
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

    func testStartSoundIsDebouncedForNearSimultaneousActivations() {
        var currentTime = Date(timeIntervalSinceReferenceDate: 1_000)
        let store = makeStore(
            permissionsAuthorized: true,
            dateProvider: { currentTime }
        )
        var playCount = 0
        store.soundPlayer = ActivationSoundPlayer(
            playStart: { playCount += 1 }
        )

        store.arm()
        store.stop()

        currentTime = currentTime.addingTimeInterval(0.05)
        store.arm()
        store.stop()

        currentTime = currentTime.addingTimeInterval(0.20)
        store.arm()

        XCTAssertEqual(playCount, 2)
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

    func testFinishHoldSessionPadsShortClipBeforeTranscription() async throws {
        let suiteName = "ActivationStoreTests.ShortHoldPadding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.whisperModel = .baseEN

        let transcriber = CapturingWhisperTranscriber(resultText: "test")
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            whisperModelLoadState: StubWhisperModelLoadState(phase: .ready(model: .baseEN)),
            bufferAccumulator: FixedWhisperSamplesAccumulator(samples: [0.2, 0.1, -0.1, 0.0]),
            preferences: preferences
        )

        XCTAssertTrue(store.beginHoldSession())

        store.finishHoldSession()

        XCTAssertEqual(store.state, .processing)

        await waitUntil { store.state.isTerminal }

        let maybeCapturedSamples = await transcriber.capturedSamples()
        let capturedSamples = try XCTUnwrap(maybeCapturedSamples)
        XCTAssertEqual(capturedSamples.count, 16_000)
        XCTAssertEqual(Array(capturedSamples.prefix(4)), [0.2, 0.1, -0.1, 0.0])
        XCTAssertTrue(capturedSamples.dropFirst(4).allSatisfy { $0 == 0 })

        if case .success(let text, _, _, _, _) = store.state {
            XCTAssertEqual(text, "test")
        } else {
            XCTFail("Expected .success state after padded hold transcription, got \(store.state)")
        }
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
        await waitUntil { store.state.isTerminal }

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
        XCTAssertNil(store.recoveryFeedback)
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

        await waitUntil { store.state.isSuccess }

        XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
        XCTAssertEqual(store.lastTranscription, "Hello world")
        if case .success(let text, _, _, _, _) = store.state {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
        let startedAt = try XCTUnwrap(store.successDismissStartedAt)
        let deadline = try XCTUnwrap(store.successDismissDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(startedAt), 10, accuracy: 0.05)
    }

    func testFinishWaitsForAudioCaptureFinalizationBeforeTranscribing() async throws {
        let transcriber = FinalizationAwareWhisperTranscriber(resultText: "tail kept")
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            bufferAccumulator: FixedWhisperSamplesAccumulator(samples: [0.2, 0.1, -0.1, 0.0])
        )
        var finalized = false
        transcriber.didFinalizeAudioCapture = { finalized }
        store.finalizeAudioCaptureBeforeTranscription = {
            try? await Task.sleep(nanoseconds: 100_000_000)
            finalized = true
        }

        store.arm()
        store.finish()

        await waitUntil { store.state.isTerminal }

        XCTAssertTrue(finalized)
        let didObserveFinalization = await transcriber.didObserveFinalization()
        XCTAssertTrue(didObserveFinalization)
        if case .success(let text, _, _, _, _) = store.state {
            XCTAssertEqual(text, "tail kept")
        } else {
            XCTFail("Expected .success state after finalization-aware transcription, got \(store.state)")
        }
    }

    func testPasteFallbackReportsCopiedOnly() async throws {
        let pasteStub = StubCopyOnlyPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        let suiteName = "ActivationStoreTests.PasteFallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.alwaysAutoPaste = true
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Fallback text")),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()

        await waitUntil { store.state.isTerminal }

        XCTAssertNil(mockClipboard.lastWrittenText)
        if case .success(_, let pasted, let rewritten, _, _) = store.state {
            XCTAssertFalse(pasted, "Synthetic paste failed so UI should show copied-only state")
            XCTAssertFalse(rewritten)
        } else {
            XCTFail("Expected .success state after fallback")
        }
        XCTAssertEqual(pasteStub.pasteCount, 1)
        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Fallback text"])
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
    }

    func testAlwaysAutoPastePastesRawTranscriptionWhenPermissionIsGranted() async throws {
        let suiteName = "ActivationStoreTests.AlwaysAutoPasteRaw.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.alwaysAutoPaste = true

        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "clipboard at recording start"
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Hello world")),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        mockClipboard.stubbedClipboardContent = "clipboard right before raw auto-paste"
        store.finish()

        let reachedSuccess = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.state.isSuccess }
        }

        XCTAssertTrue(reachedSuccess)
        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertEqual(pasteStub.pasteCount, 1)
        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Hello world"])
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
        XCTAssertEqual(mockClipboard.lastRestoredSnapshot?.plainText, "clipboard right before raw auto-paste")
        if case .success(_, let pasted, let rewritten, _, _) = store.state {
            XCTAssertTrue(pasted)
            XCTAssertFalse(rewritten)
        } else {
            XCTFail("Expected .success state after auto paste")
        }
    }

    func testAlwaysAutoPastePastesConvertedOutputWhenPermissionIsGranted() async throws {
        let suiteName = "ActivationStoreTests.AlwaysAutoPasteConverted.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.alwaysAutoPaste = true

        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "clipboard at recording start"
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("buddy Please schedule a meeting for Friday convert to email")
            ),
            localRewriter: DelayedRewriter(
                delayNanoseconds: 300_000_000,
                result: .success("Converted output")
            ),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state == .rewriting }
        mockClipboard.stubbedClipboardContent = "clipboard changed during conversion"

        await waitUntil { store.state.isSuccess }

        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertEqual(pasteStub.pasteCount, 1)
        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Converted output"])
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
        XCTAssertEqual(mockClipboard.lastRestoredSnapshot?.plainText, "clipboard changed during conversion")
        if case .success(let text, let pasted, let rewritten, _, _) = store.state {
            XCTAssertEqual(text, "Converted output")
            XCTAssertTrue(pasted)
            XCTAssertTrue(rewritten)
        } else {
            XCTFail("Expected .success state after rewritten auto paste")
        }
    }

    func testAlwaysAutoPasteRewriteFailurePreservesOriginalClipboard() async throws {
        let suiteName = "ActivationStoreTests.AlwaysAutoPasteRewriteFailure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.alwaysAutoPaste = true

        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "original clipboard"
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("buddy Please schedule a meeting for Friday convert to email")
            ),
            localRewriter: MockRewriter(result: .failure(RewriteError.generationFailed)),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()

        await waitUntil { store.state.isTerminal }

        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertTrue(mockClipboard.temporaryWriteTexts.isEmpty)
        XCTAssertEqual(mockClipboard.restoreCallCount, 0)
        XCTAssertEqual(pasteStub.pasteCount, 0)
        XCTAssertEqual(store.lastTranscription, "buddy Please schedule a meeting for Friday convert to email")
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

        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockClipboard.lastWrittenText, "Clipboard only")
        XCTAssertEqual(pasteStub.pasteCount, 0)
        if case .success(_, let pasted, let rewritten, _, _) = store.state {
            XCTAssertFalse(pasted)
            XCTAssertFalse(rewritten)
        } else {
            XCTFail("Expected .success state after clipboard-only finish")
        }
    }

    func testAlwaysAutoPasteWithoutClipboardRestoreKeepsOutputCopied() async throws {
        let suiteName = "ActivationStoreTests.AutoPasteNoRestore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.alwaysAutoPaste = true
        preferences.restorePreviousClipboardAfterAutoPaste = false

        let pasteStub = StubSuccessfulPasteService()
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Keep copied")),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()

        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(pasteStub.pasteCount, 1)
        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Keep copied"])
        XCTAssertFalse(mockClipboard.didRestoreOriginalClipboard)
        XCTAssertEqual(mockClipboard.restoreCallCount, 0)
    }

    func testCancelDuringRecordingReturnsToIdleWithoutClipboardWrite() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let mockRewriter = MockRewriter(result: .success("unused"))
        let store = makeStore(
            permissionsAuthorized: true,
            localRewriter: mockRewriter,
            clipboard: mockClipboard
        )
        store.arm()

        store.cancelCurrentSession()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertNil(store.recoveryFeedback)
        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertEqual(
            mockRewriter.scheduledIdleUnloadDurations.last,
            LocalRewriteService.idleUnloadDelayNanoseconds
        )
    }

    func testSuccessfulPassthroughSessionSchedulesRewriteModelIdleUnloadAfterReturningToIdle() async throws {
        let mockRewriter = MockRewriter(result: .success("unused"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Hello world")),
            localRewriter: mockRewriter
        )

        store.arm()
        store.finish()
        let reachedSuccess = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.state.isSuccess }
        }

        XCTAssertTrue(reachedSuccess)
        store.dismissCurrentSuccess()
        let scheduledIdleUnload = try await waitUntil(timeoutNanoseconds: 500_000_000) {
            !mockRewriter.scheduledIdleUnloadDurations.isEmpty
        }

        XCTAssertEqual(store.state, .idle)
        XCTAssertTrue(scheduledIdleUnload)
        XCTAssertEqual(
            mockRewriter.scheduledIdleUnloadDurations.last,
            LocalRewriteService.idleUnloadDelayNanoseconds
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
        XCTAssertNil(store.recoveryFeedback)
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testCancelDuringConvertingSuppressesLateConversion() async throws {
        let transcript = "team update buddy make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let preferences = makePreferencesWithTriggerStore()
        let delayedRewriter = DelayedRewriter(
            delayNanoseconds: 500_000_000,
            result: .success("Converted output")
        )
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: delayedRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()

        await waitUntil { store.state == .rewriting }

        store.cancelCurrentSession()
        // Bounded negative wait: let the delayed rewrite (500ms) arrive so we can
        // confirm the cancelled session suppresses it rather than pasting late.
        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertNil(store.recoveryFeedback)
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testImmediateRewriteHoldsConvertingStateBeforeSuccess() async throws {
        let transcript = "team update buddy make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: MockRewriter(result: .success("Refined output")),
            clipboard: mockClipboard
        )

        store.arm()
        store.finish()

        // The rewriting state is held during the minimum display window; nothing
        // is written to the clipboard until success. Wait for rewriting rather
        // than racing a fixed real-time budget (which flakes under suite load).
        await waitUntil { store.state == .rewriting }
        XCTAssertNil(mockClipboard.lastWrittenText)

        await waitUntil { store.state.isSuccess }
        XCTAssertEqual(mockClipboard.lastWrittenText, "Refined output")
        if case .success(let text, _, let rewritten, _, _) = store.state {
            XCTAssertEqual(text, "Refined output")
            XCTAssertTrue(rewritten)
        } else {
            XCTFail("Expected .success state after minimum rewriting display")
        }
    }

    func testDelayedRewriteDoesNotAddExtraDelayAfterMinimumConvertingDisplay() async throws {
        let transcript = "team update buddy make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let preferences = makePreferencesWithTriggerStore()
        let delayedRewriter = DelayedRewriter(
            delayNanoseconds: 300_000_000,
            result: .success("Delayed refined output")
        )
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: delayedRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let enteredConverting = try await waitUntil(timeoutNanoseconds: 400_000_000) {
            await MainActor.run {
                store.state == .rewriting
            }
        }
        XCTAssertTrue(enteredConverting, "Expected assistant-triggered flow to enter .rewriting")

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
        if case .success(let text, _, let rewritten, _, _) = store.state {
            XCTAssertEqual(text, "Delayed refined output")
            XCTAssertTrue(rewritten)
        } else {
            XCTFail("Expected .success state once delayed rewrite completed")
        }
    }

    func testCancelDuringMinimumConvertingDisplaySuppressesClipboardWrite() async throws {
        let transcript = "team update buddy make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: MockRewriter(result: .success("Refined output")),
            clipboard: mockClipboard
        )

        store.arm()
        store.finish()

        await waitUntil { store.state == .rewriting }

        store.cancelCurrentSession()
        // Bounded negative wait: confirm the cancelled session suppresses the
        // pending conversion instead of completing it.
        try await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertNil(store.recoveryFeedback)
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

        await waitUntil { store.recoveryFeedback == nil }

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

        await waitUntil { store.state == .failure(reason: .noSpeechDetected) }

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

        await waitUntil { store.state == .failure(reason: .wordLimitExceeded) }

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

        await waitUntil { store.state == .failure(reason: .noSpeechDetected) }

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

        await waitUntil { store.state.isTerminal }

        // Clear clipboard mock to isolate behavior
        mockClipboard.clearWriteCount()

        store.copyLastTranscription()

        XCTAssertEqual(mockClipboard.lastWrittenText, "Target text")
        XCTAssertEqual(mockClipboard.writeCount, 1)
    }

    func test_copyCurrentSuccessResult_usesConvertedText() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false
        try await Task.sleep(nanoseconds: 80_000_000)

        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("buddy make this formal")),
            localRewriter: MockRewriter(result: .success("Converted output")),
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        mockClipboard.clearWriteCount()

        store.copyCurrentSuccessResult()

        XCTAssertEqual(mockClipboard.lastWrittenText, "Converted output")
        XCTAssertEqual(mockClipboard.writeCount, 1)
    }

    func test_rewrittenSuccess_setsDismissTiming() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("buddy make this formal")),
            localRewriter: MockRewriter(result: .success("Converted output")),
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        if case .success(let text, _, let rewritten, _, _) = store.state {
            XCTAssertEqual(text, "Converted output")
            XCTAssertTrue(rewritten)
        } else {
            XCTFail("Expected rewritten success state")
        }

        let startedAt = try XCTUnwrap(store.successDismissStartedAt)
        let deadline = try XCTUnwrap(store.successDismissDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(startedAt), 10, accuracy: 0.05)
    }

    func test_successStatePersistsBeyondTwoSeconds() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let sleeper = ManualSleeper()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: ActivationStoreMockClipboard(),
            dateProvider: { sleeper.currentDate },
            sleeper: sleeper,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isSuccess }
        await settle()

        // 2.2s of virtual time is well within the 10s dismiss window.
        sleeper.advance(by: 2.2)
        await settle()

        XCTAssertTrue(store.state.isSuccess)

        // Let the dismiss timer fire so its background poll exits cleanly.
        sleeper.advance(by: 60)
        await waitUntil { store.state == .idle }
    }

    func test_successActionResetsDismissTimer() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let sleeper = ManualSleeper()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: ActivationStoreMockClipboard(),
            dateProvider: { sleeper.currentDate },
            sleeper: sleeper,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isSuccess }
        await settle() // let the dismiss timer park at virtual t0 (deadline = +10s)

        let originalStartedAt = try XCTUnwrap(store.successDismissStartedAt)
        let originalDeadline = try XCTUnwrap(store.successDismissDeadline)

        // Advance to just before the original 10s deadline: still in success.
        sleeper.advance(by: 9.5)
        await settle()
        XCTAssertTrue(store.state.isSuccess)

        // A success action resets the countdown from "now" (virtual t=9.5).
        store.copyCurrentSuccessResult()
        await settle()
        let refreshedStartedAt = try XCTUnwrap(store.successDismissStartedAt)
        let refreshedDeadline = try XCTUnwrap(store.successDismissDeadline)

        // Past the *original* deadline but within the refreshed one: still success.
        sleeper.advance(by: 1.2)
        await settle()

        XCTAssertGreaterThan(refreshedStartedAt, originalStartedAt)
        XCTAssertGreaterThan(refreshedDeadline, originalDeadline)
        XCTAssertTrue(store.state.isSuccess)

        // Let the refreshed timer fire so its background poll exits cleanly.
        sleeper.advance(by: 60)
        await waitUntil { store.state == .idle }
    }

    func test_successDismissTimingClearsWhenReturningToIdle() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let sleeper = ManualSleeper()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Target text")),
            clipboard: ActivationStoreMockClipboard(),
            dateProvider: { sleeper.currentDate },
            sleeper: sleeper,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isSuccess }
        await settle()

        XCTAssertNotNil(store.successDismissStartedAt)
        XCTAssertNotNil(store.successDismissDeadline)

        // Past the 10s dismiss window: returns to idle and clears timing.
        sleeper.advance(by: 10.2)
        await waitUntil { store.state == .idle }

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
        await waitUntil { store.state.isSuccess }

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
        let deadline = startedAt.addingTimeInterval(10)

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
                now: startedAt.addingTimeInterval(5)
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SuccessPillCountdownStyle.warningProgress(
                startedAt: startedAt,
                now: startedAt.addingTimeInterval(10)
            ),
            1,
            accuracy: 0.001
        )

        let startBoundary = SuccessPillCountdownStyle.boundaryColor(progress: 0)
        XCTAssertEqual(startBoundary.red, 48 / 255, accuracy: 0.001)
        XCTAssertEqual(startBoundary.green, 209 / 255, accuracy: 0.001)
        XCTAssertEqual(startBoundary.blue, 88 / 255, accuracy: 0.001)

        let endBoundary = SuccessPillCountdownStyle.boundaryColor(progress: 1)
        XCTAssertEqual(endBoundary.red, 1, accuracy: 0.001)
        XCTAssertEqual(endBoundary.green, 132 / 255, accuracy: 0.001)
        XCTAssertEqual(endBoundary.blue, 132 / 255, accuracy: 0.001)
    }

    func test_successCountdownStyle_labelCadence() {
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: nil), "Done")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 0), "Done")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 2.49), "Done")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 2.5), "Closing")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 4.99), "Closing")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 5), "5")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 6), "4")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 7), "3")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 8), "2")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 9), "1")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 10), "1")
    }

    func test_successCountdownStyle_usesNotedLabelWhenResultWasSavedToNote() {
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: nil, wasSavedToNote: true), "Noted")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 0, wasSavedToNote: true), "Noted")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 2.49, wasSavedToNote: true), "Noted")
        XCTAssertEqual(SuccessPillCountdownStyle.label(elapsed: 2.5, wasSavedToNote: true), "Closing")
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

        await waitUntil { store.state.isTerminal }

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

        await waitUntil { store.state.isTerminal }

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

        await waitUntil { store.state.isTerminal }

        XCTAssertNil(mockClipboard.lastWrittenText)
        if case .failure = store.state {
            // pass
        } else {
            XCTFail("Expected .failure state, got \(store.state)")
        }
    }

    func test_trigger_dictation_produces_rewritten_clipboard_output() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("buddy Please schedule a meeting for Friday convert to email")
        )
        let mockRewriter = MockRewriter(result: .success("Subject: Meeting Request\n\nPlease schedule..."))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }
        XCTAssertEqual(mockClipboard.lastWrittenText, "Subject: Meeting Request\n\nPlease schedule...")
        XCTAssertEqual(store.lastRewrittenTranscription, "Subject: Meeting Request\n\nPlease schedule...")
        if case .success(_, _, let rewritten, _, _) = store.state {
            XCTAssertTrue(rewritten)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testStaleLastTranscriptionIsNotUsedAsAssistantContextAfterThirtyMinutes() async throws {
        let initialTranscript = "Hello world"
        let assistantTranscript = "Buddy, clean up my last transcription"
        let transcriber = SequentialMockTranscriber(results: [
            .success(initialTranscript),
            .success(assistantTranscript)
        ])
        let rewriter = MockRewriter(result: .success("Rewritten output"))
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            localRewriter: rewriter,
            dateProvider: { now }
        )

        store.arm()
        store.finish()
        _ = try await waitForSuccess(of: store)
        XCTAssertEqual(store.lastTranscription, initialTranscript)

        store.dismissCurrentSuccess()
        now.addTimeInterval(31 * 60)

        store.arm()
        store.finish()
        _ = try await waitForSuccess(of: store)

        XCTAssertEqual(rewriter.generateCallCount, 1)
        XCTAssertEqual(rewriter.lastGeneratePrompt, assistantTranscript)
        XCTAssertFalse(rewriter.lastGeneratePrompt?.contains("transcript context provided below:") ?? false)
    }

    func testConfiguredRewriteSystemPromptPrefixIsPassedToAssistantGenerate() async throws {
        let suiteName = "ActivationStoreTests.RewritePromptPrefix.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.rewriteSystemPromptPrefix = "Custom rewrite prefix"

        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("buddy Please schedule a meeting for Friday convert to email")
        )
        let mockRewriter = MockRewriter(result: .success("Converted output"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGenerateSystemPrompt, "Custom rewrite prefix")
    }

    func test_finalize_rewrite_failure_surfaces_model_error_not_silent_success() async throws {
        let transcript = "team update buddy make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .failure(RewriteError.generationFailed))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

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
        await waitUntil { store.state.isTerminal }
        XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
        XCTAssertNil(store.lastRewrittenTranscription)
        if case .success(_, _, let rewritten, _, _) = store.state {
            XCTAssertFalse(rewritten)
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
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
        if case .success(_, _, let rewritten, _, _) = store.state {
            XCTAssertFalse(rewritten)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_custom_trigger_mutation_keeps_assistant_generation_active() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Helios")
        try await Task.sleep(nanoseconds: 80_000_000)

        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("helios Please schedule a meeting convert to email")
        )
        let mockRewriter = MockRewriter(result: .success("Email output"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )
        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, "helios Please schedule a meeting convert to email")
        XCTAssertEqual(
            mockRewriter.lastGenerateSystemPrompt,
            LocalRewriteService.resolveAssistantSystemPrompt(
                promptTemplate: preferences.rewriteSystemPromptPrefix,
                assistantName: "Helios"
            )
        )
    }

    // MARK: - Full-transcript assistant trigger behavior

    func test_finalize_triggered_alias_routes_full_transcript_through_generate() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "capture these notes atlas send this to the team convert to email"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Converted output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
        XCTAssertEqual(
            mockRewriter.lastGenerateSystemPrompt,
            LocalRewriteService.resolveAssistantSystemPrompt(
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
        let mockRewriter = MockRewriter(result: .success("Should not be called"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertNil(mockRewriter.lastCalledOverload)
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        if case .success(_, _, let rewritten, _, _) = store.state {
            XCTAssertFalse(rewritten)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_single_word_after_alias_still_activates_conversion() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "convert to email weekly update atlas ok"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Assistant output")
        if case .success(_, _, let rewritten, _, _) = store.state {
            XCTAssertTrue(rewritten)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_repeated_alias_mentions_still_route_full_transcript() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas convert to email first draft atlas final update convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt?.hasPrefix(transcript), true)
    }

    func test_finalize_alias_at_start_routes_full_transcript() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas please send this update to the team convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt?.hasPrefix(transcript), true)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Assistant output")
        if case .success(let text, _, let rewritten, _, _) = store.state {
            XCTAssertEqual(text, "Assistant output")
            XCTAssertTrue(rewritten)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_alias_in_middle_routes_full_transcript() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "status update for engineering atlas convert to email or convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt?.hasPrefix(transcript), true)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Assistant output")
    }

    func test_finalize_triggered_assistantPromptAllowsInputBelowGlobal1500WordGate() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let longBody = repeatedWords(1_200)
        let transcript = "\(longBody) atlas rewrite this as a concise executive update"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        let reachedSuccess = try await waitForSuccess(of: store)

        XCTAssertTrue(reachedSuccess)
        XCTAssertEqual(mockRewriter.generateCallCount, 1)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt?.hasPrefix(transcript), true)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Assistant output")
    }

    func test_finalize_triggered_assistantPromptRejectsInputBeyondDynamicLimit() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        // RewriteModelLimits caps input at the 32k-token practical ceiling, which
        // converts to roughly 23k words. 30k words is reliably over that on any
        // supported machine.
        let longBody = repeatedWords(30_000)
        let transcript = "\(longBody) atlas rewrite this as a concise executive update"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Should not be called"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        let reachedFailure = try await waitForFailure(of: store, reason: .wordLimitExceeded)

        XCTAssertTrue(reachedFailure)
        XCTAssertEqual(store.state, .failure(reason: .wordLimitExceeded))
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        XCTAssertEqual(mockRewriter.generateCallCount, 0)
    }

    // MARK: - External text routing tests

    func test_autoPasteStillRestoresOriginalClipboard() async throws {
        let suiteName = "ActivationStoreTests.ClipboardProtection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.alwaysAutoPaste = true

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
        let reachedSuccess = try await waitForSuccess(of: store)

        XCTAssertTrue(reachedSuccess)
        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Hello world"])
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
        XCTAssertEqual(pasteStub.pasteCount, 1)
    }

    func test_finalize_triggered_generation_failure_fallsBackToRawClipboard() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas please send this update to the team convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .failure(RewriteError.generationFailed))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

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
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "weekly update on launch metrics atlas make this casual and concise"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .failure(RewriteError.generationFailed))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt?.hasPrefix(transcript), true)
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
        try await Task.sleep(nanoseconds: 80_000_000)

        // Switch back to the default assistant name — no restart.
        preferences.resetAssistantNameToDefault()
        try await Task.sleep(nanoseconds: 80_000_000)

        // The default trigger must now be the active trigger.
        let triggerWord = AssistantDefaults.defaultAssistantName.lowercased()
        let transcript = "please draft a message \(triggerWord) convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload,
                       "Default trigger must activate trigger parsing after resetAssistantNameToDefault without restart")
        XCTAssertEqual(mockRewriter.lastGeneratePrompt?.hasPrefix(transcript), true)
    }

    /// After setCustomTrigger, the new custom primary activates trigger parsing
    /// in the next session without restarting the app.
    func test_finalize_setCustomTrigger_updatesAliasesUsedInNextSession() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.resetAssistantNameToDefault()
        try await Task.sleep(nanoseconds: 80_000_000)

        // Switch to custom name "Helios"
        preferences.setCustomTrigger(primary: "Helios")
        try await Task.sleep(nanoseconds: 80_000_000)

        // "helios" must now be the active trigger — use a clean trailing shortcut
        // so the built-in mode overload path is selected unambiguously.
        let transcript = "project update helios convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload,
                       "Custom trigger 'helios' must activate parsing after setCustomTrigger without restart")
        XCTAssertEqual(mockRewriter.lastGeneratePrompt?.hasPrefix(transcript), true)
    }

    func test_finalize_customTriggerNotMentioned_doesNotEnterAssistantRouting() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Helios")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "please send this to finance before noon"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Should not be called"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            localRewriter: mockRewriter,
            clipboard: mockClipboard,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.generateCallCount, 0)
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        XCTAssertEqual(store.lastTranscription, transcript)
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
            PillCopyControlConfiguration.forState(.rewriting),
            .disabled
        )
    }

    func test_pillCopyControlConfiguration_enablesSuccessAndKeepsStableGeometry() {
        let successConfiguration = PillCopyControlConfiguration.forState(
            .success(text: "Hello world", pasted: false, rewritten: false)
        )

        XCTAssertEqual(successConfiguration, .enabled)
        XCTAssertEqual(PillCopyControlConfiguration.slotWidth, 34)
        XCTAssertEqual(PillCopyControlConfiguration.slotHeight, 34)
        XCTAssertEqual(PillCopyControlConfiguration.controlDiameter, 22)
        XCTAssertEqual(PillCopyControlConfiguration.iconSymbolSize, 11)
        XCTAssertEqual(
            successConfiguration.accessibilityIdentifier,
            PillCopyControlConfiguration.successAccessibilityIdentifier
        )
    }

    /// Dismissing a success (rather than restarting) must produce a clean prompt
    /// with no prior conversation carry-over.
    func test_dismissCurrentSuccess_nextSessionHasNoPriorConversation() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "atlas convert to slack status update"
        let secondTranscript = "atlas convert to email different request"

        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockRewriter(result: .success("Slack output"))
        mockRewriter.queuedGenerateResults = [
            .success("Slack output"),
            .success("Email output"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            localRewriter: mockRewriter,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        guard case .success = store.state else {
            XCTFail("Expected success after first session, got \(store.state)")
            return
        }

        // Dismiss (not restart) — the next assistant-triggered request should start clean.
        store.dismissCurrentSuccess()

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        // 2 calls: session 1 rewrite + session 2 rewrite
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
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "atlas convert to email status update"
        let secondTranscript = "atlas convert to slack follow up"

        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockRewriter(result: .success("Email output"))
        mockRewriter.queuedGenerateResults = [
            .success("Email output"),
            .success("Slack output"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            localRewriter: mockRewriter,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        guard case .success = store.state else {
            XCTFail("Expected success after first session, got \(store.state)")
            return
        }

        // Append from success — the next assistant-triggered request should start clean.
        store.appendFromSuccess()

        store.finish()
        await waitUntil { store.state.isTerminal }

        // 2 calls: session 1 rewrite + session 2 rewrite
        XCTAssertEqual(mockRewriter.generateCallCount, 2)

        let secondPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)
        XCTAssertFalse(
            secondPrompt.contains("<prior_conversation>"),
            "Prompt after appendFromSuccess must NOT carry prior conversation. Prompt:\n\(secondPrompt)"
        )
    }

    /// The output stored in lastRewrittenTranscription must be the raw LLM
    /// output — not decorated with XML tags or prior-conversation markup.
    /// This verifies the correct value remains available for follow-up routing.
    func test_lastRewrittenTranscription_isRawLLMOutput() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas make this a professional email"
        let expectedOutput = "Dear Team,\n\nPlease find the update attached."

        let mockRewriter = MockRewriter(result: .success(expectedOutput))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success(transcript)),
            localRewriter: mockRewriter,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        let stored = try XCTUnwrap(store.lastRewrittenTranscription)
        XCTAssertEqual(stored, expectedOutput,
            "lastRewrittenTranscription must equal the raw LLM output, not wrapped in XML")
        XCTAssertFalse(stored.contains("<"), "lastRewrittenTranscription must not contain XML markup")
    }

    func test_assistantNotePhrase_savesRewrittenOutput() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let localRewriter = MockRewriter(result: .success("- first\n- second"))
        localRewriter.queuedGenerateResults = [
            .success("- first\n- second"),
            .success("Bullet summary")
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("Buddy make a note of this turn this into bullet points")
            ),
            localRewriter: localRewriter,
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(
            noteCaptureService.savedContents,
            [
                NoteCaptureContent(
                    title: "Bullet summary",
                    rawTranscription: "Buddy make a note of this turn this into bullet points",
                    assistantOutput: "- first\n- second"
                )
            ]
        )
        XCTAssertEqual(store.successNoteSaveState, .saved)
        XCTAssertEqual(noteCaptureService.savedConfigurations.first, preferences.assistantNoteConfiguration)
    }

    func test_assistantNotePhrase_savesReferencedSelectedTextInNote() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let clipboard = ActivationStoreMockClipboard()
        let pasteService = StubSelectionAwarePasteService(
            clipboard: clipboard,
            queuedCopyResults: [
                .dispatched("hey thanks for the quick reply"),
                .dispatched("hey thanks for the quick reply"),
            ]
        )
        let localRewriter = MockRewriter(result: .success("Thank you for the quick reply."))
        localRewriter.queuedGenerateResults = [
            .success("Thank you for the quick reply."),
            .success("Selected text cleanup")
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("Buddy make a note of this make the selected text more professional")
            ),
            localRewriter: localRewriter,
            contextRouter: ScriptedContextRouter(modes: [.selectedText]),
            noteCaptureService: noteCaptureService,
            clipboard: clipboard,
            pasteService: pasteService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(
            noteCaptureService.savedContents,
            [
                NoteCaptureContent(
                    title: "Selected text cleanup",
                    rawTranscription: "Buddy make a note of this make the selected text more professional",
                    referencedContexts: [
                        NoteCaptureReferencedContext(
                            title: "Selected text",
                            content: "hey thanks for the quick reply"
                        )
                    ],
                    assistantOutput: "Thank you for the quick reply."
                )
            ]
        )
        XCTAssertEqual(store.successNoteSaveState, .saved)
    }

    func test_manualSaveCurrentSuccessResultAsNote_savesPassthroughOutput() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("plain transcript")),
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.successNoteSaveState, .available)

        store.saveCurrentSuccessResultAsNote()

        let didSave = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.successNoteSaveState == .saved }
        }

        XCTAssertTrue(didSave)
        XCTAssertEqual(
            noteCaptureService.savedContents,
            [
                NoteCaptureContent(
                    title: nil,
                    rawTranscription: "plain transcript",
                    assistantOutput: nil
                )
            ]
        )
    }

    func test_requestCurrentSessionResultAsNote_queuesDuringRecordingAndSavesPassthroughOutput() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("plain transcript")),
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        XCTAssertEqual(store.successNoteSaveState, .available)

        store.requestCurrentSessionResultAsNote()
        XCTAssertEqual(store.successNoteSaveState, .queued)

        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.successNoteSaveState, .saved)
        XCTAssertEqual(
            noteCaptureService.savedContents,
            [
                NoteCaptureContent(
                    title: nil,
                    rawTranscription: "plain transcript",
                    assistantOutput: nil
                )
            ]
        )
    }

    func test_requestCurrentSessionResultAsNote_queuesDuringProcessingAndSavesPassthroughOutput() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: DelayedWhisperTranscriber(
                delayNanoseconds: 250_000_000,
                result: .success("plain transcript")
            ),
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()
        XCTAssertEqual(store.state, .processing)

        store.requestCurrentSessionResultAsNote()
        XCTAssertEqual(store.successNoteSaveState, .queued)

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.successNoteSaveState, .saved)
        XCTAssertEqual(noteCaptureService.savedContents.count, 1)
        XCTAssertEqual(noteCaptureService.savedContents.first?.rawTranscription, "plain transcript")
        XCTAssertNil(noteCaptureService.savedContents.first?.assistantOutput)
    }

    func test_requestCurrentSessionResultAsNote_queuesDuringRewritingAndSavesAssistantOutput() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Buddy draft a quick status update")),
            localRewriter: DelayedRewriter(
                delayNanoseconds: 250_000_000,
                result: .success("Here is the cleaned status update.")
            ),
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        await waitUntil { store.state == .rewriting }
        store.requestCurrentSessionResultAsNote()
        XCTAssertEqual(store.successNoteSaveState, .queued)

        let didSucceed = try await waitForSuccess(of: store, timeoutNanoseconds: 3_000_000_000)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.successNoteSaveState, .saved)
        XCTAssertEqual(noteCaptureService.savedContents.count, 1)
        XCTAssertEqual(noteCaptureService.savedContents.first?.rawTranscription, "Buddy draft a quick status update")
        XCTAssertEqual(noteCaptureService.savedContents.first?.assistantOutput, "Here is the cleaned status update.")
    }

    func test_manualSaveCurrentSuccessResultAsNote_savesAssistantOutputWithoutAutomaticNotePhrase() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let localRewriter = MockRewriter(result: .success("Here is the cleaned status update."))
        localRewriter.queuedGenerateResults = [
            .success("Here is the cleaned status update."),
            .success("Quick status update")
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Buddy draft a quick status update")),
            localRewriter: localRewriter,
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.successNoteSaveState, .available)

        store.saveCurrentSuccessResultAsNote()

        let didSave = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.successNoteSaveState == .saved }
        }

        XCTAssertTrue(didSave)
        XCTAssertEqual(
            noteCaptureService.savedContents,
            [
                NoteCaptureContent(
                    title: "Quick status update",
                    rawTranscription: "Buddy draft a quick status update",
                    assistantOutput: "Here is the cleaned status update."
                )
            ]
        )
    }

    func test_manualSaveCurrentSuccessResultAsNote_preventsDuplicateWrites() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("plain transcript")),
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        store.saveCurrentSuccessResultAsNote()
        let didSave = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.successNoteSaveState == .saved }
        }
        XCTAssertTrue(didSave)

        store.saveCurrentSuccessResultAsNote()
        XCTAssertEqual(noteCaptureService.savedContents.count, 1)
    }

    func test_successWithoutConfiguredNoteDestination_disablesManualNoteSave() async throws {
        let preferences = makePreferencesWithTriggerStore()
        let noteCaptureService = StubNoteCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("plain transcript")),
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.successNoteSaveState, .disabledMissingConfiguration)

        store.saveCurrentSuccessResultAsNote()
        XCTAssertTrue(noteCaptureService.savedContents.isEmpty)
    }

    func test_assistantNotePhrase_doesNotSaveWhenRewriteFails() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("Buddy make a note of this summarize the update")
            ),
            localRewriter: MockRewriter(result: .failure(RewriteError.modelLoadFailed)),
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didFail = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run {
                if case .failure = store.state {
                    return true
                }
                return false
            }
        }

        XCTAssertTrue(didFail)
        XCTAssertTrue(noteCaptureService.savedContents.isEmpty)
    }

    func test_assistantNotePhrase_marksQueuedStateBeforeRewriteSuccess() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("Buddy make a note of this summarize the update")
            ),
            localRewriter: DelayedRewriter(
                delayNanoseconds: 250_000_000,
                result: .success("Summary output")
            ),
            noteCaptureService: noteCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didQueue = try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            await MainActor.run {
                store.state == .rewriting && store.successNoteSaveState == .queued
            }
        }

        XCTAssertTrue(didQueue)

        let didSucceed = try await waitForSuccess(of: store, timeoutNanoseconds: 3_000_000_000)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.successNoteSaveState, .saved)
        XCTAssertEqual(noteCaptureService.savedContents.count, 1)
        XCTAssertEqual(noteCaptureService.savedContents.first?.rawTranscription, "Buddy make a note of this summarize the update")
        XCTAssertEqual(noteCaptureService.savedContents.first?.assistantOutput, "Summary output")
    }

    func test_rawSuccess_savesHistoryWhenEnabled() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("plain transcript")),
            historyCaptureService: historyCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            historyCaptureService.savedContents.count == 1
        }

        XCTAssertTrue(didPersist)
        XCTAssertEqual(
            historyCaptureService.savedContents,
            [HistoryCaptureContent(rawTranscription: "plain transcript", assistantOutput: nil)]
        )
        XCTAssertEqual(historyCaptureService.savedConfigurations.first, preferences.historyConfiguration)
    }

    func test_assistantSuccess_savesHistoryWhenEnabled() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("Buddy rewrite this professionally")
            ),
            localRewriter: MockRewriter(result: .success("Professional rewrite")),
            historyCaptureService: historyCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            historyCaptureService.savedContents.count == 1
        }

        XCTAssertTrue(didPersist)
        XCTAssertEqual(
            historyCaptureService.savedContents,
            [
                HistoryCaptureContent(
                    rawTranscription: "Buddy rewrite this professionally",
                    assistantOutput: "Professional rewrite"
                )
            ]
        )
    }

    func test_historyDisabled_skipsHistoryWrite() async throws {
        let preferences = makePreferencesWithTriggerStore()
        let historyCaptureService = StubHistoryCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("plain transcript")),
            historyCaptureService: historyCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertTrue(historyCaptureService.savedContents.isEmpty)
    }

    // MARK: - Helpers

    private func makeStore(
        permissionsAuthorized: Bool,
        postEventAuthorized: Bool = false,
        transcriber: (any WhisperTranscribing)? = nil,
        localRewriter: (any Rewriting)? = nil,
        contextRouter: (any AssistantContextRouting)? = nil,
        whisperModelLoadState: (any WhisperModelLoadStateProviding)? = nil,
        noteCaptureService: (any NoteCapturing)? = nil,
        historyCaptureService: (any HistoryCapturing)? = nil,
        clipboard: ClipboardService? = nil,
        pasteService: (any PasteServicing)? = nil,
        bufferAccumulator: AudioBufferAccumulator? = nil,
        dateProvider: (() -> Date)? = nil,
        sleeper: (any Sleeping)? = nil,
        resetSessionMonitoring: (@MainActor () -> Void)? = nil,
        preferences: ShellPreferences? = nil,
        screenshotCollector: RecordingScreenshotCollector? = nil
    ) -> ActivationStore {
        let suiteName = "ActivationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let resolvedPreferences = preferences ?? ShellPreferences(userDefaults: defaults)

        let store = ActivationStore(
            preferences: resolvedPreferences,
            readinessProvider: StubReadinessProvider(
                permissionsAuthorized: permissionsAuthorized,
                postEventAuthorized: postEventAuthorized
            ),
            whisperModelLoadState: whisperModelLoadState ?? StubWhisperModelLoadState(),
            whisperService: transcriber ?? ActivationStoreMockTranscriber(result: .success("")),
            localRewriteService: localRewriter ?? MockRewriter(result: .failure(RewriteError.cancelled)),
            contextRouter: contextRouter ?? NoContextRouter(),
            noteCaptureService: noteCaptureService ?? StubNoteCaptureService(),
            historyCaptureService: historyCaptureService ?? StubHistoryCaptureService(),
            clipboardService: clipboard ?? ActivationStoreMockClipboard(),
            pasteService: pasteService ?? PasteService(),
            bufferAccumulator: bufferAccumulator ?? StubBufferAccumulator(),
            dateProvider: dateProvider ?? { Date() },
            sleeper: sleeper ?? SystemSleeper(),
            resetSessionMonitoring: resetSessionMonitoring ?? {},
            screenshotCollector: screenshotCollector
        )
        // Silence real system sounds during the suite. Tests that assert on sound
        // playback override `store.soundPlayer` with their own counting player.
        store.soundPlayer = .silent
        return store
    }

    /// Polls until `condition` holds, yielding briefly between checks. Fails the
    /// test if the condition is not met within `timeout`. Used instead of fixed
    /// sleeps so success/idle transitions are observed as soon as they happen.
    private func waitUntil(
        _ condition: () -> Bool,
        timeout: TimeInterval = 2.0,
        _ message: @autoclosure () -> String = "condition not met in time",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail(message(), file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    /// Gives background tasks a brief real-time window to react to a virtual-time
    /// `advance` (or to park at their sleep). Bounded and tiny; used before
    /// negative assertions like "still in success state".
    private func settle() async {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    private func makeTestImageData() -> Data {
        let size = NSSize(width: 4, height: 4)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image.tiffRepresentation ?? Data()
    }

    private func makePreferencesWithConfiguredNoteDestination(
        mode: AssistantNoteMode = .newFile
    ) -> ShellPreferences {
        let preferences = makePreferencesWithTriggerStore()
        preferences.noteSavingEnabled = true
        preferences.assistantNoteMode = mode

        switch mode {
        case .newFile:
            preferences.assistantNoteFolderPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("MouthKeyboardNotes")
                .appendingPathComponent(UUID().uuidString)
                .path
        case .appendToFile:
            preferences.assistantNoteAppendFilePath = FileManager.default.temporaryDirectory
                .appendingPathComponent("MouthKeyboardNotes")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("md")
                .path
        }

        return preferences
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

    private func repeatedWords(_ count: Int, token: String = "word") -> String {
        Array(repeating: token, count: count).joined(separator: " ")
    }

    private nonisolated func waitForSuccess(
        of store: ActivationStore,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> Bool {
        try await waitUntil(timeoutNanoseconds: timeoutNanoseconds) {
            await MainActor.run { store.state.isSuccess }
        }
    }

    private nonisolated func waitForFailure(
        of store: ActivationStore,
        reason: RecordingState.FailureReason,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> Bool {
        try await waitUntil(timeoutNanoseconds: timeoutNanoseconds) {
            await MainActor.run {
                guard case .failure(let currentReason) = store.state else { return false }
                return currentReason == reason
            }
        }
    }
}

extension ActivationStoreTests {

    func test_route_noneTarget_producesDirectAssistantPrompt() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, write me a thank-you note for the team dinner",
            selectedText: "Some selected text",
            clipboardText: "Some clipboard text",
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .none,
                decisionSource: .modelClassifier
            )
        )

        XCTAssertEqual(body, "Buddy, write me a thank-you note for the team dinner")
        XCTAssertFalse(body.contains("selected context provided below:"))
        XCTAssertFalse(body.contains("copied context provided below:"))
        XCTAssertFalse(body.contains("transcript context provided below:"))
    }

    func test_route_selectedTextTarget_wrapsUserRequestAndSourceContext() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, make what's selected more professional",
            selectedText: "hey thanks for the food it was rly good",
            clipboardText: "Some clipboard text",
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .selectedText,
                decisionSource: .modelClassifier
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, make what's selected more professional

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
            The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
            Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
            Rewrite it to sound more professional and polished.
            Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
            Do not invent new information, describe the change, or return the source text unchanged.
            Return only the transformed text.

            selected context provided below:
            "hey thanks for the food it was rly good"
            """
        )
        XCTAssertFalse(body.contains("Some clipboard text"))
        XCTAssertFalse(body.contains("copied context provided below:"))
    }

    func test_route_clipboardTarget_wrapsUserRequestAndSourceContext() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, format what I copied",
            selectedText: nil,
            clipboardText: "Meeting notes from tuesday: action items - follow up with design team, update roadmap",
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .clipboard,
                decisionSource: .modelClassifier
            )
        )

        XCTAssertTrue(body.contains("User request:\nBuddy, format what I copied"))
        XCTAssertTrue(body.contains("Use the copied context provided below as the exact text to transform."))
        XCTAssertTrue(body.contains("Apply the user request directly to that text itself."))
        XCTAssertTrue(body.contains("Preserve concrete facts unless the user asks to change them."))
        XCTAssertTrue(body.contains("Do not describe the change or return the source text unchanged."))
        XCTAssertTrue(body.contains("Return only the transformed text."))
        XCTAssertTrue(body.contains("copied context provided below:\n\"Meeting notes from tuesday: action items - follow up with design team, update roadmap\""))
        XCTAssertFalse(body.contains("selected text"))
    }

    func test_route_lastTranscriptionTarget_wrapsUserRequestAndSourceContext() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, can you fix my last transcription",
            selectedText: nil,
            clipboardText: nil,
            lastTranscription: "i went too the store and buyed some groceries",
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .lastTranscription,
                decisionSource: .modelClassifier
            )
        )

        XCTAssertTrue(body.contains("User request:\nBuddy, can you fix my last transcription"))
        XCTAssertTrue(body.contains("Use the transcript context provided below as the exact text to transform."))
        XCTAssertTrue(body.contains("Apply the user request directly to that text itself."))
        XCTAssertTrue(body.contains("Preserve concrete facts unless the user asks to change them."))
        XCTAssertTrue(body.contains("Do not describe the change or return the source text unchanged."))
        XCTAssertTrue(body.contains("Return only the transformed text."))
        XCTAssertTrue(body.contains("transcript context provided below:\n\"i went too the store and buyed some groceries\""))
        XCTAssertFalse(body.contains("selected context provided below:"))
        XCTAssertFalse(body.contains("copied context provided below:"))
    }

    func test_route_selectedTextLanguageCleanup_usesDedicatedInstructionBlock() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, check the grammar in what's selected",
            selectedText: "i went too the store and buyed some groceries",
            clipboardText: nil,
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .selectedText,
                decisionSource: .modelClassifier
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, check the grammar in what's selected

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
            The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
            Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
            Correct grammar, spelling, punctuation, wording, and sentence clarity.
            Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
            Do not invent new information, describe the change, or return the source text unchanged.
            Return only the transformed text.

            selected context provided below:
            "i went too the store and buyed some groceries"
            """
        )
    }

    func test_route_selectedTextLanguageCleanupAndProfessionalRewrite_composeInstructions() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, check the grammar in what's selected and make it more professional",
            selectedText: "i went too the store and buyed some groceries",
            clipboardText: nil,
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .selectedText,
                decisionSource: .modelClassifier
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, check the grammar in what's selected and make it more professional

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
            The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
            Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
            Correct grammar, spelling, punctuation, wording, and sentence clarity.
            Rewrite it to sound more professional and polished.
            Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
            Do not invent new information, describe the change, or return the source text unchanged.
            Return only the transformed text.

            selected context provided below:
            "i went too the store and buyed some groceries"
            """
        )
    }

    func test_route_lastTranscriptionToneSofteningAndShorterDirect_composeInstructions() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, make my last transcription nicer and shorter",
            selectedText: nil,
            clipboardText: nil,
            lastTranscription: "this deck is a mess and we need to talk right now",
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .lastTranscription,
                decisionSource: .modelClassifier
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, make my last transcription nicer and shorter

            Use the transcript context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
            The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
            Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
            Rewrite it so it becomes much kinder and more professional while still communicating the same point.
            Keep the same core point, criticism, and urgency unless the user asks to change them.
            Remove insults, profanity, mockery, and personal attacks.
            Do not reverse the sentiment or turn criticism into praise.
            Rewrite it into a shorter, more direct version.
            Cut filler and redundancy while preserving the key point.
            Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
            Do not invent new information, describe the change, or return the source text unchanged.
            Return only the transformed text.

            transcript context provided below:
            "this deck is a mess and we need to talk right now"
            """
        )
    }

    func test_route_selectedTextFormatConflict_lastMentionWins() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, turn what's selected into bullets and then make it one sentence",
            selectedText: "We need analytics validation, support notification, and product sign-off.",
            clipboardText: nil,
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .selectedText,
                decisionSource: .modelClassifier
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, turn what's selected into bullets and then make it one sentence

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
            The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
            Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
            Condense it into one direct sentence.
            Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
            Do not invent new information, describe the change, or return the source text unchanged.
            Return exactly one sentence.

            selected context provided below:
            "We need analytics validation, support notification, and product sign-off."
            """
        )
    }

    func test_route_selectedTextFormatConflict_reverseOrderPrefersTrailingBullets() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, make what's selected one sentence and then turn it into three bullets",
            selectedText: "We need analytics validation, support notification, and product sign-off.",
            clipboardText: nil,
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .selectedText,
                decisionSource: .modelClassifier
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, make what's selected one sentence and then turn it into three bullets

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
            The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
            Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
            Rewrite it as 3 short bullet points.
            Each bullet should contain one concrete point from the source text.
            Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
            Do not invent new information, describe the change, or return the source text unchanged.
            Return only the bullet list.

            selected context provided below:
            "We need analytics validation, support notification, and product sign-off."
            """
        )
    }

    func test_route_multipleDeterministicTargets_appendsAllMatchedSourcesInStableOrder() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, compare what's selected with what I copied and my last transcription",
            selectedText: "selected text content",
            clipboardText: "clipboard content",
            lastTranscription: "last transcription content",
            routingDecision: AssistantContextRoutingDecision(
                matchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .lastTranscription
                    ),
                    AssistantContextMatchedSource(
                        targetMode: .clipboard
                    ),
                    AssistantContextMatchedSource(
                        targetMode: .selectedText
                    ),
                ],
                decisionSource: .modelClassifier
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, compare what's selected with what I copied and my last transcription

            Use the provided sections below as the source text for the user request above.
            Apply the request directly to that source material.
            The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
            Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
            Preserve concrete facts from each section unless the user asks to change them.
            Rewrite, compare, merge, summarize, or combine the provided sections as needed.
            Return only the final transformed result.

            transcript context provided below:
            "last transcription content"

            copied context provided below:
            "clipboard content"

            selected context provided below:
            "selected text content"
            """
        )
    }

    func test_externalTextRouter_explicitLastTranscriptionInjectsStoredTranscript() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Buddy")
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "Hey Sarah, these mock-ups are horrific. Did you even try?"
        let secondTranscript = "buddy make my last transcription sound much more polite"
        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockRewriter(result: .success("Much more polite version"))
        mockRewriter.queuedGenerateResults = [
            .success("Much more polite version"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            localRewriter: mockRewriter,
            contextRouter: ScriptedContextRouter(modes: [.lastTranscription]),
            preferences: preferences
        )

        store.arm()
        store.finish()
        let firstSucceeded = try await waitForSuccess(of: store)
        XCTAssertTrue(firstSucceeded)

        store.arm()
        store.finish()
        let secondSucceeded = try await waitForSuccess(of: store)
        XCTAssertTrue(secondSucceeded)

        let finalPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)
        XCTAssertTrue(
            finalPrompt.contains("User request:\nbuddy make my last transcription sound much more polite")
        )
        XCTAssertTrue(finalPrompt.contains("Use the transcript context provided below as the exact text to transform."))
        XCTAssertTrue(finalPrompt.contains("Apply the user request directly to that text itself."))
        XCTAssertTrue(finalPrompt.contains("Rewrite it so it becomes much kinder and more professional while still communicating the same point."))
        XCTAssertTrue(finalPrompt.contains("Keep the same core point, criticism, and urgency unless the user asks to change them."))
        XCTAssertTrue(finalPrompt.contains("Remove insults, profanity, mockery, and personal attacks."))
        XCTAssertTrue(finalPrompt.contains("Do not reverse the sentiment or turn criticism into praise."))
        XCTAssertTrue(finalPrompt.contains("Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them."))
        XCTAssertTrue(finalPrompt.contains("Do not invent new information, describe the change, or return the source text unchanged."))
        XCTAssertTrue(finalPrompt.contains("Return only the transformed text."))
        XCTAssertTrue(finalPrompt.contains("transcript context provided below:\n\"\(firstTranscript)\""))
        XCTAssertEqual(mockRewriter.generateCallCount, 1)
    }

    func test_externalTextRouter_explicitMultiSourceInjectsAllMatchedSourcesInStableOrder() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Buddy")
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "Please treat this as the prior transcription source."
        let secondTranscript = "buddy combine my last transcription with what I copied and what's selected"
        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockRewriter(result: .success("Combined output"))
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "clipboard context"
        let pasteStub = StubSelectionAwarePasteService(
            clipboard: mockClipboard,
            queuedCopyResults: [
                .unavailable,
                .unavailable,
                .dispatched("initial selection"),
                .dispatched("selected text context"),
            ]
        )
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: transcriber,
            localRewriter: mockRewriter,
            contextRouter: ScriptedContextRouter(
                modes: [.lastTranscription, .clipboard, .selectedText]
            ),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()
        let firstSucceeded = try await waitForSuccess(of: store)
        XCTAssertTrue(firstSucceeded)

        store.arm()
        store.finish()
        let secondSucceeded = try await waitForSuccess(of: store)
        XCTAssertTrue(secondSucceeded)

        XCTAssertEqual(mockRewriter.generateCallCount, 1)
        let finalPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)
        XCTAssertEqual(
            finalPrompt,
            """
            User request:
            buddy combine my last transcription with what I copied and what's selected

            Use the provided sections below as the source text for the user request above.
            Apply the request directly to that source material.
            The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
            Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
            Preserve concrete facts from each section unless the user asks to change them.
            Rewrite, compare, merge, summarize, or combine the provided sections as needed.
            Return only the final transformed result.

            transcript context provided below:
            "\(firstTranscript)"

            copied context provided below:
            "clipboard context"

            selected context provided below:
            "selected text context"
            """
        )
    }

    func test_externalTextRouter_possessiveSelectedTextRequestInjectsCapturedSelection() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Buddy")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "Buddy, can you take the text I've got selected and condense it a little more? It needs to be like a sentence."
        let selectedText = "The next call should be a deep dive on the data-source definitions, alias assignment, and OpenLineage mappings that make our cross-cloud connections possible."
        let transcriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("One-sentence focus point"))
        let mockClipboard = ActivationStoreMockClipboard()
        let pasteStub = StubSelectionAwarePasteService(
            clipboard: mockClipboard,
            queuedCopyResults: [
                .dispatched(selectedText),
                .dispatched(selectedText),
            ]
        )
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: transcriber,
            localRewriter: mockRewriter,
            contextRouter: ScriptedContextRouter(modes: [.selectedText]),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()
        let succeeded = try await waitForSuccess(of: store)
        XCTAssertTrue(succeeded)

        let finalPrompt = try XCTUnwrap(mockRewriter.lastGeneratePrompt)
        XCTAssertTrue(finalPrompt.contains("User request:\nBuddy, can you take the text I've got selected and condense it a little more? It needs to be like a sentence."))
        XCTAssertTrue(finalPrompt.contains("Use the selected context provided below as the exact text to transform."))
        XCTAssertTrue(finalPrompt.contains("Condense it into one direct sentence."))
        XCTAssertTrue(finalPrompt.contains("Return exactly one sentence."))
        XCTAssertTrue(finalPrompt.contains("selected context provided below:\n\"\(selectedText)\""))
    }

    func test_externalTextRouter_tryThatAgainDoesNotReusePriorAssistantOutput() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Jack")
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "jack rewrite this as a concise executive update"
        let secondTranscript = "jack try that again"
        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockRewriter(result: .success("Retry output"))
        mockRewriter.queuedGenerateResults = [
            .success("Initial rewritten output"),
            .success("Retry output"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            localRewriter: mockRewriter,
            preferences: preferences
        )

        store.arm()
        store.finish()
        let firstSucceeded = try await waitForSuccess(of: store)
        XCTAssertTrue(firstSucceeded)

        store.arm()
        store.finish()
        let secondSucceeded = try await waitForSuccess(of: store)
        XCTAssertTrue(secondSucceeded)

        XCTAssertEqual(mockRewriter.generateCallCount, 2)
        let retryPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)
        XCTAssertEqual(retryPrompt, secondTranscript)
        XCTAssertFalse(retryPrompt.contains("<prior_conversation>"))
        XCTAssertFalse(retryPrompt.contains("transcript context provided below:"))
        XCTAssertFalse(retryPrompt.contains("copied context provided below:"))
        XCTAssertFalse(retryPrompt.contains("selected context provided below:"))
    }

    func test_externalTextRouter_tryThatAgainDoesNotReuseLastTranscriptionAfterRawSuccess() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let firstTranscript = "plain raw dictation without trigger words"
        let secondTranscript = "atlas try that again"
        let transcriber = SequentialMockTranscriber(results: [
            .success(firstTranscript),
            .success(secondTranscript),
        ])
        let mockRewriter = MockRewriter(result: .success("Retry output"))
        mockRewriter.queuedGenerateResults = [
            .success("Retry output"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            localRewriter: mockRewriter,
            preferences: preferences
        )

        store.arm()
        store.finish()
        let firstSucceeded = try await waitForSuccess(of: store)
        XCTAssertTrue(firstSucceeded)

        store.arm()
        store.finish()
        let secondSucceeded = try await waitForSuccess(of: store)
        XCTAssertTrue(secondSucceeded)

        XCTAssertEqual(mockRewriter.generateCallCount, 1)
        let retryPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)
        XCTAssertEqual(retryPrompt, secondTranscript)
        XCTAssertFalse(retryPrompt.contains("transcript context provided below:"))
        XCTAssertFalse(retryPrompt.contains("copied context provided below:"))
        XCTAssertFalse(retryPrompt.contains("selected context provided below:"))
    }

    func test_externalTextRouter_explicitClipboardBeatsThisAndInjectsClipboardOnly() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Buddy")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "buddy use what I copied to improve this"
        let transcriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Clipboard rewrite"))
        let mockClipboard = ActivationStoreMockClipboard()
        mockClipboard.stubbedClipboardContent = "clipboard context"
        let pasteStub = StubSelectionAwarePasteService(
            clipboard: mockClipboard,
            queuedCopyResults: [
                .dispatched("initial selection"),
                .dispatched("final selected draft"),
            ]
        )
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: transcriber,
            localRewriter: mockRewriter,
            contextRouter: ScriptedContextRouter(modes: [.clipboard]),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()
        let succeeded = try await waitForSuccess(of: store)
        XCTAssertTrue(succeeded)

        XCTAssertEqual(mockRewriter.generateCallCount, 1)
        let finalPrompt = try XCTUnwrap(mockRewriter.generatePrompts.last)
        XCTAssertTrue(finalPrompt.contains("User request:\nbuddy use what I copied to improve this"))
        XCTAssertTrue(finalPrompt.contains("Use the copied context provided below as the exact text to transform."))
        XCTAssertTrue(finalPrompt.contains("Apply the user request directly to that text itself."))
        XCTAssertTrue(finalPrompt.contains("Preserve concrete facts unless the user asks to change them."))
        XCTAssertTrue(finalPrompt.contains("Do not describe the change or return the source text unchanged."))
        XCTAssertTrue(finalPrompt.contains("Return only the transformed text."))
        XCTAssertTrue(finalPrompt.contains("copied context provided below:\n\"clipboard context\""))
        XCTAssertFalse(finalPrompt.contains("selected context provided below:"))
    }

    func test_externalTextRouter_oversizedReferencedSourceIsNotedNotInjected() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Buddy")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "buddy rewrite what's selected"
        let transcriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockRewriter(result: .success("Sorry, that was too large to process."))
        let mockClipboard = ActivationStoreMockClipboard()
        let oversizedSelection = repeatedWords(30_000, token: "selected")
        let pasteStub = StubSelectionAwarePasteService(
            clipboard: mockClipboard,
            queuedCopyResults: [
                .dispatched(oversizedSelection),
                .dispatched(oversizedSelection),
            ]
        )
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: transcriber,
            localRewriter: mockRewriter,
            contextRouter: ScriptedContextRouter(modes: [.selectedText]),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()
        let succeeded = try await waitForSuccess(of: store)
        XCTAssertTrue(succeeded)

        // The referenced source is too large to inject, but the model is still
        // called with a short "too large" notice instead of its 30k-word text, so it
        // can tell the user honestly rather than answering as if no context existed.
        XCTAssertEqual(mockRewriter.generateCallCount, 1)
        let prompt = try XCTUnwrap(mockRewriter.lastGeneratePrompt)
        XCTAssertTrue(prompt.contains("too large to include"))
        XCTAssertFalse(prompt.contains(oversizedSelection))
        // The 30k-word text must not have leaked into the prompt body.
        XCTAssertLessThan(prompt.split(whereSeparator: { $0.isWhitespace }).count, 200)
    }

    func test_externalTextRouting_mockScenarioMatrix() async {
        let scenarios: [ExternalTextRoutingScenario] = [
            ExternalTextRoutingScenario(
                name: "Explicit selected text fast path",
                dictatedContent: "Buddy, make what's selected sound more professional",
                selectedText: "hey thanks for the quick reply",
                clipboardText: "clipboard fallback should stay unused",
                lastTranscription: "previous transcription should stay unused",
                expectedMatchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .selectedText
                    )
                ],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: """
                User request:
                Buddy, make what's selected sound more professional

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
                The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
                Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
                Rewrite it to sound more professional and polished.
                Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
                Do not invent new information, describe the change, or return the source text unchanged.
                Return only the transformed text.

                selected context provided below:
                "hey thanks for the quick reply"
                """
            ),
            ExternalTextRoutingScenario(
                name: "Explicit clipboard fast path",
                dictatedContent: "Buddy, turn what I copied into a tighter Slack update",
                selectedText: "selected fallback should stay unused",
                clipboardText: "Meeting slipped to Friday. Need design sign-off by noon.",
                lastTranscription: nil,
                expectedMatchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .clipboard
                    )
                ],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: """
                User request:
                Buddy, turn what I copied into a tighter Slack update

                Use the copied context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
                The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
                Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
                Rewrite it as a short Slack-ready update.
                Keep it concise, natural, and professional.
                Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
                Do not invent new information, describe the change, or return the source text unchanged.
                Return only the Slack message.

                copied context provided below:
                "Meeting slipped to Friday. Need design sign-off by noon."
                """
            ),
            ExternalTextRoutingScenario(
                name: "Explicit last transcription fast path",
                dictatedContent: "Buddy, fix my last transcription and make it polite",
                selectedText: nil,
                clipboardText: nil,
                lastTranscription: "hey Sarah this deck is a mess",
                expectedMatchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .lastTranscription
                    )
                ],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: """
                User request:
                Buddy, fix my last transcription and make it polite

                Use the transcript context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
                The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
                Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
                Rewrite it so it becomes much kinder and more professional while still communicating the same point.
                Keep the same core point, criticism, and urgency unless the user asks to change them.
                Remove insults, profanity, mockery, and personal attacks.
                Do not reverse the sentiment or turn criticism into praise.
                Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
                Do not invent new information, describe the change, or return the source text unchanged.
                Return only the transformed text.

                transcript context provided below:
                "hey Sarah this deck is a mess"
                """
            ),
            ExternalTextRoutingScenario(
                name: "Explicit selected text language cleanup",
                dictatedContent: "Buddy, check the grammar in what's selected",
                selectedText: "i went too the store and buyed some groceries",
                clipboardText: nil,
                lastTranscription: nil,
                expectedMatchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .selectedText
                    )
                ],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: """
                User request:
                Buddy, check the grammar in what's selected

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
                The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
                Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
                Correct grammar, spelling, punctuation, wording, and sentence clarity.
                Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
                Do not invent new information, describe the change, or return the source text unchanged.
                Return only the transformed text.

                selected context provided below:
                "i went too the store and buyed some groceries"
                """
            ),
            ExternalTextRoutingScenario(
                name: "Selected text cleanup plus professional rewrite",
                dictatedContent: "Buddy, check the grammar in what's selected and make it more professional",
                selectedText: "i went too the store and buyed some groceries",
                clipboardText: nil,
                lastTranscription: nil,
                expectedMatchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .selectedText
                    )
                ],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: """
                User request:
                Buddy, check the grammar in what's selected and make it more professional

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
                The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
                Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
                Correct grammar, spelling, punctuation, wording, and sentence clarity.
                Rewrite it to sound more professional and polished.
                Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
                Do not invent new information, describe the change, or return the source text unchanged.
                Return only the transformed text.

                selected context provided below:
                "i went too the store and buyed some groceries"
                """
            ),
            ExternalTextRoutingScenario(
                name: "Last transcription nicer and shorter",
                dictatedContent: "Buddy, make my last transcription nicer and shorter",
                selectedText: nil,
                clipboardText: nil,
                lastTranscription: "this deck is a mess and we need to talk right now",
                expectedMatchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .lastTranscription
                    )
                ],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: """
                User request:
                Buddy, make my last transcription nicer and shorter

                Use the transcript context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
                The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
                Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
                Rewrite it so it becomes much kinder and more professional while still communicating the same point.
                Keep the same core point, criticism, and urgency unless the user asks to change them.
                Remove insults, profanity, mockery, and personal attacks.
                Do not reverse the sentiment or turn criticism into praise.
                Rewrite it into a shorter, more direct version.
                Cut filler and redundancy while preserving the key point.
                Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
                Do not invent new information, describe the change, or return the source text unchanged.
                Return only the transformed text.

                transcript context provided below:
                "this deck is a mess and we need to talk right now"
                """
            ),
            ExternalTextRoutingScenario(
                name: "Selected text cleanup plus three bullet output",
                dictatedContent: "Buddy, fix wording in what's selected and turn it into three bullets",
                selectedText: "We still need analytics validation, support notification by Thursday, and product sign-off before launch.",
                clipboardText: nil,
                lastTranscription: nil,
                expectedMatchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .selectedText
                    )
                ],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: """
                User request:
                Buddy, fix wording in what's selected and turn it into three bullets

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
                The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
                Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
                Correct grammar, spelling, punctuation, wording, and sentence clarity.
                Rewrite it as 3 short bullet points.
                Each bullet should contain one concrete point from the source text.
                Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
                Do not invent new information, describe the change, or return the source text unchanged.
                Return only the bullet list.

                selected context provided below:
                "We still need analytics validation, support notification by Thursday, and product sign-off before launch."
                """
            ),
            ExternalTextRoutingScenario(
                name: "Format conflict resolves to the last mention",
                dictatedContent: "Buddy, turn what's selected into bullets and then make it one sentence",
                selectedText: "We need analytics validation, support notification, and product sign-off.",
                clipboardText: nil,
                lastTranscription: nil,
                expectedMatchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .selectedText
                    )
                ],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: """
                User request:
                Buddy, turn what's selected into bullets and then make it one sentence

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
                The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
                Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
                Condense it into one direct sentence.
                Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
                Do not invent new information, describe the change, or return the source text unchanged.
                Return exactly one sentence.

                selected context provided below:
                "We need analytics validation, support notification, and product sign-off."
                """
            ),
            ExternalTextRoutingScenario(
                name: "Multiple explicit sources append every deterministic match",
                dictatedContent: "Buddy, compare what's selected with what I copied and my last transcription",
                selectedText: "Selected draft paragraph.",
                clipboardText: "Clipboard outline bullet.",
                lastTranscription: "Last transcription source.",
                expectedMatchedSources: [
                    AssistantContextMatchedSource(
                        targetMode: .lastTranscription
                    ),
                    AssistantContextMatchedSource(
                        targetMode: .clipboard
                    ),
                    AssistantContextMatchedSource(
                        targetMode: .selectedText
                    ),
                ],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: """
                User request:
                Buddy, compare what's selected with what I copied and my last transcription

                Use the provided sections below as the source text for the user request above.
                Apply the request directly to that source material.
                The request may mention the clipboard, copied text, selected or highlighted text, the screen, or an earlier dictation. All of that text was already captured and is included in full below.
                Never say you cannot access, see, read, or open the clipboard, selection, screen, or audio, and never ask the user to paste or provide the text. Everything needed is already provided below.
                Preserve concrete facts from each section unless the user asks to change them.
                Rewrite, compare, merge, summarize, or combine the provided sections as needed.
                Return only the final transformed result.

                transcript context provided below:
                "Last transcription source."

                copied context provided below:
                "Clipboard outline bullet."

                selected context provided below:
                "Selected draft paragraph."
                """
            ),
            ExternalTextRoutingScenario(
                name: "Vague request stays direct",
                dictatedContent: "Buddy, make this cleaner and easier to read",
                selectedText: "this is the selected sentence that needs cleanup",
                clipboardText: "clipboard fallback",
                lastTranscription: nil,
                expectedMatchedSources: [],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: "Buddy, make this cleaner and easier to read"
            ),
            ExternalTextRoutingScenario(
                name: "Standalone drafting request stays direct",
                dictatedContent: "Buddy, draft a thank-you note for the team dinner",
                selectedText: "selected text should not be injected",
                clipboardText: "clipboard text should not be injected",
                lastTranscription: "last transcription should not be injected",
                expectedMatchedSources: [],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: "Buddy, draft a thank-you note for the team dinner"
            ),
            ExternalTextRoutingScenario(
                name: "Retry phrasing no longer reuses context",
                dictatedContent: "Buddy, try that again",
                selectedText: nil,
                clipboardText: "clipboard text should stay unused",
                lastTranscription: "previous dictated text should stay unused",
                expectedMatchedSources: [],
                expectedDecisionSource: .modelClassifier,
                expectedPromptBody: "Buddy, try that again"
            ),
        ]

        var reports: [String] = []

        for scenario in scenarios {
            let outcome = await runExternalTextRoutingScenario(scenario)
            reports.append(outcome.report)

            XCTAssertEqual(
                outcome.decision.matchedSources,
                scenario.expectedMatchedSources,
                scenario.name
            )
            XCTAssertEqual(
                outcome.decision.decisionSource,
                scenario.expectedDecisionSource,
                scenario.name
            )
            XCTAssertEqual(
                outcome.promptBody,
                scenario.expectedPromptBody,
                scenario.name
            )
        }

        let attachment = XCTAttachment(
            string: reports.joined(separator: "\n\n---\n\n")
        )
        attachment.name = "ExternalTextRoutingScenarioMatrix"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_externalTextRouting_realModelEvaluation() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("run_external_text_eval_tests")
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_EXTERNAL_TEXT_EVAL_TESTS"] == "1" ||
                FileManager.default.fileExists(atPath: markerURL.path),
            "External text routing real-model eval skipped. Set RUN_EXTERNAL_TEXT_EVAL_TESTS=1 or create \(markerURL.path) to run."
        )

        let service = LocalRewriteService(tier: .standard2B)
        defer {
            Task {
                await service.unload()
            }
        }

        try await service.prewarm()

        let scenarios: [RealModelRoutingEvalScenario] = [
            RealModelRoutingEvalScenario(
                name: "Selected text rewrite",
                dictatedContent: "Buddy, make what's selected sound more professional",
                selectedText: "hey thanks for the quick reply. i think we should probably wait until next week before we announce anything",
                clipboardText: nil,
                lastTranscription: nil,
                expectedBehavior: "Should deterministically use selected text and return a more polished rewrite of that text."
            ),
            RealModelRoutingEvalScenario(
                name: "Clipboard to Slack update",
                dictatedContent: "Buddy, turn what I copied into a short Slack update",
                selectedText: nil,
                clipboardText: "Launch moved to Friday. Waiting on final analytics check. Need support heads-up by Thursday afternoon.",
                lastTranscription: nil,
                expectedBehavior: "Should deterministically use clipboard text and produce a concise Slack-style update."
            ),
            RealModelRoutingEvalScenario(
                name: "Last transcription cleanup",
                dictatedContent: "Buddy, fix my last transcription and make it polite",
                selectedText: nil,
                clipboardText: nil,
                lastTranscription: "hey sarah this deck is kind of a mess and i need you to clean it up today",
                expectedBehavior: "Should deterministically use last transcription and rewrite it into a more polite version."
            ),
            RealModelRoutingEvalScenario(
                name: "Selected text to bullet list",
                dictatedContent: "Buddy, turn what's selected into three short bullets",
                selectedText: "We still need to validate analytics, notify support by Thursday afternoon, and confirm the Friday launch timing.",
                clipboardText: nil,
                lastTranscription: nil,
                expectedBehavior: "Should deterministically use selected text and reshape it into a short bullet list."
            ),
            RealModelRoutingEvalScenario(
                name: "Clipboard to action items",
                dictatedContent: "Buddy, turn what I copied into a clean action-item list",
                selectedText: nil,
                clipboardText: "Need design sign-off by noon Friday. Follow up with support after analytics review. Confirm rollout timing with product.",
                lastTranscription: nil,
                expectedBehavior: "Should deterministically use clipboard text and convert it into a cleaner action-item style output."
            ),
            RealModelRoutingEvalScenario(
                name: "Last transcription tightened",
                dictatedContent: "Buddy, tighten my last transcription into one direct sentence",
                selectedText: nil,
                clipboardText: nil,
                lastTranscription: "hey can you maybe take another look at the homepage copy because i think it is still too wordy and i want us to shorten it before launch",
                expectedBehavior: "Should deterministically use last transcription and compress it into a more direct one-sentence rewrite."
            ),
            RealModelRoutingEvalScenario(
                name: "Three deterministic sources in one request",
                dictatedContent: "Buddy, merge my last transcription with what I copied and what's selected into one clean update",
                selectedText: "Selected text says analytics still looks inconsistent.",
                clipboardText: "Copied text says support should be notified by Thursday afternoon.",
                lastTranscription: "last transcription says the rollout should move to Friday",
                expectedBehavior: "Should append last transcription, clipboard, and selected text together in that order beneath the dictated request."
            ),
            RealModelRoutingEvalScenario(
                name: "Selected text grammar plus professional rewrite",
                dictatedContent: "Buddy, check the grammar in what's selected and make it more professional",
                selectedText: "i went too the store and buyed some groceries before the client meeting",
                clipboardText: nil,
                lastTranscription: nil,
                expectedBehavior: "Should deterministically use selected text and combine cleanup with a more professional rewrite."
            ),
            RealModelRoutingEvalScenario(
                name: "Last transcription nicer and shorter",
                dictatedContent: "Buddy, make my last transcription nicer and shorter",
                selectedText: nil,
                clipboardText: nil,
                lastTranscription: "this deck is a mess and we need to talk right now about why it missed the requirements",
                expectedBehavior: "Should deterministically use last transcription and combine tone softening with a shorter rewrite."
            ),
            RealModelRoutingEvalScenario(
                name: "Selected text cleanup into three bullets",
                dictatedContent: "Buddy, fix wording in what's selected and turn it into three bullets",
                selectedText: "We still need analytics validation, support notification by Thursday, and product sign-off before launch.",
                clipboardText: nil,
                lastTranscription: nil,
                expectedBehavior: "Should deterministically use selected text and combine cleanup with a three-bullet output."
            ),
            RealModelRoutingEvalScenario(
                name: "Clipboard professional Slack update",
                dictatedContent: "Buddy, make what I copied more professional and turn it into a short Slack update",
                selectedText: nil,
                clipboardText: "Launch moved to Friday. Waiting on final analytics check. Need support heads-up by Thursday afternoon.",
                lastTranscription: nil,
                expectedBehavior: "Should deterministically use clipboard text and combine professional rewrite with Slack formatting."
            ),
            RealModelRoutingEvalScenario(
                name: "Format conflict resolves to last mention",
                dictatedContent: "Buddy, turn what's selected into bullets and then make it one sentence",
                selectedText: "We need analytics validation, support notification, and product sign-off before launch.",
                clipboardText: nil,
                lastTranscription: nil,
                expectedBehavior: "Should deterministically use selected text and prefer the trailing one-sentence format over the earlier bullet request."
            ),
            RealModelRoutingEvalScenario(
                name: "Format conflict reverse order prefers trailing bullets",
                dictatedContent: "Buddy, make what's selected one sentence and then turn it into three bullets",
                selectedText: "We need analytics validation, support notification, and product sign-off before launch.",
                clipboardText: nil,
                lastTranscription: nil,
                expectedBehavior: "Should deterministically use selected text and prefer the trailing three-bullet format over the earlier one-sentence request."
            ),
            RealModelRoutingEvalScenario(
                name: "Standalone drafting request",
                dictatedContent: "Buddy, draft a thank-you note for the team dinner",
                selectedText: "unused selected text",
                clipboardText: "unused clipboard text",
                lastTranscription: "unused prior dictation",
                expectedBehavior: "Should stay as a direct assistant request because nothing deterministic matches."
            ),
            RealModelRoutingEvalScenario(
                name: "Retry phrasing without context reuse",
                dictatedContent: "Buddy, try that again",
                selectedText: nil,
                clipboardText: "clipboard text should not be injected",
                lastTranscription: "previous dictated text should not be injected",
                expectedBehavior: "Should stay as a direct request with no injected context because retry wording is no longer classified."
            ),
            RealModelRoutingEvalScenario(
                name: "Two deterministic sources in one request",
                dictatedContent: "Buddy, compare the selected text with what I copied and merge them",
                selectedText: "The selected text says the launch is delayed because analytics still needs validation.",
                clipboardText: "The copied text says support should be notified by Thursday afternoon.",
                lastTranscription: nil,
                expectedBehavior: "Should append both selected text and clipboard because both deterministic source buckets match."
            ),
        ]

        let recorder = RecordingRealModelRewriter(base: service)
        var renderedReports: [String] = []

        for scenario in scenarios {
            await recorder.reset()

            let context = ExternalTextSourceContext(
                selectedText: scenario.selectedText,
                clipboardText: scenario.clipboardText,
                lastTranscription: scenario.lastTranscription
            )

            let decision = try await LocalModelAssistantContextRouter.shared.route(
                request: scenario.dictatedContent,
                availableSources: context
            )

            let finalPrompt = ExternalTextPromptBuilder.buildBody(
                dictatedContent: scenario.dictatedContent,
                selectedText: scenario.selectedText,
                clipboardText: scenario.clipboardText,
                lastTranscription: scenario.lastTranscription,
                routingDecision: decision
            )

            let finalOutput = try await recorder.generate(
                prompt: finalPrompt,
                systemPrompt: LocalRewriteService.resolveAssistantSystemPrompt(assistantName: "Buddy")
            )

            let trace = await recorder.trace()
            let report = RealModelRoutingEvalReport(
                scenario: scenario,
                decision: decision,
                finalPrompt: finalPrompt,
                finalOutput: finalOutput,
                trace: trace
            )

            renderedReports.append(report.rendered)
            print(report.consoleBlock)

            XCTAssertFalse(
                finalOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Real model returned empty output for scenario: \(scenario.name)"
            )
        }

        let reportBody = renderedReports.joined(separator: "\n\n===\n\n")
        let attachment = XCTAttachment(string: reportBody)
        attachment.name = "ExternalTextRoutingRealModelEval"
        attachment.lifetime = .keepAlways
        add(attachment)

        let reportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-text-routing-real-model-eval.md")
        try reportBody.write(to: reportURL, atomically: true, encoding: .utf8)
        print("Saved external text routing eval report to: \(reportURL.path)")
    }

    func test_externalTextRouting_lastTranscriptionPromptVariants_realModelEvaluation() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("run_external_text_prompt_variant_eval_tests")
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_EXTERNAL_TEXT_PROMPT_VARIANT_EVAL_TESTS"] == "1" ||
                FileManager.default.fileExists(atPath: markerURL.path),
            "Prompt-variant real-model eval skipped. Set RUN_EXTERNAL_TEXT_PROMPT_VARIANT_EVAL_TESTS=1 or create \(markerURL.path) to run."
        )

        let assistantName = "Buddy"
        let priorTranscript = "Sarah, these designs you've just sent me are like... ungodly. They're an absolute piece of shit and you should be completely ashamed of yourself. We need to meet immediately."
        let dictatedRequest = "Buddy, that last transcription that I did was really mean. Can you make it a lot nicer but still communicate the point?"

        let service = LocalRewriteService(tier: .standard2B)
        defer {
            Task {
                await service.unload()
            }
        }

        try await service.prewarm()

        let context = ExternalTextSourceContext(
            selectedText: nil,
            clipboardText: nil,
            lastTranscription: priorTranscript
        )
        let decision = try await LocalModelAssistantContextRouter.shared.route(
            request: dictatedRequest,
            availableSources: context
        )
        let productionPrompt = ExternalTextPromptBuilder.buildBody(
            dictatedContent: dictatedRequest,
            selectedText: nil,
            clipboardText: nil,
            lastTranscription: priorTranscript,
            routingDecision: decision
        )
        let productionSystemPrompt = LocalRewriteService.resolveAssistantSystemPrompt(
            assistantName: assistantName
        )

        let strongerRewriteSystemPrompt = LocalRewriteService.resolveAssistantSystemPrompt(
            promptTemplate: """
            \(LocalRewriteService.defaultAssistantSystemPromptTemplate)
            When the user asks to make provided text nicer, kinder, less harsh, or more polite, rewrite the provided source text itself to satisfy that request.
            Do not merely correct punctuation, capitalization, or formatting when the request asks for a tone change.
            """,
            assistantName: assistantName
        )

        let variants: [RealModelPromptVariantEvalVariant] = [
            RealModelPromptVariantEvalVariant(
                name: "Current production prompt",
                body: productionPrompt,
                systemPrompt: productionSystemPrompt,
                rationale: "Reproduces the exact body and system prompt currently used in production."
            ),
            RealModelPromptVariantEvalVariant(
                name: "Current body with stronger rewrite system rule",
                body: productionPrompt,
                systemPrompt: strongerRewriteSystemPrompt,
                rationale: "Keeps the production body but adds an explicit system rule that tone-change requests must rewrite the source text itself."
            ),
            RealModelPromptVariantEvalVariant(
                name: "Cleaned inline request",
                body: """
                Buddy, the transcript context provided below was really mean. Can you make it a lot nicer while still communicating the point?

                transcript context provided below:
                "\(priorTranscript)"
                """,
                systemPrompt: productionSystemPrompt,
                rationale: "Removes the awkward inline artifact from simple string replacement while preserving the current overall structure."
            ),
            RealModelPromptVariantEvalVariant(
                name: "Explicit rewrite target wrapper",
                body: """
                User request:
                \(dictatedRequest)

                Rewrite the transcript context provided below so it satisfies the user request above.
                Keep the same core point and overall intent, but make it substantially softer and more professional. Remove insults, profanity, and personal attacks. Do not reverse the sentiment or turn criticism into praise.

                transcript context provided below:
                "\(priorTranscript)"
                """,
                systemPrompt: productionSystemPrompt,
                rationale: "Makes the provided transcript an explicit rewrite target instead of generic background context."
            ),
            RealModelPromptVariantEvalVariant(
                name: "Direct rewrite task",
                body: """
                Rewrite the transcript context provided below so it is much kinder while still clearly communicating the same point.

                transcript context provided below:
                "\(priorTranscript)"
                """,
                systemPrompt: productionSystemPrompt,
                rationale: "Drops the conversational request wrapper and gives the model a direct rewrite instruction."
            ),
        ]

        let recorder = RecordingRealModelRewriter(base: service)
        var renderedReports: [String] = []

        for variant in variants {
            await recorder.reset()

            let finalOutput = try await recorder.generate(
                prompt: variant.body,
                systemPrompt: variant.systemPrompt
            )
            let trace = await recorder.trace()
            let report = RealModelPromptVariantEvalReport(
                dictatedRequest: dictatedRequest,
                priorTranscript: priorTranscript,
                routingDecision: decision,
                variant: variant,
                finalOutput: finalOutput,
                trace: trace
            )

            renderedReports.append(report.rendered)
            print(report.consoleBlock)

            XCTAssertFalse(
                finalOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Real model returned empty output for variant: \(variant.name)"
            )
        }

        let reportBody = renderedReports.joined(separator: "\n\n===\n\n")
        let attachment = XCTAttachment(string: reportBody)
        attachment.name = "ExternalTextLastTranscriptionPromptVariants"
        attachment.lifetime = .keepAlways
        add(attachment)

        let reportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-text-last-transcription-prompt-variants.md")
        try reportBody.write(to: reportURL, atomically: true, encoding: .utf8)
        print("Saved prompt-variant eval report to: \(reportURL.path)")
    }

    private func runExternalTextRoutingScenario(
        _ scenario: ExternalTextRoutingScenario
    ) async -> ExternalTextRoutingScenarioOutcome {
        let decision = AssistantContextRoutingDecision(
            matchedSources: scenario.expectedMatchedSources,
            decisionSource: scenario.expectedDecisionSource
        )

        let promptBody = ExternalTextPromptBuilder.buildBody(
            dictatedContent: scenario.dictatedContent,
            selectedText: scenario.selectedText,
            clipboardText: scenario.clipboardText,
            lastTranscription: scenario.lastTranscription,
            routingDecision: decision
        )

        return ExternalTextRoutingScenarioOutcome(
            scenario: scenario,
            decision: decision,
            promptBody: promptBody
        )
    }
}

private struct ExternalTextRoutingScenario {
    let name: String
    let dictatedContent: String
    let selectedText: String?
    let clipboardText: String?
    let lastTranscription: String?
    let expectedMatchedSources: [AssistantContextMatchedSource]
    let expectedDecisionSource: RoutingDecisionSource
    let expectedPromptBody: String
}

private struct ExternalTextRoutingScenarioOutcome {
    let scenario: ExternalTextRoutingScenario
    let decision: AssistantContextRoutingDecision
    let promptBody: String

    var report: String {
        let selectedText = scenario.selectedText ?? "<nil>"
        let clipboardText = scenario.clipboardText ?? "<nil>"
        let lastTranscription = scenario.lastTranscription ?? "<nil>"
        let matchedSourcesSection = decision.matchedSources.isEmpty
            ? "  <none>"
            : decision.matchedSources.map { matchedSource in
                "  \(matchedSource.targetMode.rawValue)"
            }.joined(separator: "\n")

        return """
        Scenario: \(scenario.name)
        Dictated content:
          \(scenario.dictatedContent)
        Available sources:
          selectedText: \(selectedText)
          clipboardText: \(clipboardText)
          lastTranscription: \(lastTranscription)
        Decision:
          decisionSource: \(String(describing: decision.decisionSource))
        Matched sources:
        \(matchedSourcesSection)
        Final prompt body:
        \(promptBody)
        """
    }
}

private struct RealModelRoutingEvalScenario {
    let name: String
    let dictatedContent: String
    let selectedText: String?
    let clipboardText: String?
    let lastTranscription: String?
    let expectedBehavior: String
}

private struct RealModelPromptVariantEvalVariant {
    let name: String
    let body: String
    let systemPrompt: String
    let rationale: String
}

private struct RealModelPromptVariantEvalReport {
    let dictatedRequest: String
    let priorTranscript: String
    let routingDecision: AssistantContextRoutingDecision
    let variant: RealModelPromptVariantEvalVariant
    let finalOutput: String
    let trace: [RealModelRoutingEvalTraceEntry]

    private var matchedSourcesDescription: String {
        if routingDecision.matchedSources.isEmpty {
            return "  <none>"
        }

        return routingDecision.matchedSources.map { matchedSource in
            "  \(matchedSource.targetMode.rawValue)"
        }.joined(separator: "\n")
    }

    var consoleBlock: String {
        """

        >>> Prompt variant: \(variant.name)
        Rationale:
        \(variant.rationale)
        Prompt:
        \(variant.body)
        Output:
        \(finalOutput)
        """
    }

    var rendered: String {
        let traceSection: String
        if trace.isEmpty {
            traceSection = "Missing generation trace"
        } else {
            traceSection = trace.enumerated().map { index, entry in
                """
                Call \(index + 1) system prompt:
                \(entry.systemPrompt)

                Call \(index + 1) body:
                \(entry.prompt)

                Call \(index + 1) output:
                \(entry.output)
                """
            }.joined(separator: "\n\n")
        }

        return """
        # \(variant.name)

        Rationale:
        \(variant.rationale)

        Dictated request:
        \(dictatedRequest)

        Prior transcript:
        \(priorTranscript)

        Routing decision:
        - decisionSource: \(String(describing: routingDecision.decisionSource))
        Matched sources:
        \(matchedSourcesDescription)

        Generation trace:
        \(traceSection)
        """
    }
}

private struct RealModelRoutingEvalTraceEntry {
    let prompt: String
    let systemPrompt: String
    let output: String
}

private struct RealModelRoutingEvalReport {
    let scenario: RealModelRoutingEvalScenario
    let decision: AssistantContextRoutingDecision
    let finalPrompt: String
    let finalOutput: String
    let trace: [RealModelRoutingEvalTraceEntry]

    private var classifierTrace: [RealModelRoutingEvalTraceEntry] {
        Array(trace.dropLast())
    }

    private var finalGenerationTrace: RealModelRoutingEvalTraceEntry? {
        trace.last
    }

    private var matchedSourcesDescription: String {
        if decision.matchedSources.isEmpty {
            return "  <none>"
        }

        return decision.matchedSources.map { matchedSource in
            "  \(matchedSource.targetMode.rawValue)"
        }.joined(separator: "\n")
    }

    var consoleBlock: String {
        """

        >>> Scenario: \(scenario.name)
        Expected behavior:
        \(scenario.expectedBehavior)
        Decision:
          decisionSource: \(String(describing: decision.decisionSource))
        Matched sources:
        \(matchedSourcesDescription)
        Final prompt:
        \(finalPrompt)
        Final output:
        \(finalOutput)
        """
    }

    var rendered: String {
        let selectedText = scenario.selectedText ?? "<nil>"
        let clipboardText = scenario.clipboardText ?? "<nil>"
        let lastTranscription = scenario.lastTranscription ?? "<nil>"
        let classifierSection: String

        if classifierTrace.isEmpty {
            classifierSection = "None"
        } else {
            classifierSection = classifierTrace.enumerated().map { index, entry in
                """
                Call \(index + 1) prompt:
                \(entry.prompt)

                Call \(index + 1) output:
                \(entry.output)
                """
            }.joined(separator: "\n\n")
        }

        let finalCallSection: String
        if let finalGenerationTrace {
            finalCallSection = """
            Prompt:
            \(finalGenerationTrace.prompt)

            Output:
            \(finalGenerationTrace.output)
            """
        } else {
            finalCallSection = "Missing final generation call"
        }

        return """
        # \(scenario.name)

        Expected behavior:
        \(scenario.expectedBehavior)

        Dictated content:
        \(scenario.dictatedContent)

        Available context:
        - selectedText: \(selectedText)
        - clipboardText: \(clipboardText)
        - lastTranscription: \(lastTranscription)

        Routing decision:
        - decisionSource: \(String(describing: decision.decisionSource))
        Matched sources:
        \(matchedSourcesDescription)

        Classifier trace:
        \(classifierSection)

        Final generation:
        \(finalCallSection)
        """
    }
}

private actor RecordingRealModelRewriter: Rewriting {
    private let base: any Rewriting
    private var entries: [RealModelRoutingEvalTraceEntry] = []

    init(base: any Rewriting) {
        self.base = base
    }

    func reset() {
        entries.removeAll()
    }

    func trace() -> [RealModelRoutingEvalTraceEntry] {
        entries
    }

    func setTier(_ newTier: RewriteModelTier) async {
        await base.setTier(newTier)
    }

    func prewarm() async throws {
        try await base.prewarm()
    }

    func rewrite(body: String, instructions: String, promptPrefix: String) async throws -> String {
        try await base.rewrite(body: body, instructions: instructions, promptPrefix: promptPrefix)
    }

    func rewrite(body: String, instructions: String) async throws -> String {
        try await base.rewrite(body: body, instructions: instructions)
    }

    func generate(prompt: String, systemPrompt: String) async throws -> String {
        let output = try await base.generate(prompt: prompt, systemPrompt: systemPrompt)
        entries.append(
            RealModelRoutingEvalTraceEntry(
                prompt: prompt,
                systemPrompt: systemPrompt,
                output: output
            )
        )
        return output
    }

    func generate(
        prompt: String,
        systemPrompt: String,
        images: [UserInput.Image]
    ) async throws -> String {
        let output = try await base.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            images: images
        )
        entries.append(
            RealModelRoutingEvalTraceEntry(
                prompt: prompt,
                systemPrompt: systemPrompt,
                output: output
            )
        )
        return output
    }

    func loadedTier() async -> RewriteModelTier? {
        await base.loadedTier()
    }

    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async {
        await base.scheduleIdleUnload(afterNanoseconds: duration)
    }

    func cancelScheduledUnload() async {
        await base.cancelScheduledUnload()
    }

    func unload() async {
        await base.unload()
    }

    func deleteDownloadedModel(for tier: RewriteModelTier) async throws {
        try await base.deleteDownloadedModel(for: tier)
    }
}

// MARK: - Stubs / Mocks

/// Virtual-time sleeper for deterministic timer tests. `sleep` suspends until
/// `advance(by:)` has moved virtual time past the requested duration, so the
/// success-dismiss countdown can be exercised without real multi-second waits.
/// Pair it with `dateProvider: { sleeper.currentDate }` so the displayed
/// timestamps advance in lockstep with the firing logic.
final class ManualSleeper: Sleeping, @unchecked Sendable {
    private let lock = NSLock()
    private var elapsedSeconds: TimeInterval = 0
    let start: Date

    init(start: Date = Date(timeIntervalSinceReferenceDate: 1_000_000)) {
        self.start = start
    }

    /// Current virtual time, for use as the store's `dateProvider`.
    var currentDate: Date {
        lock.withLock { start.addingTimeInterval(elapsedSeconds) }
    }

    /// Move virtual time forward. Parked `sleep` calls whose deadline has now
    /// passed return on their next poll (≤ a couple ms later).
    func advance(by seconds: TimeInterval) {
        lock.withLock { elapsedSeconds += seconds }
    }

    private var elapsed: TimeInterval { lock.withLock { elapsedSeconds } }

    func sleep(nanoseconds: UInt64) async {
        guard nanoseconds > 0 else { return }
        // Target is captured against virtual time; real time is irrelevant.
        let target = elapsed + Double(nanoseconds) / 1_000_000_000
        while elapsed < target {
            if Task.isCancelled { return }
            // Tiny real poll just to yield; virtual time is authoritative.
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

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

actor FinalizationAwareWhisperTranscriber: WhisperTranscribing {
    private let resultText: String
    private var observedFinalization = false

    init(resultText: String) {
        self.resultText = resultText
    }

    @MainActor var didFinalizeAudioCapture: () -> Bool = { false }

    func transcribe(samples: [Float]) async throws -> String {
        observedFinalization = await MainActor.run { didFinalizeAudioCapture() }
        return resultText
    }

    func didObserveFinalization() -> Bool {
        observedFinalization
    }
}

/// A `WhisperTranscribing` mock whose `transcribe(samples:)` suspends on a
/// continuation until the test calls `release(with:)`, so tests can pause the
/// pipeline mid-`.processing` (deterministically, via `waitUntilStarted()`)
/// and act — e.g. clear collected attachments — before letting it continue.
actor GatedWhisperTranscriber: WhisperTranscribing {
    private var continuation: CheckedContinuation<String, Error>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func transcribe(samples: [Float]) async throws -> String {
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// Suspends until `transcribe` has actually been entered, so a caller can
    /// be sure the pipeline has reached the transcription step (and, since
    /// `finish()` sets `.processing` synchronously before that step runs,
    /// that `state` has already settled there) before inspecting state or
    /// calling `release`.
    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            self.startContinuation = continuation
        }
    }

    func release(with text: String) {
        continuation?.resume(returning: text)
        continuation = nil
    }
}

final class StubNoteCaptureService: NoteCapturing, @unchecked Sendable {
    enum StubError: Error {
        case failed
    }

    var result: Result<URL, Error> = .success(
        FileManager.default.temporaryDirectory.appendingPathComponent("note.md")
    )
    private(set) var savedContents: [NoteCaptureContent] = []
    private(set) var savedConfigurations: [AssistantNoteConfiguration] = []

    func saveNote(content: NoteCaptureContent, configuration: AssistantNoteConfiguration) throws -> URL {
        savedContents.append(content)
        savedConfigurations.append(configuration)
        return try result.get()
    }
}

final class StubHistoryCaptureService: HistoryCapturing, @unchecked Sendable {
    enum StubError: Error {
        case failed
    }

    var result: Result<URL, Error> = .success(
        FileManager.default.temporaryDirectory.appendingPathComponent("history.txt")
    )
    private let lock = NSLock()
    private var recordedContents: [HistoryCaptureContent] = []
    private var recordedConfigurations: [HistoryConfiguration] = []

    var savedContents: [HistoryCaptureContent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedContents
    }

    var savedConfigurations: [HistoryConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        return recordedConfigurations
    }

    func saveEntry(content: HistoryCaptureContent, configuration: HistoryConfiguration) throws -> URL {
        lock.lock()
        recordedContents.append(content)
        recordedConfigurations.append(configuration)
        lock.unlock()
        return try result.get()
    }

    func listEntries(configuration: HistoryConfiguration) throws -> [HistoryEntry] {
        []
    }

    func loadEntryText(at fileURL: URL) throws -> String {
        ""
    }

    func loadEntryDetail(at fileURL: URL) throws -> HistoryEntryDetail {
        HistoryEntryDetail(createdAt: nil, mode: .raw, rawTranscription: "", assistantOutput: nil)
    }

    func deleteEntry(at fileURL: URL) throws {}

    func deleteAllEntries(configuration: HistoryConfiguration) throws {}

    func storageUsage(configuration: HistoryConfiguration) throws -> HistoryUsage {
        HistoryUsage(totalBytes: 0, entryCount: 0)
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
    var stubbedImageContent: ClipboardImageContent?
    var stubbedSnapshotChangeCount = 1
    var didRestoreOriginalClipboard = false

    /// Backs the overridden `changeCount`, so tests can script clipboard arrivals
    /// for `RecordingScreenshotCollector` without a real pasteboard.
    var stubbedChangeCount = 0
    /// The attachments the next `readCollectableAttachments()` call returns;
    /// cleared after being read once, so a test sets it again per poll.
    var stubbedCollectableAttachments: [CollectedAttachment] = []
    private(set) var attachmentsOnlyWrites: [[CollectedAttachment]] = []
    private(set) var textAndAttachmentsWrites: [(text: String, attachments: [CollectedAttachment])] = []
    /// Records writes and pastes (the latter appended by a paste-service stub
    /// that's handed this clipboard) in call order, so tests can assert the
    /// two-paste sequence `ActivationStore.pasteTextThenAttachments` performs.
    private(set) var writeSequence: [String] = []

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
        ClipboardSnapshot.empty(
            changeCount: stubbedSnapshotChangeCount,
            plainText: stubbedClipboardContent,
            imageContent: stubbedImageContent
        )
    }

    override func writeTemporaryText(_ text: String) -> ClipboardWriteReceipt? {
        temporaryWriteTexts.append(text)
        writeSequence.append("text")
        stubbedSnapshotChangeCount += 1
        return ClipboardWriteReceipt(changeCount: stubbedSnapshotChangeCount)
    }

    override func restoreClipboard(from snapshot: ClipboardSnapshot, ifUnchangedSince receipt: ClipboardWriteReceipt? = nil) -> Bool {
        restoreCallCount += 1
        lastRestoredSnapshot = snapshot
        didRestoreOriginalClipboard = true
        stubbedClipboardContent = snapshot.plainText
        stubbedImageContent = snapshot.imageContent
        stubbedSnapshotChangeCount += 1
        return true
    }

    override func readFromClipboard() -> String? {
        stubbedClipboardContent
    }

    override var changeCount: Int {
        stubbedChangeCount
    }

    override func readCollectableAttachments() -> [CollectedAttachment] {
        guard !stubbedCollectableAttachments.isEmpty else { return [] }
        let result = stubbedCollectableAttachments
        stubbedCollectableAttachments = []
        return result
    }

    @discardableResult
    override func writeAttachments(_ attachments: [CollectedAttachment]) -> ClipboardWriteReceipt? {
        attachmentsOnlyWrites.append(attachments)
        writeSequence.append("attachments")
        stubbedSnapshotChangeCount += 1
        return ClipboardWriteReceipt(changeCount: stubbedSnapshotChangeCount)
    }

    @discardableResult
    override func writeTextAndAttachments(text: String, attachments: [CollectedAttachment]) -> ClipboardWriteReceipt? {
        textAndAttachmentsWrites.append((text: text, attachments: attachments))
        writeSequence.append("textAndAttachments")
        stubbedSnapshotChangeCount += 1
        return ClipboardWriteReceipt(changeCount: stubbedSnapshotChangeCount)
    }

    func clearWriteCount() {
        writeCount = 0
        lastWrittenText = nil
        temporaryWriteTexts = []
        restoreCallCount = 0
        lastRestoredSnapshot = nil
        didRestoreOriginalClipboard = false
        stubbedImageContent = nil
    }

    func simulateClipboardChange(to text: String?) {
        stubbedClipboardContent = text
        stubbedSnapshotChangeCount += 1
    }

    /// Called by `SequenceRecordingPasteService` so a dispatched paste shows up
    /// in `writeSequence` alongside the clipboard writes it's interleaved with.
    func recordPaste() {
        writeSequence.append("paste")
    }
}

/// A `PasteServicing` stub that logs each dispatched paste into the mock
/// clipboard's `writeSequence`, so tests can assert the exact interleaving of
/// writes and pastes performed by `ActivationStore.pasteTextThenAttachments`.
final class SequenceRecordingPasteService: PasteServicing {
    private let clipboard: ActivationStoreMockClipboard
    private let outcome: PasteOutcome
    private(set) var pasteCount = 0

    init(clipboard: ActivationStoreMockClipboard, outcome: PasteOutcome = .pasted) {
        self.clipboard = clipboard
        self.outcome = outcome
    }

    func pasteCurrentClipboard() -> PasteOutcome {
        pasteCount += 1
        clipboard.recordPaste()
        return outcome
    }

    func copySelectedTextToClipboard() -> PostEventOutcome {
        .unavailable
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

final class FixedWhisperSamplesAccumulator: AudioBufferAccumulator {
    private let fixedSamples: [Float]

    init(samples: [Float]) {
        self.fixedSamples = samples
        super.init()
    }

    override func convertToWhisperFormat() throws -> [Float] {
        fixedSamples
    }
}

final class ResetHookTracker {
    var callCount = 0
}

actor CapturingWhisperTranscriber: WhisperTranscribing {
    private let resultText: String
    private var lastSeenSamples: [Float]?

    init(resultText: String) {
        self.resultText = resultText
    }

    func transcribe(samples: [Float]) async throws -> String {
        lastSeenSamples = samples
        return resultText
    }

    func capturedSamples() -> [Float]? {
        lastSeenSamples
    }
}

final class MockRewriter: Rewriting, @unchecked Sendable {
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
    private(set) var lastGenerateImageCount = 0
    private(set) var generateImageCounts: [Int] = []
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
        try await generate(prompt: prompt, systemPrompt: systemPrompt, images: [])
    }
    func generate(
        prompt: String,
        systemPrompt: String,
        images: [UserInput.Image]
    ) async throws -> String {
        generateCallCount += 1
        lastCalledOverload = .generateOverload
        lastGeneratePrompt = prompt
        lastGenerateSystemPrompt = systemPrompt
        lastGenerateImageCount = images.count
        generateImageCounts.append(images.count)
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

final class DelayedRewriter: Rewriting, @unchecked Sendable {
    private let delayNanoseconds: UInt64
    private let result: MockRewriter.MockResult
    private let timingLock = NSLock()
    private var _lastCompletionUptimeNanoseconds: UInt64?

    var lastCompletionUptimeNanoseconds: UInt64? {
        timingLock.lock()
        defer { timingLock.unlock() }
        return _lastCompletionUptimeNanoseconds
    }

    init(delayNanoseconds: UInt64, result: MockRewriter.MockResult) {
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
        try await generate(prompt: prompt, systemPrompt: systemPrompt, images: [])
    }

    func generate(
        prompt: String,
        systemPrompt: String,
        images _: [UserInput.Image]
    ) async throws -> String {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let output = try complete()
        timingLock.lock()
        _lastCompletionUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        timingLock.unlock()
        return output
    }
}

private actor NoContextRouter: AssistantContextRouting {
    func route(
        request _: String,
        availableSources: ExternalTextSourceContext
    ) async throws -> AssistantContextRoutingDecision {
        AssistantContextRoutingDecision(
            matchedSources: [],
            decisionSource: availableSources.hasAvailableSource ? .modelClassifier : .noAvailableContext
        )
    }
}

private actor ScriptedContextRouter: AssistantContextRouting {
    private let modes: [AssistantContextTargetMode]

    init(modes: [AssistantContextTargetMode]) {
        self.modes = modes
    }

    func route(
        request _: String,
        availableSources _: ExternalTextSourceContext
    ) async throws -> AssistantContextRoutingDecision {
        AssistantContextRoutingDecision(
            matchedSources: modes.map { AssistantContextMatchedSource(targetMode: $0) },
            decisionSource: .modelClassifier
        )
    }
}

final class StubCopyOnlyPasteService: PasteServicing {
    private(set) var pasteCount = 0

    func pasteCurrentClipboard() -> PasteOutcome {
        pasteCount += 1
        return .copiedOnly
    }

    func copySelectedTextToClipboard() -> PostEventOutcome {
        .unavailable
    }
}

final class StubSuccessfulPasteService: PasteServicing {
    private(set) var pasteCount = 0

    func pasteCurrentClipboard() -> PasteOutcome {
        pasteCount += 1
        return .pasted
    }

    func copySelectedTextToClipboard() -> PostEventOutcome {
        .unavailable
    }
}

enum StubSelectionCopyResult {
    case unavailable
    case dispatched(String?)
}

final class StubSelectionAwarePasteService: PasteServicing {
    private let clipboard: ActivationStoreMockClipboard
    private let pasteOutcome: PasteOutcome
    private var queuedCopyResults: [StubSelectionCopyResult]

    private(set) var pasteCount = 0
    private(set) var selectionCopyCount = 0

    init(
        clipboard: ActivationStoreMockClipboard,
        queuedCopyResults: [StubSelectionCopyResult],
        pasteOutcome: PasteOutcome = .copiedOnly
    ) {
        self.clipboard = clipboard
        self.queuedCopyResults = queuedCopyResults
        self.pasteOutcome = pasteOutcome
    }

    func pasteCurrentClipboard() -> PasteOutcome {
        pasteCount += 1
        return pasteOutcome
    }

    func copySelectedTextToClipboard() -> PostEventOutcome {
        selectionCopyCount += 1
        guard !queuedCopyResults.isEmpty else {
            return .unavailable
        }

        switch queuedCopyResults.removeFirst() {
        case .unavailable:
            return .unavailable
        case .dispatched(let text):
            clipboard.simulateClipboardChange(to: text)
            return .dispatched
        }
    }
}


// MARK: - Attachment collection (wave 3b)

extension ActivationStoreTests {
    /// Distinct raw bytes per `seed`, standing in for a collected screenshot —
    /// the mock clipboard hands these back verbatim from
    /// `readCollectableAttachments()`, so they don't need to be real image data
    /// for these tests.
    private func makeDistinctImageData(_ seed: UInt8) -> Data {
        Data([0xAA, 0xBB, seed])
    }

    /// A distinct fake file URL standing in for a Finder-copied file. These
    /// tests drive `ActivationStore` through the mock clipboard's stubbed
    /// `readCollectableAttachments()`, so the URL never needs to resolve to a
    /// real file on disk.
    private func makeDistinctFileURL(_ seed: Int, extension ext: String = "pdf") -> URL {
        URL(fileURLWithPath: "/tmp/ActivationStoreTests-attachment-\(seed).\(ext)")
    }

    /// Builds a `RecordingScreenshotCollector` wired to `clipboard` with a tiny
    /// real poll interval, so tests can drive collection by mutating the mock's
    /// `stubbedChangeCount` / `stubbedCollectableAttachments` and then polling
    /// for the effect via `waitUntil`, instead of waiting out the collector's
    /// real 250ms default.
    private func makeFastCollector(
        clipboard: ActivationStoreMockClipboard,
        maxCount: Int = 20
    ) -> RecordingScreenshotCollector {
        RecordingScreenshotCollector(
            clipboard: clipboard,
            sleeper: SystemSleeper(),
            pollInterval: 0.01,
            maxCount: maxCount
        )
    }

    func test_preExistingClipboardImage_isNeverCollected() async throws {
        let clipboard = ActivationStoreMockClipboard()
        clipboard.stubbedChangeCount = 7
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(1))]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        await settle()

        // The baseline was taken at the clipboard's already-elevated change
        // count, so the image that was already there is never "new".
        XCTAssertEqual(store.sessionScreenshotCount, 0)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertTrue(store.lastSessionAttachments.isEmpty)
    }

    func test_screenshotCollection_baselineIsReadAfterInitialSelectedCaptureCompletes() async throws {
        let clipboard = ActivationStoreMockClipboard()
        // A change count bump that happens during the initial Cmd+C capture
        // window (before collection's baseline is read) must be folded into
        // that baseline rather than ever being treated as a new screenshot.
        clipboard.stubbedChangeCount = 10
        let pasteStub = StubSelectionAwarePasteService(
            clipboard: clipboard,
            queuedCopyResults: [.dispatched("selected text")]
        )
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            pasteService: pasteStub,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()

        // Give the initial selected-text capture — and the screenshot
        // collection start that awaits it — time to finish.
        await settle()
        await settle()

        XCTAssertEqual(pasteStub.selectionCopyCount, 1)
        XCTAssertEqual(store.sessionScreenshotCount, 0)

        // A genuinely new copy after collection has started is picked up.
        clipboard.stubbedChangeCount = 11
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(2))]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollect)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
    }

    func test_passthroughWithoutAttachments_behavesUnchanged() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: mockClipboard
        )

        store.arm()
        store.finish()

        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertTrue(mockClipboard.attachmentsOnlyWrites.isEmpty)
        XCTAssertTrue(mockClipboard.textAndAttachmentsWrites.isEmpty)
        XCTAssertEqual(mockClipboard.lastWrittenText, "hello world")
    }

    func test_passthroughWithTwoImagesAndAutoPaste_pastesTextThenAttachmentsInOrder() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = true
        let clipboard = ActivationStoreMockClipboard()
        let pasteStub = SequenceRecordingPasteService(clipboard: clipboard)
        let image1 = makeDistinctImageData(3)
        let image2 = makeDistinctImageData(4)
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            pasteService: pasteStub,
            preferences: preferences,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        // Post-event permission is granted, so screenshot collection waits on
        // the initial selected-text capture (which resolves near-instantly
        // here, since the stub reports the copy as unavailable) before
        // reading its baseline — give that a moment to finish before scripting
        // clipboard arrivals, or they'd be folded into the baseline instead.
        await settle()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image1)]
        let didCollectFirst = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollectFirst)

        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(image2)]
        let didCollectSecond = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }
        XCTAssertTrue(didCollectSecond)

        store.finish()
        // The text-then-attachments delivery sleeps ~400ms between pastes and
        // ~500ms before the (skipped, since restore-after-paste is off by
        // default here) clipboard restore, so give this a longer budget than
        // the default 2s used elsewhere.
        let didSucceed = try await waitForSuccess(of: store, timeoutNanoseconds: 4_000_000_000)
        XCTAssertTrue(didSucceed)

        XCTAssertEqual(clipboard.temporaryWriteTexts, ["hello world"])
        XCTAssertEqual(clipboard.attachmentsOnlyWrites.count, 1)
        XCTAssertEqual(clipboard.attachmentsOnlyWrites.first, [.image(image1), .image(image2)])
        XCTAssertEqual(pasteStub.pasteCount, 2)
        XCTAssertEqual(clipboard.writeSequence, ["text", "paste", "attachments", "paste"])
        if case .success(_, let pasted, let rewritten, _, _) = store.state {
            XCTAssertTrue(pasted)
            XCTAssertFalse(rewritten)
        } else {
            XCTFail("Expected .success state")
        }
    }

    func test_passthroughWithTwoImagesCopyOnly_writesTextAndAttachmentsWithoutPasting() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let pasteStub = StubSuccessfulPasteService()
        let image1 = makeDistinctImageData(5)
        let image2 = makeDistinctImageData(6)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            pasteService: pasteStub,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image1)]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }

        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(image2)]
        let didCollectSecond = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }
        XCTAssertTrue(didCollectSecond)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        XCTAssertEqual(clipboard.textAndAttachmentsWrites.count, 1)
        XCTAssertEqual(clipboard.textAndAttachmentsWrites.first?.text, "hello world")
        XCTAssertEqual(clipboard.textAndAttachmentsWrites.first?.attachments, [.image(image1), .image(image2)])
        XCTAssertTrue(clipboard.attachmentsOnlyWrites.isEmpty)
        XCTAssertEqual(pasteStub.pasteCount, 0)
    }

    func test_assistantModeWithImages_doesNotPasteOrRouteAttachmentsButSavesHistory() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let mockRewriter = MockRewriter(result: .success("Professional rewrite"))
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(7)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("Buddy rewrite this professionally")
            ),
            localRewriter: mockRewriter,
            historyCaptureService: historyCaptureService,
            clipboard: clipboard,
            preferences: preferences,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image)]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollect)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        XCTAssertTrue(clipboard.attachmentsOnlyWrites.isEmpty)
        XCTAssertTrue(clipboard.textAndAttachmentsWrites.isEmpty)
        XCTAssertEqual(mockRewriter.lastGenerateImageCount, 0)

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { historyCaptureService.savedContents.count == 1 }
        }
        XCTAssertTrue(didPersist)
        XCTAssertEqual(historyCaptureService.savedContents.first?.screenshots, [image])
        XCTAssertEqual(historyCaptureService.savedContents.first?.assistantOutput, "Professional rewrite")
    }

    func test_rewriteFailureWithImages_savesHistoryWithTranscriptAndScreenshots() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(18)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("Buddy rewrite this professionally")
            ),
            localRewriter: MockRewriter(result: .failure(RewriteError.generationFailed)),
            historyCaptureService: historyCaptureService,
            clipboard: clipboard,
            preferences: preferences,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image)]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollect)

        store.finish()
        let didFail = try await waitForFailure(
            of: store,
            reason: .modelError("Rewrite failed: Rewrite generation failed.")
        )
        XCTAssertTrue(didFail)

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { historyCaptureService.savedContents.count == 1 }
        }
        XCTAssertTrue(didPersist)
        XCTAssertEqual(
            historyCaptureService.savedContents.first?.rawTranscription,
            "Buddy rewrite this professionally"
        )
        XCTAssertEqual(historyCaptureService.savedContents.first?.screenshots, [image])
        XCTAssertEqual(store.lastSessionAttachments, [.image(image)])
    }

    func test_noSpeechFailureWithImages_savesHistoryEntryWithScreenshots() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(8)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("")),
            historyCaptureService: historyCaptureService,
            clipboard: clipboard,
            preferences: preferences,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image)]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollect)

        store.finish()
        let didFail = try await waitForFailure(of: store, reason: .noSpeechDetected)
        XCTAssertTrue(didFail)

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { historyCaptureService.savedContents.count == 1 }
        }
        XCTAssertTrue(didPersist)
        XCTAssertEqual(historyCaptureService.savedContents.first?.screenshots, [image])
        XCTAssertEqual(historyCaptureService.savedContents.first?.rawTranscription, "")
        XCTAssertEqual(store.lastSessionAttachments, [.image(image)])
    }

    func test_noSpeechFailureWithoutImages_savesNothing() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("")),
            historyCaptureService: historyCaptureService,
            preferences: preferences
        )

        store.arm()
        store.finish()

        let didFail = try await waitForFailure(of: store, reason: .noSpeechDetected)
        XCTAssertTrue(didFail)

        await settle()
        XCTAssertTrue(historyCaptureService.savedContents.isEmpty)
    }

    func test_historyReceivesImageDataAndAttachedFilePaths() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(21)
        let fileURL = makeDistinctFileURL(1)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            historyCaptureService: historyCaptureService,
            clipboard: clipboard,
            preferences: preferences,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image), .file(fileURL)]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }
        XCTAssertTrue(didCollect)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { historyCaptureService.savedContents.count == 1 }
        }
        XCTAssertTrue(didPersist)
        XCTAssertEqual(historyCaptureService.savedContents.first?.screenshots, [image])
        XCTAssertEqual(historyCaptureService.savedContents.first?.attachedFilePaths, [fileURL.path])
        XCTAssertEqual(store.lastSessionAttachments, [.image(image), .file(fileURL)])
    }

    func test_sessionAttachmentsIncludeFiles_trueOnlyOnceANonImageFileIsCollected() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(22)
        let fileURL = makeDistinctFileURL(2)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image)]
        let didCollectImage = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollectImage)
        XCTAssertFalse(store.sessionAttachmentsIncludeFiles)

        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.file(fileURL)]
        let didCollectFile = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionAttachmentsIncludeFiles }
        }
        XCTAssertTrue(didCollectFile)
        XCTAssertEqual(store.sessionScreenshotCount, 2)

        store.finish()
        _ = try await waitForSuccess(of: store)

        // A fresh recording resets the flag.
        store.arm()
        XCTAssertFalse(store.sessionAttachmentsIncludeFiles)
    }

    func test_cancelWithImages_savesHistoryAndSetsLastSessionAttachments() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(9)
        let store = makeStore(
            permissionsAuthorized: true,
            historyCaptureService: historyCaptureService,
            clipboard: clipboard,
            preferences: preferences,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image)]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollect)

        store.cancelCurrentSession()

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.lastSessionAttachments, [.image(image)])

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { historyCaptureService.savedContents.count == 1 }
        }
        XCTAssertTrue(didPersist)
        XCTAssertEqual(historyCaptureService.savedContents.first?.screenshots, [image])
    }

    func test_saveScreenshotsToHistoryOff_omitsScreenshotsFromHistoryButKeepsLastSession() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        preferences.saveScreenshotsToHistory = false
        let historyCaptureService = StubHistoryCaptureService()
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(10)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            historyCaptureService: historyCaptureService,
            clipboard: clipboard,
            preferences: preferences,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image)]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollect)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { historyCaptureService.savedContents.count == 1 }
        }
        XCTAssertTrue(didPersist)
        XCTAssertEqual(historyCaptureService.savedContents.first?.screenshots, [])
        XCTAssertEqual(store.lastSessionAttachments, [.image(image)])
    }

    func test_collectScreenshotsWhileRecordingOff_neverStartsCollector() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.collectScreenshotsWhileRecording = false
        let clipboard = ActivationStoreMockClipboard()
        let collector = makeFastCollector(clipboard: clipboard)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            preferences: preferences,
            screenshotCollector: collector
        )

        store.arm()
        XCTAssertFalse(collector.isRunning)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(11))]
        await settle()
        XCTAssertEqual(store.sessionScreenshotCount, 0)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertTrue(store.lastSessionAttachments.isEmpty)
    }

    func test_restartCurrentSession_keepsScreenshotsAndCount() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let collector = makeFastCollector(clipboard: clipboard)
        let store = makeStore(
            permissionsAuthorized: true,
            clipboard: clipboard,
            screenshotCollector: collector
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(12))]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollect)

        store.restartCurrentSession()

        XCTAssertEqual(store.state, .recording)
        XCTAssertEqual(store.sessionScreenshotCount, 1)
        XCTAssertTrue(collector.isRunning)

        // An attachment collected after the restart still adds to the same count.
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(13))]
        let didCollectSecond = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }
        XCTAssertTrue(didCollectSecond)
    }

    func test_restartDuringPendingInitialCapture_stillStartsCollectionAfterCaptureResolves() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let pasteStub = StubSelectionAwarePasteService(
            clipboard: clipboard,
            queuedCopyResults: [.dispatched("selected text")]
        )
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            clipboard: clipboard,
            pasteService: pasteStub,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        // Restart back-to-back with arm(), with no `await` in between, so the
        // initial selected-text capture task (and the screenshot-collection
        // start awaiting it) hasn't had a chance to run at all yet — the
        // collector is still not running when restart lands.
        store.restartCurrentSession()

        XCTAssertEqual(store.state, .recording)

        // Let the pending capture resolve (under the new session) and
        // collection start.
        await settle()
        await settle()

        let image = makeDistinctImageData(20)
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image)]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollect)
    }

    func test_pillPublishedState_countFullDuplicateAndResetOnNewRecording() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let collector = makeFastCollector(clipboard: clipboard, maxCount: 2)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            screenshotCollector: collector
        )

        store.arm()
        let image1 = makeDistinctImageData(14)
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image1)]
        let didCollectFirst = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollectFirst)

        // A duplicate copy of the same image shakes the pill but doesn't count.
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(image1)]
        let didDuplicate = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.screenshotDuplicateTick == 1 }
        }
        XCTAssertTrue(didDuplicate)
        XCTAssertEqual(store.sessionScreenshotCount, 1)

        // A second distinct image reaches the (small, injected) cap.
        clipboard.stubbedChangeCount = 3
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(15))]
        let didCollectSecond = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }
        XCTAssertTrue(didCollectSecond)
        XCTAssertFalse(store.sessionScreenshotsFull)

        // A third, distinct image is past the cap.
        clipboard.stubbedChangeCount = 4
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(16))]
        let didHitCap = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotsFull }
        }
        XCTAssertTrue(didHitCap)
        XCTAssertEqual(store.sessionScreenshotCount, 2)

        store.finish()
        _ = try await waitForSuccess(of: store)

        // A fresh recording resets all pill state.
        store.arm()
        XCTAssertEqual(store.sessionScreenshotCount, 0)
        XCTAssertFalse(store.sessionScreenshotsFull)
    }

    func test_copyLastSessionAttachments_writesAttachments() async throws {
        let clipboard = ActivationStoreMockClipboard()

        let emptyStore = makeStore(permissionsAuthorized: true, clipboard: clipboard)
        emptyStore.copyLastSessionAttachments()
        XCTAssertTrue(clipboard.attachmentsOnlyWrites.isEmpty)

        let image = makeDistinctImageData(17)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image)]
        let didCollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didCollect)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.lastSessionAttachments, [.image(image)])

        let writesBeforeCopy = clipboard.attachmentsOnlyWrites.count
        store.copyLastSessionAttachments()
        XCTAssertEqual(clipboard.attachmentsOnlyWrites.count, writesBeforeCopy + 1)
        XCTAssertEqual(clipboard.attachmentsOnlyWrites.last, [.image(image)])
    }
}

// MARK: - Badge clearing (wave A)

extension ActivationStoreTests {
    func test_removeLastCollectedAttachment_whileRecording_dropsNewestAndReCopyingReAddsIt() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let image1 = makeDistinctImageData(30)
        let image2 = makeDistinctImageData(31)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image1)]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(image2)]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }

        store.removeLastCollectedAttachment()
        XCTAssertEqual(store.sessionScreenshotCount, 1)

        // Its dedupe key was forgotten, so copying it again re-adds it.
        clipboard.stubbedChangeCount = 3
        clipboard.stubbedCollectableAttachments = [.image(image2)]
        let didRecollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }
        XCTAssertTrue(didRecollect)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.lastSessionAttachments, [.image(image1), .image(image2)])
    }

    func test_clearCollectedAttachments_whileRecording_resetsFlagsAndAllowsReCollection() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(32)
        let fileURL = makeDistinctFileURL(30)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image), .file(fileURL)]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }
        XCTAssertTrue(store.sessionAttachmentsIncludeFiles)

        store.clearCollectedAttachments()
        XCTAssertEqual(store.sessionScreenshotCount, 0)
        XCTAssertFalse(store.sessionAttachmentsIncludeFiles)
        XCTAssertEqual(store.state, .recording)

        // Both dedupe keys were forgotten, so re-copying either is collected again.
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.file(fileURL)]
        let didRecollect = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        XCTAssertTrue(didRecollect)
        XCTAssertTrue(store.sessionAttachmentsIncludeFiles)

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)
        XCTAssertEqual(store.lastSessionAttachments, [.file(fileURL)])
    }

    func test_removeLastCollectedAttachment_resetsFullFlagWhenCountDropsBelowCap() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let collector = makeFastCollector(clipboard: clipboard, maxCount: 2)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            screenshotCollector: collector
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(33))]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(34))]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }
        clipboard.stubbedChangeCount = 3
        clipboard.stubbedCollectableAttachments = [.image(makeDistinctImageData(35))]
        let didHitCap = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotsFull }
        }
        XCTAssertTrue(didHitCap)

        store.removeLastCollectedAttachment()
        XCTAssertEqual(store.sessionScreenshotCount, 1)
        XCTAssertFalse(store.sessionScreenshotsFull)
    }

    func test_removeLastCollectedAttachment_whileProcessing_dropsNewestFromDeliveryBeforePasteHappens() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(36)
        let fileURL = makeDistinctFileURL(31)
        let transcriber = GatedWhisperTranscriber()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            historyCaptureService: historyCaptureService,
            clipboard: clipboard,
            preferences: preferences,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image), .file(fileURL)]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }
        XCTAssertTrue(store.sessionAttachmentsIncludeFiles)

        store.finish()
        // `finish()` stops the collector and freezes `sessionAttachments`
        // before the async pipeline runs — waiting for the gated transcriber
        // to actually be entered guarantees the pipeline has reached
        // `.processing` and is now reading from that frozen array, not the
        // (already-stopped) collector.
        await transcriber.waitUntilStarted()
        XCTAssertEqual(store.state, .processing)

        // Drop the newest (the file) while the pipeline is still parked on
        // transcription — before any delivery/paste has happened.
        store.removeLastCollectedAttachment()
        XCTAssertEqual(store.sessionScreenshotCount, 1)
        XCTAssertFalse(store.sessionAttachmentsIncludeFiles)

        await transcriber.release(with: "hello world")
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        // Only the surviving image reaches the clipboard, history, and
        // `lastSessionAttachments` — the dropped file never does.
        XCTAssertEqual(clipboard.textAndAttachmentsWrites.count, 1)
        XCTAssertEqual(clipboard.textAndAttachmentsWrites.first?.attachments, [.image(image)])
        XCTAssertEqual(store.lastSessionAttachments, [.image(image)])

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { historyCaptureService.savedContents.count == 1 }
        }
        XCTAssertTrue(didPersist)
        XCTAssertEqual(historyCaptureService.savedContents.first?.screenshots, [image])
        XCTAssertEqual(historyCaptureService.savedContents.first?.attachedFilePaths, [])
    }

    func test_clearCollectedAttachments_whileProcessing_deliversTextOnlyAndSavesNoScreenshots() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.historyEnabled = true
        preferences.historyFolderPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationStoreTests.History")
            .appendingPathComponent(UUID().uuidString)
            .path
        let historyCaptureService = StubHistoryCaptureService()
        let clipboard = ActivationStoreMockClipboard()
        let image1 = makeDistinctImageData(37)
        let image2 = makeDistinctImageData(38)
        let transcriber = GatedWhisperTranscriber()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            historyCaptureService: historyCaptureService,
            clipboard: clipboard,
            preferences: preferences,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image1)]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(image2)]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 2 }
        }

        store.finish()
        await transcriber.waitUntilStarted()
        XCTAssertEqual(store.state, .processing)

        store.clearCollectedAttachments()
        XCTAssertEqual(store.sessionScreenshotCount, 0)
        XCTAssertFalse(store.sessionAttachmentsIncludeFiles)
        XCTAssertFalse(store.sessionScreenshotsFull)

        await transcriber.release(with: "hello world")
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        // No attachment-carrying write of any kind — a plain text-only
        // delivery, as if nothing had ever been collected.
        XCTAssertTrue(clipboard.textAndAttachmentsWrites.isEmpty)
        XCTAssertTrue(clipboard.attachmentsOnlyWrites.isEmpty)
        XCTAssertEqual(clipboard.lastWrittenText, "hello world")

        // Nothing carries over to `lastSessionAttachments` — a fully cleared
        // session leaves it untouched (still empty, for this fresh store).
        XCTAssertTrue(store.lastSessionAttachments.isEmpty)

        let didPersist = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { historyCaptureService.savedContents.count == 1 }
        }
        XCTAssertTrue(didPersist)
        XCTAssertTrue(historyCaptureService.savedContents.first?.screenshots.isEmpty ?? false)
        XCTAssertTrue(historyCaptureService.savedContents.first?.attachedFilePaths.isEmpty ?? false)
        XCTAssertEqual(historyCaptureService.savedContents.first?.rawTranscription, "hello world")
    }

    func test_removeLastAndClearCollectedAttachments_areNoOpsOutsideRecordingAndProcessing() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let image = makeDistinctImageData(39)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("hello world")),
            clipboard: clipboard,
            screenshotCollector: makeFastCollector(clipboard: clipboard)
        )

        // Idle: nothing to act on, but must not crash or otherwise misbehave.
        XCTAssertEqual(store.state, .idle)
        store.removeLastCollectedAttachment()
        store.clearCollectedAttachments()
        XCTAssertEqual(store.sessionScreenshotCount, 0)

        store.arm()
        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(image)]
        _ = try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            await MainActor.run { store.sessionScreenshotCount == 1 }
        }

        store.finish()
        let didSucceed = try await waitForSuccess(of: store)
        XCTAssertTrue(didSucceed)

        // Success: the delivered attachment is already committed to
        // `currentSuccessAttachments`/history — clearing now must not touch it.
        let successAttachmentsBefore = store.lastSessionAttachments
        store.removeLastCollectedAttachment()
        store.clearCollectedAttachments()
        XCTAssertEqual(store.lastSessionAttachments, successAttachmentsBefore)
        XCTAssertEqual(store.sessionScreenshotCount, 1)

        let writesBeforeNoOp = clipboard.textAndAttachmentsWrites.count
        store.copyCurrentSuccessResult()
        XCTAssertEqual(clipboard.textAndAttachmentsWrites.count, writesBeforeNoOp + 1)
        XCTAssertEqual(clipboard.textAndAttachmentsWrites.last?.attachments, [.image(image)])
    }
}
