---
status: awaiting_human_verify
trigger: "Investigate issue: hotkey-rearm-freeze-after-paste"
created: 2026-03-09T01:50:33Z
updated: 2026-03-09T03:00:44Z
---

## Current Focus

hypothesis: `tiny.en` made finish->success fast enough that a repeated key-down from the same hotkey press can arrive after `.success`, and the terminal-state restart change then treats that repeat as a fresh recording start.
test: Manual verification in the live app build is needed to confirm the second activation now starts a clean session after a real finish/paste cycle.
expecting: The finish hotkey should no longer cause a hidden immediate re-arm, so the next deliberate hotkey press after pasting should start recording instead of freezing or erroring.
next_action: wait for user verification against the original reproduction steps

## Symptoms

expected: After a successful finish and paste, pressing the hotkey again should immediately start a fresh recording.
actual: Recording succeeds once, clipboard output succeeds, paste succeeds, then the next hotkey press causes the app to freeze/error again.
errors: No explicit error text captured yet; behavior is described as freeze/error after the second activation attempt.
reproduction: 1. Launch the app build using tiny.en. 2. Start recording with the hotkey. 3. Press Control+V to finish. 4. Wait for clipboard write and paste the result into another app. 5. Press the hotkey again to start a new recording. 6. App errors/freeze occurs.
started: Observed after switching the bundled model to tiny.en and after the earlier terminal-state hotkey fix was confirmed.

## Eliminated

## Evidence

- timestamp: 2026-03-09T01:53:00Z
  checked: `Speech2Test/Activation/HotkeyService.swift`
  found: The global hotkey stays registered through `KeyboardShortcuts.onKeyDown(for: .activate)` and always routes the shortcut back to `ActivationStore.arm()`.
  implication: The second activation attempt should still reach the store; the failure is less likely to be simple hotkey deregistration.

- timestamp: 2026-03-09T01:53:40Z
  checked: `Speech2Test/App/AppDelegate.swift`
  found: `ActivationStore` state drives lifecycle hooks: `.recording` starts capture, `.processing` stops capture, `.success` only updates UI, and `.idle` stops capture again.
  implication: A successful first run can leave capture teardown dependent on the `.processing` transition and any later re-arm skips `.idle` entirely.

- timestamp: 2026-03-09T01:54:25Z
  checked: `Speech2Test/Activation/SpacebarInterceptor.swift`
  found: The session interceptor only traps key codes 49 and 53 (space and escape), not the global activation shortcut.
  implication: The reported `Control+V` finish/re-arm issue does not originate from the session interceptor owning the same key combination.

- timestamp: 2026-03-09T01:55:10Z
  checked: commit `9460be4` and `Speech2TestTests/ActivationStoreTests.swift`
  found: The earlier hotkey fix only changed `ActivationStore.arm()` to allow restart from terminal states and added regression coverage for long-dictation success, not the normal single-session success path.
  implication: A separate regression can still exist after a regular success flow, especially if it depends on audio-capture or app-delegate cleanup.

- timestamp: 2026-03-09T01:57:40Z
  checked: `Speech2Test/Audio/AudioCaptureService.swift` and `Speech2TestTests/AudioCaptureServiceTests.swift`
  found: `AudioCaptureService.stop()` removes the input tap, nils the engine, and existing tests confirm restart works after stop and after failure recovery.
  implication: The second-run freeze is unlikely to be a simple engine/tap restart failure in `AudioCaptureService` alone.

- timestamp: 2026-03-09T01:59:10Z
  checked: `xcodebuild test -scheme Speech2Test -project Speech2Test.xcodeproj -only-testing:Speech2TestTests/ActivationStoreTests -only-testing:Speech2TestTests/AudioCaptureServiceTests`
  found: All 36 targeted unit tests passed, including `test_arm_after_longSessionSuccess_restartsImmediatelyWithoutWaitingForAutoDismiss` and `testStopRemovesTapAndSupportsRestart`.
  implication: The reported bug does not reproduce in the isolated store/capture layers and likely depends on the real app hotkey integration or UI event timing.

- timestamp: 2026-03-09T02:12:10Z
  checked: `Speech2Test/Activation/HotkeyService.swift`, `Speech2Test/App/AppDelegate.swift`, and `Speech2TestTests/HotkeyServiceTests.swift`
  found: The app resets the activation shortcut on launch and the registered global hotkey default is `Control+V`; every hotkey key-down calls `ActivationStore.arm()` with no filtering for clipboard paste intent.
  implication: A normal paste gesture after transcription is indistinguishable from the activation shortcut at the hotkey layer.

- timestamp: 2026-03-09T02:12:45Z
  checked: `Speech2Test/Activation/ActivationStore.swift` and `Speech2Test/Activation/RecordingState.swift`
  found: `ActivationStore.arm()` explicitly accepts activation from terminal states (`.success` and `.failure`) so users can restart without waiting for auto-dismiss.
  implication: Pressing `Control+V` while success UI is still showing will immediately transition the store back to `.recording`.

- timestamp: 2026-03-09T02:13:05Z
  checked: `Speech2Test/App/AppDelegate.swift` and `Speech2Test/Shell/RecordingPillPanel.swift`
  found: App-level state observation starts audio capture on every `.recording` transition, while the pill panel is passive UI only and does not block keyboard input.
  implication: The paste-triggered re-arm would start a real capture session in the background, and the next user hotkey press would act as a finish/toggle on that unintended session rather than a clean new start.

- timestamp: 2026-03-09T02:20:50Z
  checked: `Speech2Test/Activation/HotkeyService.swift`, `Speech2TestTests/HotkeyServiceTests.swift`, and `Speech2TestTests/ActivationStoreTests.swift`
  found: A targeted repeat guard was added to suppress rapid duplicate activation deliveries, and regression tests now model the exact start -> finish -> rapid repeat -> later re-arm sequence.
  implication: Verification can now directly test the suspected hotkey-repeat failure mode instead of relying only on indirect reasoning.

- timestamp: 2026-03-09T03:00:20Z
  checked: `xcodebuild test -scheme Speech2Test -project Speech2Test.xcodeproj -only-testing:Speech2TestTests/HotkeyServiceTests -only-testing:Speech2TestTests/ActivationStoreTests -only-testing:Speech2TestTests/AudioCaptureServiceTests`
  found: All 43 targeted tests passed, including the new `testRapidRepeatedHotkeyAfterSuccessDoesNotSilentlyRearm` and the new hotkey repeat-guard unit coverage.
  implication: The fix prevents the modeled unintended post-success re-arm while preserving the normal start/finish toggle and capture restart behavior in test coverage.

## Resolution

root_cause: `tiny.en` reduced the finish-to-success latency enough that the same physical hotkey press can plausibly deliver a rapid duplicate key-down after `.success`, and the earlier terminal-state restart change then re-arms recording on that duplicate event.
fix: Added a minimum activation interval in `HotkeyService` so rapid duplicate hotkey deliveries are ignored, and added regression tests for both the repeat guard and the success-then-repeat lifecycle.
verification:
  - `xcodebuild test -scheme Speech2Test -project Speech2Test.xcodeproj -only-testing:Speech2TestTests/HotkeyServiceTests -only-testing:Speech2TestTests/ActivationStoreTests -only-testing:Speech2TestTests/AudioCaptureServiceTests`
  - New regression coverage proves rapid duplicate hotkey delivery after success is ignored, while a later hotkey press still starts a fresh recording.
files_changed:
  - Speech2Test/Activation/HotkeyService.swift
  - Speech2TestTests/HotkeyServiceTests.swift
  - Speech2TestTests/ActivationStoreTests.swift
