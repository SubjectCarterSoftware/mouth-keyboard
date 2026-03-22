# Codebase Concerns

**Analysis Date:** 2026-03-22

---

## Resource Lifecycle Issues

### LLM Rewrite Model: Loaded But Never Unloaded

**Issue:** `LLMRewriteService.shared` holds a `cachedModel` (a `ModelContainer` wrapping a large MLX LLM) in memory from first use until the app terminates. There is no unload, eviction, or idle-timeout path. The model is cleared only when `setTier()` is called (tier change). A user who runs one AI rewrite keeps the 1.1–5.0 GB model resident for the entire session.

- Files: `Speech2Text/Conversion/LLMRewriteService.swift`
- Impact: Persistent RAM pressure; models are 1.1 GB (1.7B), 2.5 GB (4B), or 5.0 GB (8B) resident. On 8 GB machines using the 8B tier, this can crowd out Whisper + the audio engine.
- Fix approach: Add an `unload()` method that nils `cachedModel` and `loadTask`. Call it from `AppDelegate.applicationWillTerminate` and/or on a configurable idle timer (e.g., 10 minutes after last use). The `setTier()` path already does this correctly and serves as a model.

---

### WhisperKit Model: Loaded But Never Unloaded

**Issue:** `WhisperService.shared` holds `private var pipe: WhisperKit?` in memory after the first `prepare()` call and never releases it. There is no unload path. If `autoModelSelection` is on, the service may load multiple different models across sessions (the `guard model != currentModel || pipe == nil` condition means a tier change replaces the old model, but the old `WhisperKit` object is not explicitly deinitialized—it is simply replaced by assignment, relying on ARC). However the current model is always retained indefinitely.

- Files: `Speech2Text/Transcription/WhisperService.swift`
- Impact: WhisperKit base.en is ~150 MB; medium.en is ~1.5 GB. With the LLM also loaded, total persistent ML model RAM can easily exceed 3–6 GB on a single session.
- Fix approach: Add an `unload()` that sets `pipe = nil` and `currentModel = nil`. Call from `applicationWillTerminate`. Optionally unload after a configurable idle period.

---

### AVAudioEngine: Intentionally Retained After Stop (Documented Trade-off with Risk)

**Issue:** `AudioCaptureService.stop()` explicitly keeps the `AVAudioEngine` instance alive to avoid CoreAudio hardware teardown/rebuild races. The comment reads "Keep engine alive to avoid CoreAudio hardware teardown/rebuild races when re-pressing Ctrl-V quickly." This is intentional, but the engine holds hardware resources (CoreAudio input node). If `ensureEngine()` never deems the old engine unusable, the engine is held for the entire app lifetime.

- Files: `Speech2Text/Audio/AudioCaptureService.swift` (lines 199–206)
- Impact: CoreAudio input device lock held persistently. On shared-device machines, this may block other audio recording apps from the same input.
- Fix approach: Add a "reuse window" heuristic — release the engine after N seconds of idle, or explicitly in `applicationWillTerminate`.

---

## Missing Flows

### Silence Warning: Wired But Never Surfaced in UI

**Issue:** `AudioLevelMonitor` fires `onSilenceWarning` after 45 seconds of silence. `AppDelegate.onRecordingStarted()` wires a closure that only calls `NSLog(...)`. `RecordingPillView` has a `silenceWarningActive: Bool` property and uses it to tint the bars orange — but this flag is never set to `true` by any live code path. The visual warning is dead code in production.

- Files: `Speech2Text/App/AppDelegate.swift` (lines 135–137), `Speech2Text/Shell/RecordingPillView.swift` (line 62), `Speech2Text/Shell/RecordingPillPanel.swift`
- Impact: Users receive no visual warning that they are about to be auto-stopped for silence. The 60-second auto-stop fires without any preceding UI cue.
- Fix approach: When `onSilenceWarning` fires, set a flag on `ActivationStore` (e.g., `isSilenceWarningActive: Bool`) and pass it through to `RecordingPillView` via the existing `silenceWarningActive` parameter.

---

### Cancel-During-Converting: Not Guarded in UI

**Issue:** `cancelCurrentSession()` guards on `state == .recording || state == .processing` only. The `.converting` state (LLM rewrite in-flight) is not cancellable through the UI — the cancel button in `RecordingPillPanel` is inactive during `.converting` because the panel only enables `ignoresMouseEvents = false` during `.recording`. However, the LLM task would be cancelled if the `transcriptionTask` was cancelled, but the guard in `cancelCurrentSession()` prevents entry during `.converting`. The user is stuck waiting for the LLM to finish with no escape.

- Files: `Speech2Text/Activation/ActivationStore.swift` (lines 204–211), `Speech2Text/Shell/RecordingPillPanel.swift` (lines 98–101)
- Impact: If the LLM hangs or takes unusually long, the user cannot interrupt without quitting the app.
- Fix approach: Extend `cancelCurrentSession()` guard to include `.converting`. Extend `RecordingPillPanel.updatePresentation` to enable mouse events during `.converting` so the cancel button is accessible.

---

### LiveCalibrationSampleCapturer: Uses AudioCaptureService Without Checking Recording State

**Issue:** `LiveCalibrationSampleCapturer.captureSample()` calls `capture.start(...)` directly on `AudioCaptureService.shared` without checking whether the main `ActivationStore` is currently recording. If the user opens the AI Assistant settings sheet and taps "Record Custom Name" while a regular recording session is active, the `AudioCaptureService` will be started again — but `start()` is guarded by `guard !hasInstalledTap`, so the call silently does nothing and the calibration proceeds with an empty accumulator, returning `nil`. There is no user-facing error for this conflict.

- Files: `Speech2Text/Audio/LiveCalibrationSampleCapturer.swift`, `Speech2Text/Shell/AIAssistantSettingsView.swift` (lines 273–295)
- Impact: Silent calibration failure with no feedback when called during recording.
- Fix approach: Check `ActivationStore.shared.state != .idle` before starting calibration and surface an error or disable the button.

---

## State Management Gaps

### `AIAssistantTileView`: Ephemeral ViewModel Created Per Render

**Issue:** `AIAssistantTileView.body` constructs a new `AIAssistantSettingsViewModel(preferences: preferences)` on every SwiftUI render pass (`let vm = AIAssistantSettingsViewModel(preferences: preferences)` inside `var body`). The ViewModel subscribes to `preferences.$activeTriggerProfile` in its `init`. Each render creates a new subscriber that is immediately released, so the `cancellables` bag is discarded on every layout pass. The tile reads `vm.activeName`, `vm.tileStatusLine`, and `vm.aliasSummary` synchronously from `init`, which is correct, but the subscription is wasted on each render and the ViewModel lifecycle is never properly managed.

- Files: `Speech2Text/Shell/AIAssistantSettingsView.swift` (lines 97–128, specifically line 102)
- Impact: Wasteful allocation and subscription setup per render. If SwiftUI retains the `vm` longer than expected in some versions, stale observers may fire.
- Fix approach: Promote `AIAssistantSettingsViewModel` to a `@StateObject` in `SetupWindowView`, or refactor `AIAssistantTileView` to read directly from `preferences` properties without an intermediary ViewModel.

---

### `AssistantCalibrationRunner.onSampleAccepted`: Always Passes 0

**Issue:** `AssistantCalibrationRunner.runSession()` calls `onSampleAccepted?(0)` unconditionally (line 66). The parameter is documented as "delivers accepted count (1, 2)" but always passes `0`. There is a `countAccepted()` private method that returns `0` hardcoded, with a comment noting it is "best-effort" and "not exposed as state."

- Files: `Speech2Text/Shell/AssistantCalibrationRunner.swift` (lines 66, 76–82)
- Impact: Any UI caller using `onSampleAccepted` to show progress (e.g., "1 of 3 recorded") would always see 0. This is incomplete/stub behavior.
- Fix approach: Track accepted sample count within `runSession()` using a local counter and pass the current count to `onSampleAccepted`.

---

### `WhisperModelChoice.forDuration`: `largeTurbo` Never Selected by Auto-Selection

**Issue:** `WhisperModelChoice` defines a `largeTurbo` case but `forDuration(_:)` only returns `.baseEN`, `.smallEN`, or `.mediumEN`. The large-v3-turbo model is listed in settings as "best quality" but is unreachable via auto-selection. A user who picks it manually in preferences will use it if `autoModelSelection == false`, but the auto path never escalates to it.

- Files: `Speech2Text/Transcription/WhisperModelChoice.swift` (lines 21–25)
- Impact: Misleading settings UI — "Large Turbo (best quality)" is offered as an explicit option but auto-selection ignores it, creating a silent inconsistency.
- Fix approach: Either add a `>= 5 min` branch returning `.largeTurbo`, or add a UI note that large-turbo is only used when auto-selection is disabled.

---

## Error Handling Gaps

### `UserIntentStore.defaultStoreURL` and `TriggerProfileStore.defaultStoreURL`: Force-Try on System URL

**Issue:** Both `UserIntentStore.defaultStoreURL` and `TriggerProfileStore.defaultStoreURL` use `try!` when resolving the Application Support directory:

```swift
let appSupport = try! FileManager.default.url(
    for: .applicationSupportDirectory, in: .userDomainMask, ...
)
```

While this path almost never fails on macOS, it will crash the app in sandboxed edge cases (e.g., permissions misconfiguration, corrupted user home directory).

- Files: `Speech2Text/Conversion/UserIntentStore.swift` (line 11), `Speech2Text/Activation/TriggerProfileStore.swift` (line 11)
- Impact: Crash (unhandled exception) on rare but possible system misconfiguration.
- Fix approach: Use `try?` with a fallback to `FileManager.default.temporaryDirectory`, or convert `defaultStoreURL` to a throwing computed property.

---

### `isMemoryPressureError`: String-Matching Heuristic

**Issue:** `LLMRewriteService.isMemoryPressureError(_:)` detects OOM by string-matching `error.localizedDescription.lowercased()` for `"out of memory"` and `"memory" && "alloc"`. This is a fragile heuristic against unstructured error strings from the MLX framework. A future MLX version could change error message wording and silently break OOM detection, causing the app to re-attempt loading a model that will always fail, rather than falling back to the smaller tier.

- Files: `Speech2Text/Conversion/LLMRewriteService.swift` (lines 265–268)
- Impact: Silent breakage if MLX error messages change. OOM fallback logic stops working.
- Fix approach: Check for specific MLX error types or error codes if the framework exposes them. Otherwise, add a snapshot test for error message strings to catch regressions.

---

### `UserIntentStore.load()`: Silent Corruption Degradation

**Issue:** When `IntentStore.json` fails to decode, `load()` silently resets to an empty array and sets `loaded = true`. The user's custom intents are lost with no error surfaced to the UI.

- Files: `Speech2Text/Conversion/UserIntentStore.swift` (lines 77–90)
- Impact: A corrupt JSON file (e.g., from an interrupted write) silently wipes all custom AI shortcuts on next launch, with no user notification.
- Fix approach: Rename corrupt store to a backup file before resetting (preserves user data), and/or log a visible error through `ReadinessStore` or a notification.

---

## Performance Concerns

### `IntentDetector`: Significant Code Duplication Across Four Scoring Methods

**Issue:** `IntentDetector.swift` contains four nearly-identical scoring method families: `scoreZone`/`scoreAllZone` (accepts `[ConvertMode]`, filters `IntentCatalog.all` internally) and `scoreZoneDefs`/`scoreAllZoneDefs` (accepts `[IntentDefinition]` directly). The implementations are 95% identical, totalling ~300 lines of duplicated logic.

- Files: `Speech2Text/Conversion/IntentDetector.swift` (lines 337–532)
- Impact: Any bug fix or improvement to one scoring method must be applied to three others. High maintenance surface. Already exhibits minor divergence (the `defs` overloads lack the `modes.contains($0.mode)` filter line but are otherwise identical).
- Fix approach: Extract a single private `scoreZoneImpl(_ zone: String, defs: [IntentDefinition])` that both families delegate to after resolving the definition list.

---

### `AudioBufferAccumulator`: Unbounded Buffer Growth During Long Recordings

**Issue:** `AudioBufferAccumulator` appends `AVAudioPCMBuffer` objects indefinitely in `buffers: [AVAudioPCMBuffer]`. There is a 5-minute max recording duration (enforced by `ActivationStore.maxDurationTask`), but at 16 kHz float32 mono that is ~300 seconds × 16000 samples × 4 bytes ≈ ~19 MB of raw samples plus per-buffer overhead multiplied by the capture buffer size (4096 frames per buffer). Under normal use this is fine, but if the 5-minute guard fires late or is cancelled, the accumulator is uncapped.

- Files: `Speech2Text/Audio/AudioBufferAccumulator.swift`, `Speech2Text/Activation/ActivationStore.swift` (line 69)
- Impact: Low risk under normal use; edge case during interrupted sessions.
- Fix approach: Add an optional `maxDurationSeconds` cap inside `AudioBufferAccumulator.append()` that stops accumulating beyond the limit.

---

## Security Considerations

### PasteService: Clipboard Overwrite Before CGEvent Post

**Issue:** `PasteService.paste(text:)` writes text to `NSPasteboard.general`, then immediately posts `CGEvent` Cmd+V. Between those two operations, another process could theoretically read the clipboard. More practically, if the `CGEvent` delivery fails silently (`keyDown?.post(...)` returns void, errors are not checked), the sensitive transcription text is left on the clipboard but was not pasted, leaving it accessible to any app that reads the clipboard. The user may not be aware this occurred.

- Files: `Speech2Text/Clipboard/PasteService.swift`
- Impact: Transcribed text is always written to the shared clipboard as a side effect of paste, which is expected behavior, but failure to paste is invisible to the user.
- Fix approach: Return a Bool from `paste(text:)` indicating whether the key events were successfully created, and surface failure through the recording state machine.

---

## Fragile Areas

### `AppDelegate.updateMenuBarIcon`: DOM-Walking Heuristic

**Issue:** `AppDelegate.updateMenuBarIcon(state:)` finds the menu bar button by iterating `NSApp.windows` for windows at `statusBar` level and accessing their first `NSButton` subview. This relies on undocumented AppKit view hierarchy structure for `MenuBarExtra`. Apple could change this hierarchy in any macOS update, silently breaking the icon update.

- Files: `Speech2Text/App/AppDelegate.swift` (lines 208–217)
- Impact: Menu bar icon stops updating on state changes after any macOS update that changes the `MenuBarExtra` view hierarchy. Best-effort by design (comment acknowledges this).
- Fix approach: Migrate to `@Environment(\.menuBarExtraAccess)` or hold a direct reference to the `NSStatusItem` once SwiftUI exposes one, rather than walking the window tree.

---

### `RewriteExecutionGate`: Waiter Queue Has No Cancellation Support

**Issue:** `RewriteExecutionGate` is a custom serialization actor with a `waiters: [CheckedContinuation<Void, Never>]` queue. If a task that is waiting in the queue is cancelled before `release()` is called, its continuation is never resumed (no cancellation hook). The waiting `Task` will block indefinitely until another `release()` fires — potentially blocking the next legitimate rewrite operation from acquiring the gate.

- Files: `Speech2Text/Conversion/LLMRewriteService.swift` (lines 37–59)
- Impact: Under task cancellation (e.g., user starts a second session while first is in the LLM queue), the gate can deadlock if cancelled waiters are not cleaned up.
- Fix approach: Use `withTaskCancellationHandler` in `acquire()`, or replace `RewriteExecutionGate` with a Swift `AsyncSemaphore` pattern that handles cancellation (Swift Concurrency's `Actor` alone is sufficient for serial execution — the extra gate may be removable).

---

### `RecordingPillPanel.updatePosition`: Anchored to `NSScreen.main` Only

**Issue:** Pill panel position is calculated using `NSScreen.main?.visibleFrame`. On multi-display setups, `NSScreen.main` is the display containing the menu bar, which may not be the display the user is currently working on. The pill always appears on the primary display, potentially far from the user's focus.

- Files: `Speech2Text/Shell/RecordingPillPanel.swift` (lines 133–141)
- Impact: Poor UX on multi-monitor setups. Low severity but frequently noticed.
- Fix approach: Anchor to the screen containing the key window (`NSApp.keyWindow?.screen ?? NSScreen.main`) at arm time.

---

## Test Coverage Gaps

### LLM Unload / Memory Pressure Recovery Path

**What's not tested:** There are no tests for `LLMRewriteService` behavior after memory pressure: the OOM fallback path (`isMemoryPressureError`), what happens when `setTier()` is called while a `loadTask` is in-flight with a waiter in `RewriteExecutionGate`, and whether the gate properly serializes concurrent rewrite calls under cancellation.

- Files: `Speech2TextTests/LLMRewriteServiceTests.swift`, `Speech2TextTests/LLMRewriteServiceIntegrationTests.swift`
- Risk: OOM fallback and gate serialization are untested. Regressions in these paths would be invisible.
- Priority: High

### Silence Warning UI Wire-Up

**What's not tested:** No test verifies that `onSilenceWarning` actually sets `silenceWarningActive` on the pill view, because this wire-up is missing (see concern above). Tests in `WhisperServiceTests.swift` and `AudioCaptureServiceTests.swift` don't cover the silence warning → UI path.

- Files: `Speech2TextTests/` (no dedicated silence-warning UI test)
- Risk: The orange bar tint feature has no test and no production code path.
- Priority: Medium

### `LiveCalibrationSampleCapturer` Conflict with Active Recording

**What's not tested:** No test covers the scenario where `captureSample()` is called while `AudioCaptureService` already has a tap installed.

- Files: `Speech2TextTests/` (no test for this race condition)
- Risk: Silent failure during concurrent use; hard to reproduce and debug without a test.
- Priority: Medium

---

*Concerns audit: 2026-03-22*
