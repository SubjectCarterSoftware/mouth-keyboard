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

    func testStopTransitionsToIdle() {
        let store = makeStore(permissionsAuthorized: true)
        store.arm()

        store.stop()

        XCTAssertEqual(store.state, .idle)
    }

    // arm() is blocked when permissions are not yet authorized — readiness
    // state alone is not the gate; the individual permission items are checked.
    func testArmDoesNotTransitionWhenPermissionsNotAuthorized() {
        let store = makeStore(permissionsAuthorized: false)

        store.arm()

        XCTAssertEqual(store.state, .idle)
    }

    // arm() succeeds when all permissions are authorized, even if the user has
    // not yet pressed "Finish Setup" (hasCompletedInitialSetup == false).
    // The setup-finalize step is an onboarding UX gate, not a runtime gate.
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
        if case .success(let text, _, _, _) = store.state {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testCancelDuringRecordingReturnsToIdleWithoutClipboardWrite() {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            clipboard: mockClipboard
        )
        store.arm()

        store.cancelCurrentSession()

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.recoveryFeedback, .canceled)
        XCTAssertNil(mockClipboard.lastWrittenText)
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

    func test_arm_while_recording_calls_finish() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success("toggled"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: ActivationStoreMockClipboard()
        )
        store.arm() // -> .recording
        XCTAssertEqual(store.state, .recording)

        store.arm() // second arm while recording should call finish()

        XCTAssertEqual(store.state, .processing)
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
        var timestamps = [0.0, 0.1, 0.2, 0.7].makeIterator()
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
        XCTAssertTrue(hotkeyService.handleKeyDown()) // finish

        try await Task.sleep(nanoseconds: 200_000_000)

        if case .success(let text, _, _, _) = store.state {
            XCTAssertEqual(text, "ready")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }

        XCTAssertTrue(hotkeyService.handleKeyDown()) // stale repeat should be ignored
        if case .success(let text, _, _, _) = store.state {
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

        if case .success(let text, _, _, _) = store.state {
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
            result: .success("zeus Please schedule a meeting for Friday convert to email")
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
        if case .success(_, _, let converted, _) = store.state {
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
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
        if case .success(_, _, let converted, _) = store.state {
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    // MARK: - UserIntentStore override + custom intent routing tests (11-03)

    /// Built-in mode with a store override: finalizeSession must resolve override's systemPrompt
    /// and call rewrite(body:instructions:) with that prompt, not the default mode prompt.
    func test_builtin_override_calls_instructions_overload() async throws {
        let overridePrompt = "My custom email instructions for testing"
        let emailOverride = UserIntentEntry(
            id: ConvertMode.email.rawValue,
            modeName: "Email",
            systemPrompt: overridePrompt,
            phrasePatterns: [],
            keywordSignal: "",
            isBuiltIn: true
        )
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let intentStore = UserIntentStore(storeURL: tmpURL)
        try await intentStore.addOrUpdateBuiltInOverride(emailOverride)

        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("zeus Please schedule a meeting for Friday convert to email")
        )
        let mockRewriter = MockLLMRewriter(result: .success("Rewritten email output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            userIntentStore: intentStore,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .instructionsOverload,
                       "Built-in override should use rewrite(body:instructions:) not rewrite(body:mode:)")
        XCTAssertEqual(mockRewriter.lastInstructions, overridePrompt,
                       "instructions should be the override's systemPrompt")
        XCTAssertEqual(mockClipboard.lastWrittenText, "Rewritten email output")
    }

    /// Custom mode match (customIntentID non-nil): finalizeSession calls rewrite(body:instructions:)
    /// with the custom entry's systemPrompt.
    func test_custom_mode_calls_instructions_overload() async throws {
        let customPrompt = "Format this as a JIRA ticket with summary and description"
        let customEntry = UserIntentEntry(
            id: UUID().uuidString,
            modeName: "JIRA Ticket",
            systemPrompt: customPrompt,
            phrasePatterns: ["convert to jira", "jira ticket"],
            keywordSignal: "jira",
            isBuiltIn: false
        )
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let intentStore = UserIntentStore(storeURL: tmpURL)
        try await intentStore.addOrUpdateCustomMode(customEntry)

        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("zeus We need to fix the login bug convert to jira")
        )
        let mockRewriter = MockLLMRewriter(result: .success("JIRA: Fix login bug"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            userIntentStore: intentStore,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .instructionsOverload,
                       "Custom mode should use rewrite(body:instructions:)")
        XCTAssertEqual(mockRewriter.lastInstructions, customPrompt,
                       "instructions should be the custom entry's systemPrompt")
        XCTAssertEqual(mockClipboard.lastWrittenText, "JIRA: Fix login bug")
    }

    /// Built-in mode with NO store override: finalizeSession still calls rewrite(body:mode:)
    /// (existing path unchanged — no regression for standard users).
    func test_builtin_no_override_uses_mode_overload() async throws {
        // Empty store — no overrides
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let intentStore = UserIntentStore(storeURL: tmpURL)

        let mockTranscriber = ActivationStoreMockTranscriber(
            result: .success("zeus Please schedule a meeting convert to email")
        )
        let mockRewriter = MockLLMRewriter(result: .success("Email output"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            userIntentStore: intentStore,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRewriter.lastCalledOverload, .modeOverload,
                       "Built-in with no override should use rewrite(body:mode:)")
        XCTAssertEqual(mockRewriter.lastMode, .email)
    }

    /// Passthrough intent: store lookup never called; raw transcript to clipboard.
    /// (This is the existing passthrough path test but with an explicit userIntentStore to confirm isolation.)
    func test_passthrough_with_intent_store_still_bypasses_llm() async throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let intentStore = UserIntentStore(storeURL: tmpURL)

        let mockTranscriber = ActivationStoreMockTranscriber(result: .success("Hello world"))
        let mockRewriter = MockLLMRewriter(result: .success("Should never be called"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            llmRewriter: mockRewriter,
            userIntentStore: intentStore,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(mockRewriter.lastCalledOverload,
                     "Passthrough path must not call LLM rewriter at all")
        XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
        if case .success(_, _, let converted, _) = store.state {
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_trigger_preset_mutation_does_not_change_passthrough_finalize_behavior() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
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
        if case .success(_, _, let converted, _) = store.state {
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_custom_trigger_mutation_does_not_change_convert_mode_finalize_behavior() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setCustomTrigger(primary: "Helios", aliases: ["assistant helios"])
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

        XCTAssertEqual(mockRewriter.lastCalledOverload, .modeOverload)
        XCTAssertEqual(mockRewriter.lastMode, .email)
    }

    // MARK: - Phase 13 parser-gated finalize behavior (RED in 13-02 Task 1)

    func test_finalize_uses_postAlias_instruction_segment_for_conversion_body() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
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

        XCTAssertEqual(mockRewriter.lastCalledOverload, .modeOverload)
        XCTAssertEqual(mockRewriter.lastMode, .email)
        XCTAssertEqual(mockRewriter.lastBody, "send this to the team")
    }

    func test_finalize_no_trigger_alias_keeps_passthrough_behavior() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
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
        if case .success(_, _, let converted, _) = store.state {
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_short_postAlias_instruction_does_not_activate_conversion() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "convert to email weekly update atlas ok"
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
        if case .success(_, _, let converted, _) = store.state {
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_repeated_alias_mentions_use_last_name_wins_boundary() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas convert to email first draft atlas final update convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Slack output"))
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

        XCTAssertEqual(mockRewriter.lastCalledOverload, .modeOverload)
        XCTAssertEqual(mockRewriter.lastMode, .slack)
        XCTAssertEqual(mockRewriter.lastBody, "final update")
    }

    // MARK: - Phase 14 shortcut routing behavior (RED for 14-01 Task 1)

    func test_finalize_validTrigger_leadingShortcut_instruction_routesToCustomInstructionFallback() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "weekly team update atlas convert to email send this update to the team"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Custom rewrite output"))
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

        XCTAssertEqual(mockRewriter.lastCalledOverload, .instructionsOverload)
        XCTAssertEqual(mockRewriter.lastBody, "weekly team update")
        XCTAssertEqual(mockRewriter.lastInstructions, "convert to email send this update to the team")
        XCTAssertEqual(mockClipboard.lastWrittenText, "Custom rewrite output")
        if case .success(let text, _, let converted, _) = store.state {
            XCTAssertEqual(text, "Custom rewrite output")
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_validTrigger_ambiguousBuiltInInstruction_routesToCustomInstructionFallback() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "status update for engineering atlas convert to email or convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Ambiguous custom rewrite output"))
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

        XCTAssertEqual(mockRewriter.lastCalledOverload, .instructionsOverload)
        XCTAssertEqual(mockRewriter.lastBody, "status update for engineering")
        XCTAssertEqual(mockRewriter.lastInstructions, "convert to email or convert to slack")
        XCTAssertEqual(mockClipboard.lastWrittenText, "Ambiguous custom rewrite output")
        if case .success(let text, _, let converted, _) = store.state {
            XCTAssertEqual(text, "Ambiguous custom rewrite output")
            XCTAssertTrue(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_validTrigger_clearTrailingShortcut_usesBuiltInModePipeline() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
        try await Task.sleep(nanoseconds: 80_000_000)

        let transcript = "atlas please send this update to the team convert to slack"
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success(transcript))
        let mockRewriter = MockLLMRewriter(result: .success("Slack output"))
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

        XCTAssertEqual(mockRewriter.lastCalledOverload, .modeOverload)
        XCTAssertEqual(mockRewriter.lastMode, .slack)
        XCTAssertEqual(mockRewriter.lastBody, "please send this update to the team")
    }

    func test_finalize_validTrigger_customFallback_preserves350WordGate() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
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
        XCTAssertNil(mockRewriter.lastCalledOverload)
    }

    func test_finalize_validTrigger_builtInShortcut_llmFailure_silentlyFallsBackToRawClipboard() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
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

        XCTAssertEqual(mockRewriter.lastCalledOverload, MockLLMRewriter.CalledOverload.modeOverload)
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        if case .success(let text, _, let converted, _) = store.state {
            XCTAssertEqual(text, transcript)
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func test_finalize_validTrigger_customFallback_llmFailure_silentlyFallsBackToRawClipboard() async throws {
        let preferences = makePreferencesWithTriggerStore()
        preferences.setTriggerPreset(.atlas)
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

        XCTAssertEqual(mockRewriter.lastCalledOverload, MockLLMRewriter.CalledOverload.instructionsOverload)
        XCTAssertEqual(mockRewriter.lastBody, "weekly update on launch metrics")
        XCTAssertEqual(mockRewriter.lastInstructions, "make this casual and concise")
        XCTAssertEqual(mockClipboard.lastWrittenText, transcript)
        if case .success(let text, _, let converted, _) = store.state {
            XCTAssertEqual(text, transcript)
            XCTAssertFalse(converted)
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    // MARK: - Helpers

    private func makeStore(
        permissionsAuthorized: Bool,
        transcriber: (any WhisperTranscribing)? = nil,
        llmRewriter: (any LLMRewriting)? = nil,
        userIntentStore: UserIntentStore? = nil,
        clipboard: ClipboardService? = nil,
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
            readinessProvider: StubReadinessProvider(permissionsAuthorized: permissionsAuthorized),
            whisperService: transcriber ?? ActivationStoreMockTranscriber(result: .success("")),
            llmRewriteService: llmRewriter ?? MockLLMRewriter(result: .failure(LLMRewriteError.cancelled)),
            userIntentStore: userIntentStore ?? UserIntentStore(storeURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")),
            clipboardService: clipboard ?? ActivationStoreMockClipboard(),
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
}

// MARK: - Stubs / Mocks

@MainActor
private struct StubReadinessProvider: ReadinessProviding {
    let permissionsAuthorized: Bool

    var snapshot: ReadinessSnapshot {
        let status: PermissionGrantState = permissionsAuthorized ? .authorized : .denied
        let permissions = PermissionKind.allCases.map {
            PermissionChecklistItem(kind: $0, status: status, message: "", isRequired: true)
        }
        // state is derived from permission statuses; supply a plausible value.
        let state: ReadinessState = permissionsAuthorized ? .ready : .blocked
        return ReadinessSnapshot(
            state: state,
            title: "",
            message: "",
            primaryActionTitle: "",
            permissions: permissions
        )
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

/// Mock clipboard service — subclasses ClipboardService (must be non-final) for test interception
class ActivationStoreMockClipboard: ClipboardService {
    private(set) var lastWrittenText: String?
    private(set) var writeCount = 0

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

    func clearWriteCount() {
        writeCount = 0
        lastWrittenText = nil
    }
}

/// Stub accumulator returns minimal samples to satisfy the transcription pipeline
class StubBufferAccumulator: AudioBufferAccumulator {
    override func convertToWhisperFormat() throws -> [Float] {
        return [0.0, 0.0, 0.0] // non-empty, won't throw emptyBuffers
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
    enum CalledOverload { case modeOverload; case instructionsOverload }
    private let result: MockResult
    private(set) var lastCalledOverload: CalledOverload?
    private(set) var lastBody: String?
    private(set) var lastInstructions: String?
    private(set) var lastMode: ConvertMode?
    init(result: MockResult) { self.result = result }
    func rewrite(body: String, mode: ConvertMode) async throws -> String {
        lastCalledOverload = .modeOverload
        lastBody = body
        lastMode = mode
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
    func rewrite(body: String, instructions: String) async throws -> String {
        lastCalledOverload = .instructionsOverload
        lastBody = body
        lastInstructions = instructions
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}
