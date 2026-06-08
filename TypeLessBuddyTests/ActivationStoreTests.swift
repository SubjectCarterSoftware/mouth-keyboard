import AppKit
import Combine
import MLXLMCommon
import XCTest
@testable import TypeLessBuddy

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
        if case .success(_, let pasted, let converted, _, _) = store.state {
            XCTAssertTrue(pasted)
            XCTAssertFalse(converted)
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
            llmRewriter: DelayedLLMRewriter(
                delayNanoseconds: 300_000_000,
                result: .success("Converted output")
            ),
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state == .converting }
        mockClipboard.stubbedClipboardContent = "clipboard changed during conversion"

        await waitUntil { store.state.isSuccess }

        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertEqual(pasteStub.pasteCount, 1)
        XCTAssertEqual(mockClipboard.temporaryWriteTexts, ["Converted output"])
        XCTAssertTrue(mockClipboard.didRestoreOriginalClipboard)
        XCTAssertEqual(mockClipboard.lastRestoredSnapshot?.plainText, "clipboard changed during conversion")
        if case .success(let text, let pasted, let converted, _, _) = store.state {
            XCTAssertEqual(text, "Converted output")
            XCTAssertTrue(pasted)
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state after converted auto paste")
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
            llmRewriter: MockLLMRewriter(result: .failure(LLMRewriteError.generationFailed)),
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
        if case .success(_, let pasted, let converted, _, _) = store.state {
            XCTAssertFalse(pasted)
            XCTAssertFalse(converted)
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
        XCTAssertNil(store.recoveryFeedback)
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
        XCTAssertNil(store.recoveryFeedback)
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testCancelDuringConvertingSuppressesLateConversion() async throws {
        let transcript = "team update buddy make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let preferences = makePreferencesWithTriggerStore()
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

        await waitUntil { store.state == .converting }

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
            llmRewriter: MockLLMRewriter(result: .success("Refined output")),
            clipboard: mockClipboard
        )

        store.arm()
        store.finish()

        // The converting state is held during the minimum display window; nothing
        // is written to the clipboard until success. Wait for converting rather
        // than racing a fixed real-time budget (which flakes under suite load).
        await waitUntil { store.state == .converting }
        XCTAssertNil(mockClipboard.lastWrittenText)

        await waitUntil { store.state.isSuccess }
        XCTAssertEqual(mockClipboard.lastWrittenText, "Refined output")
        if case .success(let text, _, let converted, _, _) = store.state {
            XCTAssertEqual(text, "Refined output")
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state after minimum converting display")
        }
    }

    func testDelayedRewriteDoesNotAddExtraDelayAfterMinimumConvertingDisplay() async throws {
        let transcript = "team update buddy make this concise and direct"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockClipboard = ActivationStoreMockClipboard()
        let preferences = makePreferencesWithTriggerStore()
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
        let transcript = "team update buddy make this concise and direct"
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

        await waitUntil { store.state == .converting }

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
            llmRewriter: MockLLMRewriter(result: .success("Converted output")),
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

    func test_convertedSuccess_setsDismissTiming() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.alwaysAutoPaste = false

        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("buddy make this formal")),
            llmRewriter: MockLLMRewriter(result: .success("Converted output")),
            clipboard: ActivationStoreMockClipboard(),
            preferences: preferences
        )

        store.arm()
        store.finish()
        await waitUntil { store.state.isTerminal }

        if case .success(let text, _, let converted, _, _) = store.state {
            XCTAssertEqual(text, "Converted output")
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected converted success state")
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

    func test_trigger_dictation_produces_converted_clipboard_output() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("buddy Please schedule a meeting for Friday convert to email")
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
        await waitUntil { store.state.isTerminal }
        XCTAssertEqual(mockClipboard.lastWrittenText, "Subject: Meeting Request\n\nPlease schedule...")
        XCTAssertEqual(store.lastConvertedTranscription, "Subject: Meeting Request\n\nPlease schedule...")
        if case .success(_, _, let converted, _, _) = store.state {
            XCTAssertTrue(converted)
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
        let rewriter = MockLLMRewriter(result: .success("Rewritten output"))
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: rewriter,
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
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGenerateSystemPrompt, "Custom rewrite prefix")
    }

    func test_finalize_rewrite_failure_surfaces_model_error_not_silent_success() async throws {
        let transcript = "team update buddy make this concise and direct"
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
        await waitUntil { store.state.isTerminal }

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
        await waitUntil { store.state.isTerminal }

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
        await waitUntil { store.state.isTerminal }

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
        await waitUntil { store.state.isTerminal }

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
        await waitUntil { store.state.isTerminal }

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
        await waitUntil { store.state.isTerminal }

        XCTAssertEqual(mockRewriter.lastCalledOverload, .generateOverload)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt?.hasPrefix(transcript), true)
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
        let reachedSuccess = try await waitForSuccess(of: store)

        XCTAssertTrue(reachedSuccess)
        XCTAssertEqual(mockRewriter.generateCallCount, 1)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt?.hasPrefix(transcript), true)
        XCTAssertEqual(mockClipboard.lastWrittenText, "Assistant output")
    }

    func test_finalize_triggered_assistantPromptUsesGlobal1500WordGate() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
        try await Task.sleep(nanoseconds: 80_000_000)

        let longBody = repeatedWords(1_501)
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
        let mockRewriter = MockLLMRewriter(result: .success("Slack output"))
        mockRewriter.queuedGenerateResults = [
            .success("Slack output"),
            .success("Email output"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
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
        let mockRewriter = MockLLMRewriter(result: .success("Email output"))
        mockRewriter.queuedGenerateResults = [
            .success("Email output"),
            .success("Slack output"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
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

    /// The output stored in lastConvertedTranscription must be the raw LLM
    /// output — not decorated with XML tags or prior-conversation markup.
    /// This verifies the correct value remains available for follow-up routing.
    func test_lastConvertedTranscription_isRawLLMOutput() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Atlas")
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
        await waitUntil { store.state.isTerminal }

        let stored = try XCTUnwrap(store.lastConvertedTranscription)
        XCTAssertEqual(stored, expectedOutput,
            "lastConvertedTranscription must equal the raw LLM output, not wrapped in XML")
        XCTAssertFalse(stored.contains("<"), "lastConvertedTranscription must not contain XML markup")
    }

    func test_assistantNotePhrase_savesRewrittenOutput() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let llmRewriter = MockLLMRewriter(result: .success("- first\n- second"))
        llmRewriter.queuedGenerateResults = [
            .success("- first\n- second"),
            .success("Bullet summary")
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("Buddy make a note of this turn this into bullet points")
            ),
            llmRewriter: llmRewriter,
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
        let llmRewriter = MockLLMRewriter(result: .success("Thank you for the quick reply."))
        llmRewriter.queuedGenerateResults = [
            .success("Thank you for the quick reply."),
            .success("Selected text cleanup")
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            postEventAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(
                result: .success("Buddy make a note of this make the selected text more professional")
            ),
            llmRewriter: llmRewriter,
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

    func test_manualSaveCurrentSuccessResultAsNote_savesAssistantOutputWithoutAutomaticNotePhrase() async throws {
        let preferences = makePreferencesWithConfiguredNoteDestination()
        let noteCaptureService = StubNoteCaptureService()
        let llmRewriter = MockLLMRewriter(result: .success("Here is the cleaned status update."))
        llmRewriter.queuedGenerateResults = [
            .success("Here is the cleaned status update."),
            .success("Quick status update")
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("Buddy draft a quick status update")),
            llmRewriter: llmRewriter,
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
            llmRewriter: MockLLMRewriter(result: .failure(LLMRewriteError.modelLoadFailed)),
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
            llmRewriter: MockLLMRewriter(result: .success("Professional rewrite")),
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
        llmRewriter: (any LLMRewriting)? = nil,
        whisperModelLoadState: (any WhisperModelLoadStateProviding)? = nil,
        noteCaptureService: (any NoteCapturing)? = nil,
        historyCaptureService: (any HistoryCapturing)? = nil,
        clipboard: ClipboardService? = nil,
        pasteService: (any PasteServicing)? = nil,
        bufferAccumulator: AudioBufferAccumulator? = nil,
        dateProvider: (() -> Date)? = nil,
        sleeper: (any Sleeping)? = nil,
        resetSessionMonitoring: (@MainActor () -> Void)? = nil,
        preferences: ShellPreferences? = nil
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
            llmRewriteService: llmRewriter ?? MockLLMRewriter(result: .failure(LLMRewriteError.cancelled)),
            noteCaptureService: noteCaptureService ?? StubNoteCaptureService(),
            historyCaptureService: historyCaptureService ?? StubHistoryCaptureService(),
            clipboardService: clipboard ?? ActivationStoreMockClipboard(),
            pasteService: pasteService ?? PasteService(),
            bufferAccumulator: bufferAccumulator ?? StubBufferAccumulator(),
            dateProvider: dateProvider ?? { Date() },
            sleeper: sleeper ?? SystemSleeper(),
            resetSessionMonitoring: resetSessionMonitoring ?? {}
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
        preferences.assistantNoteMode = mode

        switch mode {
        case .newFile:
            preferences.assistantNoteFolderPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("TypeLessBuddyNotes")
                .appendingPathComponent(UUID().uuidString)
                .path
        case .appendToFile:
            preferences.assistantNoteAppendFilePath = FileManager.default.temporaryDirectory
                .appendingPathComponent("TypeLessBuddyNotes")
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
    func test_externalTextSourceClassifier_explicitSelectedTextReturnsSingleDeterministicMatch() {
        let context = ExternalTextSourceContext(
            selectedTextAvailable: true,
            clipboardTextAvailable: true,
            lastTranscriptionAvailable: true
        )

        let decision = ExternalTextSourceClassifier.classify(
            message: "Buddy, make what's selected more concise and professional",
            availableSources: context
        )

        XCTAssertEqual(decision.targetMode, .selectedText)
        XCTAssertEqual(decision.decisionSource, .explicitFastPath)
        XCTAssertEqual(decision.promptLabel, "what's selected")
        XCTAssertEqual(
            decision.matchedSources,
            [
                AssistantContextMatchedSource(
                    targetMode: .selectedText,
                    promptLabel: "what's selected"
                )
            ]
        )
    }

    func test_externalTextSourceClassifier_explicitClipboardReturnsSingleDeterministicMatch() {
        let context = ExternalTextSourceContext(
            selectedTextAvailable: true,
            clipboardTextAvailable: true,
            lastTranscriptionAvailable: true
        )

        let decision = ExternalTextSourceClassifier.classify(
            message: "Buddy, turn what I copied into a polished Slack update",
            availableSources: context
        )

        XCTAssertEqual(decision.targetMode, .clipboard)
        XCTAssertEqual(decision.decisionSource, .explicitFastPath)
        XCTAssertEqual(decision.promptLabel, "what i copied")
        XCTAssertEqual(
            decision.matchedSources,
            [
                AssistantContextMatchedSource(
                    targetMode: .clipboard,
                    promptLabel: "what i copied"
                )
            ]
        )
    }

    func test_externalTextSourceClassifier_explicitLastTranscriptionReturnsSingleDeterministicMatch() {
        let context = ExternalTextSourceContext(
            selectedTextAvailable: true,
            clipboardTextAvailable: true,
            lastTranscriptionAvailable: true
        )

        let decision = ExternalTextSourceClassifier.classify(
            message: "Buddy, clean up my last transcription and make it easier to read",
            availableSources: context
        )

        XCTAssertEqual(decision.targetMode, .lastTranscription)
        XCTAssertEqual(decision.decisionSource, .explicitFastPath)
        XCTAssertEqual(decision.promptLabel, "my last transcription")
        XCTAssertEqual(
            decision.matchedSources,
            [
                AssistantContextMatchedSource(
                    targetMode: .lastTranscription,
                    promptLabel: "my last transcription"
                )
            ]
        )
    }

    func test_externalTextSourceClassifier_multipleExplicitSourcesReturnsAllMatchedSourcesInStableOrder() {
        let context = ExternalTextSourceContext(
            selectedTextAvailable: true,
            clipboardTextAvailable: true,
            lastTranscriptionAvailable: true
        )

        let decision = ExternalTextSourceClassifier.classify(
            message: "Buddy, compare what's selected with what I copied and my last transcription",
            availableSources: context
        )

        XCTAssertEqual(decision.targetMode, .none)
        XCTAssertEqual(decision.promptLabel, nil)
        XCTAssertEqual(decision.decisionSource, .explicitFastPath)
        XCTAssertEqual(
            decision.matchedSources,
            [
                AssistantContextMatchedSource(
                    targetMode: .lastTranscription,
                    promptLabel: "my last transcription"
                ),
                AssistantContextMatchedSource(
                    targetMode: .clipboard,
                    promptLabel: "what i copied"
                ),
                AssistantContextMatchedSource(
                    targetMode: .selectedText,
                    promptLabel: "what's selected"
                ),
            ]
        )
    }

    func test_externalTextSourceClassifier_vagueRequestReturnsNoDeterministicMatch() {
        let context = ExternalTextSourceContext(
            selectedTextAvailable: true,
            clipboardTextAvailable: true,
            lastTranscriptionAvailable: true
        )

        let decision = ExternalTextSourceClassifier.classify(
            message: "Buddy, make this more professional",
            availableSources: context
        )

        XCTAssertEqual(decision.targetMode, .none)
        XCTAssertEqual(decision.decisionSource, .noDeterministicMatch)
        XCTAssertTrue(decision.matchedSources.isEmpty)
    }

    func test_externalTextSourceClassifier_noAvailableContextReturnsNoAvailableContext() {
        let context = ExternalTextSourceContext(
            selectedTextAvailable: false,
            clipboardTextAvailable: false,
            lastTranscriptionAvailable: false
        )

        let decision = ExternalTextSourceClassifier.classify(
            message: "Buddy, make this more professional",
            availableSources: context
        )

        XCTAssertEqual(decision.targetMode, .none)
        XCTAssertEqual(decision.decisionSource, .noAvailableContext)
        XCTAssertTrue(decision.matchedSources.isEmpty)
    }

    func test_route_noneTarget_producesDirectAssistantPrompt() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, write me a thank-you note for the team dinner",
            selectedText: "Some selected text",
            clipboardText: "Some clipboard text",
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .none,
                decisionSource: .noDeterministicMatch
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
                decisionSource: .explicitFastPath,
                promptLabel: "what's selected"
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, make the selected context provided below more professional

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
            Rewrite it to sound more professional and polished.
            Keep the original meaning and preserve concrete facts, names, numbers, dates, deadlines, owners, and next steps unless the user asks to change them.
            Do not invent new information, describe the change, or return the source text unchanged.
            Return only the transformed text.

            selected context provided below:
            "hey thanks for the food it was rly good"
            """
        )
        XCTAssertFalse(body.contains("clipboard"))
    }

    func test_route_clipboardTarget_wrapsUserRequestAndSourceContext() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, format what I copied",
            selectedText: nil,
            clipboardText: "Meeting notes from tuesday: action items - follow up with design team, update roadmap",
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .clipboard,
                decisionSource: .explicitFastPath,
                promptLabel: "what i copied"
            )
        )

        XCTAssertTrue(body.contains("User request:\nBuddy, format the copied context provided below"))
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
                decisionSource: .explicitFastPath,
                promptLabel: "my last transcription"
            )
        )

        XCTAssertTrue(body.contains("User request:\nBuddy, can you fix the transcript context provided below"))
        XCTAssertTrue(body.contains("Use the transcript context provided below as the exact text to transform."))
        XCTAssertTrue(body.contains("Apply the user request directly to that text itself."))
        XCTAssertTrue(body.contains("Preserve concrete facts unless the user asks to change them."))
        XCTAssertTrue(body.contains("Do not describe the change or return the source text unchanged."))
        XCTAssertTrue(body.contains("Return only the transformed text."))
        XCTAssertTrue(body.contains("transcript context provided below:\n\"i went too the store and buyed some groceries\""))
        XCTAssertFalse(body.contains("selected text"))
        XCTAssertFalse(body.contains("clipboard"))
    }

    func test_route_selectedTextLanguageCleanup_usesDedicatedInstructionBlock() {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: "Buddy, check the grammar in what's selected",
            selectedText: "i went too the store and buyed some groceries",
            clipboardText: nil,
            routingDecision: AssistantContextRoutingDecision(
                targetMode: .selectedText,
                decisionSource: .explicitFastPath,
                promptLabel: "what's selected"
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, check the grammar in the selected context provided below

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
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
                decisionSource: .explicitFastPath,
                promptLabel: "what's selected"
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, check the grammar in the selected context provided below and make it more professional

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
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
                decisionSource: .explicitFastPath,
                promptLabel: "my last transcription"
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, make the transcript context provided below nicer and shorter

            Use the transcript context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
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
                decisionSource: .explicitFastPath,
                promptLabel: "what's selected"
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, turn the selected context provided below into bullets and then make it one sentence

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
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
                decisionSource: .explicitFastPath,
                promptLabel: "what's selected"
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, make the selected context provided below one sentence and then turn it into three bullets

            Use the selected context provided below as the exact text to transform.
            Apply the user request directly to that text itself.
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
                        targetMode: .lastTranscription,
                        promptLabel: "my last transcription"
                    ),
                    AssistantContextMatchedSource(
                        targetMode: .clipboard,
                        promptLabel: "what i copied"
                    ),
                    AssistantContextMatchedSource(
                        targetMode: .selectedText,
                        promptLabel: "what's selected"
                    ),
                ],
                decisionSource: .explicitFastPath
            )
        )

        XCTAssertEqual(
            body,
            """
            User request:
            Buddy, compare the selected context provided below with the copied context provided below and the transcript context provided below

            Use the provided sections below as the source text for the user request above.
            Apply the request directly to that source material.
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
        let mockRewriter = MockLLMRewriter(result: .success("Much more polite version"))
        mockRewriter.queuedGenerateResults = [
            .success("Much more polite version"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
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
            finalPrompt.contains(
                "User request:\nbuddy make the transcript context provided below sound much more polite"
            )
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
        let mockRewriter = MockLLMRewriter(result: .success("Combined output"))
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
            llmRewriter: mockRewriter,
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
            buddy combine the transcript context provided below with the copied context provided below and the selected context provided below

            Use the provided sections below as the source text for the user request above.
            Apply the request directly to that source material.
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
        let mockRewriter = MockLLMRewriter(result: .success("Retry output"))
        mockRewriter.queuedGenerateResults = [
            .success("Initial converted output"),
            .success("Retry output"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
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
        let mockRewriter = MockLLMRewriter(result: .success("Retry output"))
        mockRewriter.queuedGenerateResults = [
            .success("Retry output"),
        ]
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: transcriber,
            llmRewriter: mockRewriter,
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
        let mockRewriter = MockLLMRewriter(result: .success("Clipboard rewrite"))
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
            llmRewriter: mockRewriter,
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
        XCTAssertTrue(finalPrompt.contains("User request:\nbuddy use the copied context provided below to improve this"))
        XCTAssertTrue(finalPrompt.contains("Use the copied context provided below as the exact text to transform."))
        XCTAssertTrue(finalPrompt.contains("Apply the user request directly to that text itself."))
        XCTAssertTrue(finalPrompt.contains("Preserve concrete facts unless the user asks to change them."))
        XCTAssertTrue(finalPrompt.contains("Do not describe the change or return the source text unchanged."))
        XCTAssertTrue(finalPrompt.contains("Return only the transformed text."))
        XCTAssertTrue(finalPrompt.contains("copied context provided below:\n\"clipboard context\""))
        XCTAssertFalse(finalPrompt.contains("selected context provided below:"))
    }

    func test_externalTextRouter_oversizedSelectedTextIsExcludedFromRouting() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Buddy")
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "buddy rewrite what's selected"
        let transcriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Direct assistant output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let oversizedSelection = repeatedWords(5_000, token: "selected")
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
            llmRewriter: mockRewriter,
            clipboard: mockClipboard,
            pasteService: pasteStub,
            preferences: preferences
        )

        store.arm()
        store.finish()
        let succeeded = try await waitForSuccess(of: store)
        XCTAssertTrue(succeeded)

        XCTAssertEqual(mockRewriter.generateCallCount, 1)
        XCTAssertEqual(mockRewriter.lastGeneratePrompt, transcript)
        XCTAssertFalse(mockRewriter.lastGeneratePrompt?.contains("selected context provided below:") ?? false)
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
                        targetMode: .selectedText,
                        promptLabel: "what's selected"
                    )
                ],
                expectedDecisionSource: .explicitFastPath,
                expectedPromptBody: """
                User request:
                Buddy, make the selected context provided below sound more professional

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
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
                        targetMode: .clipboard,
                        promptLabel: "what i copied"
                    )
                ],
                expectedDecisionSource: .explicitFastPath,
                expectedPromptBody: """
                User request:
                Buddy, turn the copied context provided below into a tighter Slack update

                Use the copied context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
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
                        targetMode: .lastTranscription,
                        promptLabel: "my last transcription"
                    )
                ],
                expectedDecisionSource: .explicitFastPath,
                expectedPromptBody: """
                User request:
                Buddy, fix the transcript context provided below and make it polite

                Use the transcript context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
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
                        targetMode: .selectedText,
                        promptLabel: "what's selected"
                    )
                ],
                expectedDecisionSource: .explicitFastPath,
                expectedPromptBody: """
                User request:
                Buddy, check the grammar in the selected context provided below

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
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
                        targetMode: .selectedText,
                        promptLabel: "what's selected"
                    )
                ],
                expectedDecisionSource: .explicitFastPath,
                expectedPromptBody: """
                User request:
                Buddy, check the grammar in the selected context provided below and make it more professional

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
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
                        targetMode: .lastTranscription,
                        promptLabel: "my last transcription"
                    )
                ],
                expectedDecisionSource: .explicitFastPath,
                expectedPromptBody: """
                User request:
                Buddy, make the transcript context provided below nicer and shorter

                Use the transcript context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
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
                        targetMode: .selectedText,
                        promptLabel: "what's selected"
                    )
                ],
                expectedDecisionSource: .explicitFastPath,
                expectedPromptBody: """
                User request:
                Buddy, fix wording in the selected context provided below and turn it into three bullets

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
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
                        targetMode: .selectedText,
                        promptLabel: "what's selected"
                    )
                ],
                expectedDecisionSource: .explicitFastPath,
                expectedPromptBody: """
                User request:
                Buddy, turn the selected context provided below into bullets and then make it one sentence

                Use the selected context provided below as the exact text to transform.
                Apply the user request directly to that text itself.
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
                        targetMode: .lastTranscription,
                        promptLabel: "my last transcription"
                    ),
                    AssistantContextMatchedSource(
                        targetMode: .clipboard,
                        promptLabel: "what i copied"
                    ),
                    AssistantContextMatchedSource(
                        targetMode: .selectedText,
                        promptLabel: "what's selected"
                    ),
                ],
                expectedDecisionSource: .explicitFastPath,
                expectedPromptBody: """
                User request:
                Buddy, compare the selected context provided below with the copied context provided below and the transcript context provided below

                Use the provided sections below as the source text for the user request above.
                Apply the request directly to that source material.
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
                expectedDecisionSource: .noDeterministicMatch,
                expectedPromptBody: "Buddy, make this cleaner and easier to read"
            ),
            ExternalTextRoutingScenario(
                name: "Standalone drafting request stays direct",
                dictatedContent: "Buddy, draft a thank-you note for the team dinner",
                selectedText: "selected text should not be injected",
                clipboardText: "clipboard text should not be injected",
                lastTranscription: "last transcription should not be injected",
                expectedMatchedSources: [],
                expectedDecisionSource: .noDeterministicMatch,
                expectedPromptBody: "Buddy, draft a thank-you note for the team dinner"
            ),
            ExternalTextRoutingScenario(
                name: "Retry phrasing no longer reuses context",
                dictatedContent: "Buddy, try that again",
                selectedText: nil,
                clipboardText: "clipboard text should stay unused",
                lastTranscription: "previous dictated text should stay unused",
                expectedMatchedSources: [],
                expectedDecisionSource: .noDeterministicMatch,
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

        let service = LLMRewriteService(tier: .standard2B)
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

            let decision = ExternalTextSourceClassifier.classify(
                message: scenario.dictatedContent,
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
                systemPrompt: LLMRewriteService.resolveAssistantSystemPrompt(assistantName: "Buddy")
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

        let service = LLMRewriteService(tier: .standard2B)
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
        let decision = ExternalTextSourceClassifier.classify(
            message: dictatedRequest,
            availableSources: context
        )
        let productionPrompt = ExternalTextPromptBuilder.buildBody(
            dictatedContent: dictatedRequest,
            selectedText: nil,
            clipboardText: nil,
            lastTranscription: priorTranscript,
            routingDecision: decision
        )
        let productionSystemPrompt = LLMRewriteService.resolveAssistantSystemPrompt(
            assistantName: assistantName
        )

        let strongerRewriteSystemPrompt = LLMRewriteService.resolveAssistantSystemPrompt(
            promptTemplate: """
            \(LLMRewriteService.defaultAssistantSystemPromptTemplate)
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
        let availableSources = ExternalTextSourceContext(
            selectedText: scenario.selectedText,
            clipboardText: scenario.clipboardText,
            lastTranscription: scenario.lastTranscription
        )

        let decision = ExternalTextSourceClassifier.classify(
            message: scenario.dictatedContent,
            availableSources: availableSources
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
                "  \(matchedSource.targetMode.rawValue): \(matchedSource.promptLabel ?? "<nil>")"
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
            "  \(matchedSource.targetMode.rawValue): \(matchedSource.promptLabel ?? "<nil>")"
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
            "  \(matchedSource.targetMode.rawValue): \(matchedSource.promptLabel ?? "<nil>")"
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

private actor RecordingRealModelRewriter: LLMRewriting {
    private let base: any LLMRewriting
    private var entries: [RealModelRoutingEvalTraceEntry] = []

    init(base: any LLMRewriting) {
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
