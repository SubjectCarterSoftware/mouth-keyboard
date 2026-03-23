# Proposal: Quick Fixes & Cleanup (Revised)

**Date:** 2026-03-22
**Scope:** 10 isolated, low-risk fixes plus 1 explicitly deferred product decision
**Estimated effort:** Small overall - most fixes are 1-4 files, with focused unit-test follow-up

---

## Why this document was revised

This revision incorporates code review of the current implementation. The goal is to make this document safe for a smaller implementation agent to execute without having to rediscover design traps.

Key changes from the earlier draft:

- Removed ambiguous items that are really product decisions, not bugs.
- Corrected fixes that were too narrow to solve the real issue.
- Added concrete implementation notes where the obvious patch would still leave the bug in place.
- Added testing guidance so behavior regressions are harder to miss.

Unless otherwise noted, each item below is intended to be independently shippable.

---

## 1. Silence warning should be owned by `AudioLevelMonitor`, not `ActivationStore`

**Where:** `Speech2Text/App/AppDelegate.swift`, `Speech2Text/Audio/AudioLevelMonitor.swift`, `Speech2Text/Shell/RecordingPillView.swift`, `Speech2Text/Shell/RecordingPillPanel.swift`

**The problem:** `AudioLevelMonitor.onSilenceWarning` fires after ~45 seconds of silence, but `AppDelegate` only logs the event. `RecordingPillView` already has a `silenceWarningActive` visual state, so the app has a built warning UI that never becomes active. Users get auto-stopped at ~60 seconds with no visible lead-in.

**Important design note:** The earlier proposal suggested storing this flag on `ActivationStore`. That would work, but it is the wrong ownership boundary. Silence timing, reset behavior, and threshold recovery already live inside `AudioLevelMonitor`, so the warning flag should live there too.

**Suggested fix:**

1. Add `@Published private(set) var silenceWarningActive = false` to `AudioLevelMonitor`.
2. In `updateSilenceTracking(normalized:)`, set `silenceWarningActive = true` when the 45-second warning threshold is crossed.
3. Clear `silenceWarningActive` whenever audio rises back above the silence threshold.
4. Clear `silenceWarningActive` in `reset()`.
5. Remove the dead `NSLog(...)`-only behavior in `AppDelegate` and let the pill observe the published state.
6. Pass `levelMonitor.silenceWarningActive` into `RecordingPillView`, or let the view read it directly from the observed monitor.

**Expected result:** The pill turns orange after the long-silence warning begins and returns to normal if speech resumes before timeout.

**Validation / tests:**

- Add or extend an `AudioLevelMonitor` test covering warning activation and reset on resumed audio.
- Manually verify: stay silent long enough to trigger the warning, then speak again and confirm the orange warning clears.

---

## 2. Cancel during `.converting` must be reachable from the UI, not just legal in the state machine

**Where:** `Speech2Text/Activation/ActivationStore.swift`, `Speech2Text/Shell/RecordingPillPanel.swift`, `Speech2Text/Shell/RecordingPillView.swift`, `Speech2Text/Shell/StatusMenuView.swift`

**The problem:** `cancelCurrentSession()` only allows `.recording` and `.processing`. That blocks cancellation while the LLM rewrite is running. The problem is not only the guard:

- `RecordingPillPanel` disables pointer interaction outside `.recording`.
- `RecordingPillView` has no cancel affordance in the `.converting` UI.
- `StatusMenuView` only enables cancel for `.recording` and `.processing`.

So even if the store guard is widened, the user still cannot actually trigger cancel from the UI.

**Suggested fix:**

1. Extend `ActivationStore.cancelCurrentSession()` to allow `.converting`.
2. Keep the pill panel interactive during `.converting`.
3. Add a visible cancel button to the converting pill UI.
4. Extend `StatusMenuView.canCancelSession` to include `.converting`.
5. Update any user-facing copy so converting is treated as an in-progress state that can still be canceled.
6. Preserve the current cancellation semantics: invalidate the active session, cancel the task, publish `.canceled`, and return to `.idle`.

**Expected result:** A hung or slow rewrite can be canceled from both the pill and the menu without quitting the app.

**Validation / tests:**

- Add an `ActivationStore` test that starts conversion, cancels during `.converting`, and verifies no late success is published.
- Manually verify that the cancel affordance remains clickable while the converting animation is visible.

---

## 3. Calibration must fail loudly when audio capture is already busy

**Where:** `Speech2Text/Audio/LiveCalibrationSampleCapturer.swift`, `Speech2Text/Audio/AudioCaptureService.swift`, `Speech2Text/Shell/AIAssistantSettingsView.swift`

**The problem:** `LiveCalibrationSampleCapturer.captureSample()` calls `AudioCaptureService.start(...)` without knowing whether a normal dictation session already owns the shared capture service. Today `AudioCaptureService.start(...)` silently returns when a tap is already installed. That creates two bugs:

1. Calibration records nothing and eventually returns `nil` with no explanation.
2. The calibration path still calls `stop()`, which can tear down the active dictation session's audio capture.

This is more severe than a harmless no-op. A UI-only disable is not sufficient protection.

**Suggested fix:**

1. Add a typed error such as `AudioCaptureError.captureBusy` (name flexible) to `AudioCaptureService`.
2. Replace `guard !hasInstalledTap else { return }` in `start(...)` with that error.
3. Update `LiveCalibrationSampleCapturer` to treat this as an expected conflict, not a generic failure.
4. Surface the conflict in the settings UI with inline feedback and/or by disabling the custom-name recording action while capture is busy.
5. Do **not** solve this by making `LiveCalibrationSampleCapturer` read `ActivationStore.shared.state`. The capture service itself is the source of truth for whether the mic is already in use.

**Expected result:** Attempting calibration during an active recording reports a clear conflict and does not interrupt the live session.

**Validation / tests:**

- Add an `AudioCaptureService` test that verifies `start(...)` throws the new busy error when capture is already active.
- Add a calibration-path test to confirm the active recording is not stopped as a side effect.
- Manual verify: start dictation, open settings, try custom-name recording, confirm the app refuses safely and leaves dictation intact.

---

## 4. `AssistantCalibrationRunner.onSampleAccepted` always reports `0`

**Where:** `Speech2Text/Shell/AssistantCalibrationRunner.swift`

**The problem:** `runSession()` always invokes `onSampleAccepted?(0)`. The callback contract says it should report progress for accepted samples, but the implementation never tracks count and the private `countAccepted()` helper is dead code.

**Suggested fix:**

1. Add a local `acceptedCount` variable inside `runSession()`.
2. Increment it each time `session.recordSample(...)` returns `.accepted`.
3. Pass the current count to `onSampleAccepted`.
4. Delete the dead `countAccepted()` helper.

**Expected result:** Any UI progress indicator receives meaningful values instead of `0` every time.

**Validation / tests:**

- Add focused tests for accepted sample progression (for example: first accepted sample reports `1`, second reports `2`, completion is still signaled by `onComplete`).

---

## 5. Persistent store URL resolution should not use `try!`

**Where:** `Speech2Text/Conversion/UserIntentStore.swift`, `Speech2Text/Activation/TriggerProfileStore.swift`

**The problem:** Both stores use `try!` when resolving the Application Support directory. That is usually fine on a normal machine, but it turns a recoverable filesystem failure into an app crash.

**Suggested fix:**

1. Replace the inline `try!` logic with a small shared helper that:
   - tries to resolve/create Application Support,
   - logs if resolution fails,
   - falls back to `FileManager.default.temporaryDirectory`.
2. Keep filenames unchanged so existing persisted data is still discovered when Application Support is available.
3. Prefer this local fallback strategy in this batch rather than converting all call sites to throwing APIs.

**Expected result:** The app falls back safely instead of crashing during store initialization.

**Validation / tests:**

- Existing temp-path persistence tests already cover the stores' ability to operate outside Application Support.
- If practical, add a helper-level test for fallback behavior; otherwise document the fallback path with a diagnostic log.

---

## 6. `AIAssistantSettingsViewModel` needs a stable lifecycle

**Where:** `Speech2Text/Shell/AIAssistantSettingsView.swift`, `Speech2Text/Shell/SetupWindowView.swift`

**The problem:** `AIAssistantTileView.body` constructs a new `AIAssistantSettingsViewModel` on every render pass. Each instance subscribes to `preferences.$activeTriggerProfile` in `init`, then is immediately discarded. The tile happens to render correctly because it only reads synchronous properties, but the subscription churn is wasted work. On top of that, the sheet creates a separate view model instance instead of sharing the same one.

**Suggested fix:**

1. Create one stable `@StateObject` view model in `SetupWindowView`.
2. Pass that single instance into both:
   - `AIAssistantTileView`
   - `AIAssistantSettingsView`
3. Update `AIAssistantTileView` so it observes the injected view model instead of constructing one inside `body`.
4. Keep `ShellPreferences` bindings only where the UI genuinely needs them.

**Expected result:** One long-lived view model drives both the tile and the sheet, and Combine subscriptions are no longer recreated on every render.

**Validation / tests:**

- Existing `AIAssistantSettingsViewModel` tests should continue to pass unchanged.
- Manual verify: changing assistant profile updates both tile and sheet correctly.

---

## 7. Recording pill should choose a screen per session using pointer location, not `NSApp.keyWindow`

**Where:** `Speech2Text/Shell/RecordingPillPanel.swift`

**The problem:** `updatePosition()` uses `NSScreen.main`, which is usually the menu-bar display, not necessarily the display where the user is working. The earlier suggestion to use `NSApp.keyWindow?.screen` is not reliable here because this is a menu bar app; the app often has no meaningful key window during normal dictation. The pill position is also only recalculated at a few specific times, so screen choice needs to be tied to session start, not just generic layout updates.

**Suggested fix:**

1. Add a helper that chooses the screen containing `NSEvent.mouseLocation` when the pill first becomes visible for a new session.
2. Cache that chosen screen (or its visible frame) for the duration of the session so the pill does not jump across displays during processing/converting/success.
3. Fall back to `NSScreen.main` if no matching screen can be found.
4. Recompute on the next session start and when screen configuration changes.

**Expected result:** On multi-display setups, the pill appears on the display where the user's pointer and attention most likely already are.

**Validation / tests:**

- Manual multi-display verification is required for this one.
- If a small helper is extracted, unit-test the screen-selection math separately.

---

## 8. Paste must distinguish "pasted" from "copied only"

**Where:** `Speech2Text/Clipboard/PasteService.swift`, `Speech2Text/Activation/ActivationStore.swift`

**The problem:** `PasteService.paste(text:)` always writes to the clipboard first, then attempts to synthesize Command-V. If the synthetic key events cannot be created or posted, the text still exists on the clipboard, but the app currently behaves as if paste succeeded.

The earlier proposal suggested returning `Bool` and transitioning to an error state. That is too coarse. Clipboard write success and paste-event success are two different outcomes, and synthetic paste failure should not be treated as total failure.

**Suggested fix:**

1. Replace `Void` return with a small outcome enum, for example:
   - `.pasted`
   - `.copiedOnly`
2. In `ActivationStore`, use the actual outcome when publishing success state.
   - Only set `pasted: true` when the synthetic paste really happened.
   - If paste falls back to clipboard-only, keep the text on the clipboard and show the normal copied-success state instead.
3. Log the failure to synthesize paste events for diagnostics.
4. Do **not** transition to a hard failure state just because automatic paste failed.

**Expected result:** The UI truthfully reports whether text was pasted or merely copied for manual paste.

**Validation / tests:**

- Add an `ActivationStore` test that simulates a paste fallback and verifies the resulting success state is "copied" rather than "pasted".
- This may require extracting a protocol for the paste service or otherwise making paste behavior injectable.

---

## 9. `AudioBufferAccumulator` needs an internal cap and non-silent overflow handling

**Where:** `Speech2Text/Audio/AudioBufferAccumulator.swift`, `Speech2Text/Activation/ActivationStore.swift`

**The problem:** The accumulator currently grows without an internal limit. The 5-minute recording limit lives outside the accumulator in `ActivationStore`. That is fine as a first line of defense, but if that outer guard is delayed, canceled, or bypassed later, the accumulator can grow indefinitely.

The earlier proposal suggested simply stopping appends at the cap. That would silently truncate audio, which is not acceptable.

**Suggested fix:**

1. Add a configurable `maxFrameCount` to `AudioBufferAccumulator` based on a default max-duration constant.
2. When an append would exceed the cap:
   - mark an overflow flag,
   - stop accepting additional buffers.
3. Make `convertToWhisperFormat()` throw a dedicated overflow error instead of returning truncated audio.
4. In `ActivationStore.finalizeSession`, catch that overflow error and map it to a clear user-facing failure path rather than letting it surface as a generic model error.

**Expected result:** The accumulator becomes self-protecting, and if the safety backstop ever trips the user gets a truthful failure instead of a silently truncated transcript.

**Validation / tests:**

- Add `AudioBufferAccumulator` tests for cap enforcement and overflow errors.
- Add an `ActivationStore` test that verifies the overflow is mapped to a clear failure.

---

## 10. Corrupted JSON stores should be quarantined, not silently discarded

**Where:** `Speech2Text/Conversion/UserIntentStore.swift`, `Speech2Text/Activation/TriggerProfileStore.swift`

**The problem:** `UserIntentStore` resets to an empty array on decode failure. `TriggerProfileStore` resets to the default profile. In both cases, the app silently discards the unreadable file and gives the user no path to inspect or recover it.

**Suggested fix:**

1. On decode failure, rename the unreadable file to something like:
   - `IntentStore.json.corrupt`
   - `TriggerProfileStore.json.corrupt`
   or use a timestamped suffix if overwriting is a concern.
2. After quarantining the file, continue with the default in-memory fallback so the app remains usable.
3. Emit a visible warning or at minimum a strong diagnostic log so the user is not left wondering why configuration disappeared.
4. Reuse the same helper pattern across both stores if practical.

**Expected result:** The app still recovers automatically, but the corrupted file is preserved for inspection and data loss is no longer silent.

**Validation / tests:**

- Add store tests that write invalid JSON, trigger load, confirm the file is renamed, and verify the store falls back to defaults afterward.

---

## Deferred / Out of scope for this batch

### `largeTurbo` auto-selection is a product decision, not a cleanup fix

**Where:** `Speech2Text/Transcription/WhisperModelChoice.swift`, `Speech2Text/Shell/SetupWindowView.swift`

The current UI already documents auto-selection as:

- Base for short recordings
- Small for medium recordings
- Medium for long recordings

So the fact that `largeTurbo` is not selected automatically is currently a product choice mismatch at most, not a broken implementation. Do **not** include this in the cleanup implementation batch unless product direction changes.

If product wants `largeTurbo` in auto-selection later, update both:

1. the selection algorithm, and
2. the user-facing UI copy

in the same change.

---

## Recommended implementation order

If a smaller agent is going to execute this document, this order minimizes cross-item interference:

1. Item 4 - calibration accepted-count callback
2. Item 5 - safer store URL resolution
3. Item 6 - assistant settings view model lifecycle
4. Item 1 - silence warning wiring
5. Item 2 - cancel during converting
6. Item 8 - paste outcome correctness
7. Item 3 - capture-busy calibration fix
8. Item 9 - accumulator internal cap
9. Item 10 - corrupted-store quarantine
10. Item 7 - multi-display pill placement

This order is a recommendation, not a dependency graph. Most items remain independent.
