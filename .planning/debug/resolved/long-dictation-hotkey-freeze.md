---
status: resolved
trigger: "Investigate issue: long-dictation-hotkey-freeze"
created: 2026-03-09T00:00:00Z
updated: 2026-03-09T01:04:52Z
---

## Current Focus

hypothesis: Confirmed and fixed. Immediate hotkey reuse after terminal feedback now re-arms the store instead of waiting for auto-dismiss.
test: Human verification confirmed the real stuck-instance cleanup and hotkey re-entry path now work after successful long dictation.
expecting: Resolved; both automated coverage and real workflow checks now match the intended behavior.
next_action: archive the resolved debug session and commit the verified fix

## Symptoms

expected: After a successful long-dictation session completes, pressing the hotkey again should start a fresh recording session normally.
actual: The app worked once, then when the hotkey was pressed again it froze and locked up.
errors: No explicit error message reported yet.
reproduction: Launch the debug app, complete one long-dictation flow successfully, then press the hotkey again to start or toggle the next session; app freezes.
started: Started during Phase 5 plan 03 human verification on March 8, 2026, after the recent long-dictation reliability changes from plans 05-01 through 05-03.

## Eliminated

## Evidence

- timestamp: 2026-03-09T00:08:00Z
  checked: Speech2Test/Activation/HotkeyService.swift
  found: The global shortcut handler only logs and calls ActivationStore.arm() on the main actor.
  implication: The freeze is unlikely to originate in hotkey registration logic itself; the bug is likely downstream in activation/session handling.

- timestamp: 2026-03-09T00:09:00Z
  checked: Speech2Test/Activation/ActivationStore.swift and Speech2Test/App/AppDelegate.swift
  found: Long dictation remains in `.recording`, switches to `.processing` only on explicit finish, and teardown/reset is split across ActivationStore invalidation and AppDelegate audio-capture stop callbacks.
  implication: A second-session freeze can be caused by stale session state or a blocking cleanup path between `.processing`/`.success` and the next `.recording`.

- timestamp: 2026-03-09T00:16:00Z
  checked: Speech2Test/Audio/AudioCaptureService.swift, Speech2Test/Audio/AudioLevelMonitor.swift, Speech2TestTests/AudioCaptureServiceTests.swift, and Speech2TestTests/LongDictationFlowTests.swift
  found: AudioCaptureService already has coverage for stop-then-restart, and long-dictation tests cover segmentation/finalization but not a brand-new session after long-session success.
  implication: The current blind spot is the successful long-dictation completion -> next activation path the user reported.

- timestamp: 2026-03-09T00:24:00Z
  checked: Focused test runs for Speech2TestTests/LongDictationFlowTests, Speech2TestTests/ActivationStoreTests, and Speech2TestTests/AudioCaptureServiceTests
  found: All three focused suites passed; long-dictation orchestration, store-level cancellation/finalization, and audio stop/restart are each green in isolation.
  implication: The freeze is either in an untested second-session lifecycle gap or in app wiring that current unit tests do not cover.

- timestamp: 2026-03-09T00:33:00Z
  checked: Speech2TestTests/ActivationStoreTests.swift regression test_arm_after_longSessionSuccess_restartsImmediatelyWithoutWaitingForAutoDismiss
  found: The new regression failed because calling arm() from `.success(text: "first second")` left the store in `.success` instead of transitioning to `.recording`.
  implication: The root cause is that terminal success feedback blocks the hotkey until the delayed auto-dismiss finishes, which matches the reported post-completion lockup.

- timestamp: 2026-03-09T00:38:00Z
  checked: Speech2Test/Activation/ActivationStore.swift plus focused reruns of the new regression, Speech2TestTests/ActivationStoreTests, and Speech2TestTests/LongDictationFlowTests
  found: Allowing `arm()` from terminal states made the new regression pass, and the full ActivationStore and long-dictation flow suites remained green.
  implication: The fix is targeted to terminal-state reactivation and does not regress the existing processing/long-session behavior under automated coverage.

- timestamp: 2026-03-09T01:04:52Z
  checked: Human verification checkpoint response
  found: The user re-tested the stuck-instance cleanup and hotkey re-entry path in the real app and confirmed the issue is fixed.
  implication: The fix holds in the real workflow that originally reproduced the freeze, so the session can be archived and closed.

## Resolution

root_cause: ActivationStore.arm() only accepted `.idle` and `.recording`, so a hotkey press during terminal `.success` / `.failure` feedback after long dictation was ignored until auto-dismiss completed.
fix: Updated ActivationStore.arm() to allow reactivation from terminal success/failure feedback while continuing to block activation during `.processing`, and added a regression covering long-session success followed by immediate reactivation.
verification: Passed xcodebuild for the new targeted regression, the full ActivationStoreTests suite, and the full LongDictationFlowTests suite after the fix. The user then re-tested the stuck-instance cleanup and hotkey re-entry path in the real app and confirmed it works.
files_changed:
  - Speech2Test/Activation/ActivationStore.swift
  - Speech2TestTests/ActivationStoreTests.swift
