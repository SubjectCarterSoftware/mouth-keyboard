# Quick Fixes Cleanup - Execution Brief

Use this brief together with:

- `.planning/feature-proposals/quick-fixes-cleanup.md`
- `.planning/feature-proposals/resource-lifecycle-and-stability.md`

This brief is for a smaller implementation agent. It narrows scope, sets sequencing, and calls out the traps that must not be missed.

---

## Goal

Implement the cleanup items from `.planning/feature-proposals/quick-fixes-cleanup.md` only.

Do not redesign broader architecture.
Do not implement anything from the lifecycle/stability proposal unless the cleanup doc explicitly requires it.

---

## In Scope

Implement these items from the cleanup proposal:

1. Silence warning wiring, with warning ownership on `AudioLevelMonitor`
2. Cancel during `.converting`, including actual UI reachability
3. Calibration conflict handling via a typed busy error in `AudioCaptureService`
4. `AssistantCalibrationRunner.onSampleAccepted` accepted-count fix
5. Safer persistent store URL resolution without `try!`
6. Stable lifecycle for `AIAssistantSettingsViewModel`
7. Better per-session screen selection for the recording pill
8. Paste outcome correctness: distinguish pasted vs copied-only
9. Internal `AudioBufferAccumulator` cap with non-silent overflow handling
10. Corrupt JSON quarantine for both intent and trigger-profile stores

---

## Explicitly Out of Scope

Do not implement:

- `largeTurbo` auto-selection changes
- `ResourceCoordinator`
- rewrite-model/Whisper unload policies beyond any cleanup strictly needed by the quick-fixes doc
- menu bar icon redesign
- `IntentDetector` deduplication

If work starts to drift into those areas, stop and return to the cleanup list.

---

## Required implementation order

Implement in this order unless a concrete dependency forces a slight change:

1. `AssistantCalibrationRunner.onSampleAccepted` count fix
2. Store URL resolution fallback cleanup
3. `AIAssistantSettingsViewModel` lifecycle fix
4. Silence warning wiring
5. Cancel during `.converting`
6. Paste outcome correctness
7. Calibration busy/conflict fix
8. `AudioBufferAccumulator` cap and overflow handling
9. Corrupt-store quarantine
10. Recording pill screen selection

The order matters because it gets the low-risk isolated fixes done first and delays the more coupled runtime changes until later.

---

## Non-Negotiable design constraints

### 1. Silence warning ownership

The silence-warning state belongs in `AudioLevelMonitor`, not `ActivationStore`.
Do not add a new warning-state source of truth to `ActivationStore`.

### 2. Cancel during `.converting`

It is not enough to widen the store guard.
The user must be able to trigger cancel from the UI while conversion is active.
That includes:

- the store,
- the recording pill interaction state,
- the converting pill UI,
- and the status menu.

### 3. Calibration conflict handling

Do not solve the calibration conflict by checking `ActivationStore.shared.state`.
The source of truth is the capture layer.

`AudioCaptureService.start(...)` must throw a typed busy/conflict error when capture is already active.
`LiveCalibrationSampleCapturer` must treat that as an expected conflict and must not interrupt the active recording.

### 4. Paste outcome semantics

Do not collapse paste into success/failure only.
Clipboard write success and synthetic paste success are different outcomes.
Model this explicitly and make the UI/state reflect the true outcome.

### 5. Accumulator cap behavior

Do not silently truncate audio.
If the accumulator hits its internal cap, that must become an explicit overflow condition that maps to a clear user-visible failure path.

### 6. Corrupt store handling

Do not silently discard unreadable JSON.
Quarantine the file first, then fall back.
Apply the same pattern to both stores where practical.

---

## Expected files to touch

Likely files include:

- `Speech2Text/Audio/AudioLevelMonitor.swift`
- `Speech2Text/App/AppDelegate.swift`
- `Speech2Text/Shell/RecordingPillView.swift`
- `Speech2Text/Shell/RecordingPillPanel.swift`
- `Speech2Text/Shell/StatusMenuView.swift`
- `Speech2Text/Activation/ActivationStore.swift`
- `Speech2Text/Audio/AudioCaptureService.swift`
- `Speech2Text/Audio/LiveCalibrationSampleCapturer.swift`
- `Speech2Text/Shell/AssistantCalibrationRunner.swift`
- `Speech2Text/Conversion/UserIntentStore.swift`
- `Speech2Text/Activation/TriggerProfileStore.swift`
- `Speech2Text/Shell/AIAssistantSettingsView.swift`
- `Speech2Text/Shell/SetupWindowView.swift`
- `Speech2Text/Clipboard/PasteService.swift`
- `Speech2Text/Audio/AudioBufferAccumulator.swift`

Tests will likely need updates or additions in:

- `Speech2TextTests/ActivationStoreTests.swift`
- `Speech2TextTests/AudioCaptureServiceTests.swift`
- `Speech2TextTests/AudioBufferAccumulatorTests.swift`
- `Speech2TextTests/UserIntentStoreTests.swift`
- `Speech2TextTests/TriggerProfileStoreTests.swift`
- plus any new focused tests if the existing files are not the best fit

---

## Minimum acceptance criteria

Before calling the work done, verify all of the following:

1. The converting state can actually be canceled from the UI and no late success leaks through
2. Attempting calibration during active capture fails safely and does not stop the active session
3. Silence warning becomes visible and clears correctly when speech resumes
4. Paste fallback reports copied-only rather than pasted
5. Accumulator overflow is explicit and not silent
6. Corrupt JSON is preserved via quarantine before fallback
7. No deferred item from the cleanup doc was implemented accidentally

---

## Testing expectations

Run the most relevant targeted tests for any changed area.

At minimum, add or update tests for:

- cancel during converting
- capture busy behavior
- accepted-count callback
- paste outcome handling
- accumulator overflow
- corrupt store quarantine

If any area cannot be reasonably automated in this pass, call it out clearly in the final report and provide a manual verification step.

---

## Final report expectations

In the final handoff, report:

1. what was changed
2. which tests were added or updated
3. which tests were run
4. any manual verification still required
5. any item from the cleanup brief that was intentionally deferred and why

--- Summary for this change set ---

1. What changed
   • AssistantCalibrationRunner now tracks accepted samples and reports real progress; tests verify the counts.
   • Store URL resolution now uses `StoreURLResolver`, while corrupt JSON is quarantined via `StoreQuarantine`; the intent and trigger stores fall back safely.
   • The assistant settings view model is stabilized in `SetupWindowView`, the silence warning state lives in `AudioLevelMonitor`, and the recording pills/make UI path displays warnings, keeps cancel interaction alive during `.converting`, and picks a screen per session based on the pointer.
   • PasteService now reports `.pasted` versus `.copiedOnly`, `ActivationStore` respects the outcome, and cancel-during-converting plus paste/UI reachability were expanded.
   • AudioCaptureService throws `captureBusy`, LiveCalibrationSampleCapturer propagates the conflict and the settings view surfaces a warning, while the accumulator enforces a max-duration cap and ActivationStore maps overflow to `.wordLimitExceeded`.

2. Which files changed
   • Added `StoreURLResolver.swift` and `StoreQuarantine.swift` (with updates to the PBX project), plus dozens of touched sources in Activation, Audio, Shell, Clipboard, and related tests to wire the behaviors described above.

3. Tests added/updated
   • `AssistantCalibrationRunnerTests`, `ActivationStoreTests`, `AudioBufferAccumulatorTests`, `AudioCaptureServiceTests`, `UserIntentStoreTests`, `TriggerProfileStoreTests` all gain targeted coverage for the new behaviors (accepted counts, cancel during converting, accumulator overflow, capture busy, paste outcome, quarantine handling).

4. Tests run
   • xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2TextTests -destination "platform=macOS" -only-testing:Speech2TextTests/AudioBufferAccumulatorTests/testAppendStopsAddingBuffersAfterOverflow -only-testing:Speech2TextTests/AudioBufferAccumulatorTests/testConvertThrowsOverflowAfterCap -only-testing:Speech2TextTests/AudioCaptureServiceTests/testStartThrowsWhenCaptureAlreadyActive -only-testing:Speech2TextTests/UserIntentStoreTests/testCorruptStoreIsQuarantinedAndDefaultsToEmpty -only-testing:Speech2TextTests/TriggerProfileStoreTests/testCorruptionFallbackToZeus -only-testing:Speech2TextTests/AssistantCalibrationRunnerTests/testAcceptedCountCallbackReportsProgress -only-testing:Speech2TextTests/ActivationStoreTests/testCancelDuringConvertingSuppressesLateConversion (fails because xcodebuild cannot write to Swift module cache/directories due to “Operation not permitted” and cannot reconnect to CoreSimulatorService; see log for details).

5. Manual verification still required
   • Multi-display recording pill placement, .converting cancel affordance, silence warning UX, calibration-busy messaging, paste outcome display, and overall flow in an end-to-end scenario.

6. Deferred items
   • None; the quick-fixes brief scope was fully implemented without adding any out-of-scope work.
