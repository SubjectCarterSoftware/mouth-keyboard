---
phase: 03-recognition-and-clipboard-loop
plan: "02"
subsystem: finish-and-transcribe-loop
tags: [activation-store, whisper, clipboard, spacebar, silence-detection, audio-accumulator]
dependency_graph:
  requires: [WhisperService, AudioBufferAccumulator, ClipboardService, SpacebarInterceptor, RecordingState, ShellPreferences]
  provides: [ActivationStore.finish, ActivationStore.handleSilenceTimeout, AudioLevelMonitor.silenceDetection, AudioCaptureService.bufferAccumulation]
  affects: [AppDelegate, ActivationStore, AudioCaptureService, AudioLevelMonitor]
tech_stack:
  added: [WhisperService.shared singleton]
  patterns: [async-task-transcription, silence-duration-tracking, state-machine-dispatch, protocol-injection-for-testing]
key_files:
  created: []
  modified:
    - Speech2Test/Activation/ActivationStore.swift
    - Speech2Test/Audio/AudioCaptureService.swift
    - Speech2Test/Audio/AudioLevelMonitor.swift
    - Speech2Test/App/AppDelegate.swift
    - Speech2Test/Transcription/WhisperService.swift
    - Speech2Test/Audio/AudioBufferAccumulator.swift
    - Speech2Test/Clipboard/ClipboardService.swift
    - Speech2TestTests/ActivationStoreTests.swift
decisions:
  - "WhisperService.shared singleton added so AppDelegate and ActivationStore.shared share one model instance"
  - "ActivationStore.bufferAccumulator is internal (not private) so AppDelegate can pass it to AudioCaptureService.start()"
  - "ClipboardService and AudioBufferAccumulator made non-final to allow test subclassing in ActivationStoreTests"
  - "removeDuplicates() removed from state pipeline — terminal states are always distinct, removal was preventing success/failure observation"
  - "RecordingPillPanel manages its own visibility via state observer — AppDelegate delegates to it rather than calling orderFrontRegardless()"
  - "AudioCaptureService.stop() resets bufferAccumulator but does not transfer samples — ActivationStore reads accumulator directly via finish()"
metrics:
  duration: "~6 minutes"
  tasks_completed: 2
  files_created: 0
  files_modified: 8
  tests_added: 8
  completed_date: "2026-03-07"
---

# Phase 3 Plan 02: Finish-and-Transcribe Loop Summary

**One-liner:** ActivationStore.finish() drives recording -> processing -> success/failure -> idle with WhisperService transcription, NSPasteboard clipboard write, optional Cmd+V auto-paste, and AudioLevelMonitor silence detection at 45s warning / 60s auto-stop.

## What Was Built

### ActivationStore.swift (major expansion)

**finish() method:** Guards on `.recording` state, transitions to `.processing`, spawns an async `Task` that calls `bufferAccumulator.convertToWhisperFormat()` then `whisperService.transcribe(samples:)`. On success: `state = .success(text:)`, clipboard write, optional autoPaste, 1.5s auto-dismiss to idle. On `noSpeechDetected`: `state = .failure(.noSpeechDetected)`, 2s auto-dismiss. On other errors: `state = .failure(.modelError(...))`, 2s auto-dismiss.

**arm() updated:** When `state == .recording`, calls `finish()` instead of `stop()` — toggle behavior is now finish-and-transcribe.

**handleSilenceTimeout():** Delegates to `finish()` to attempt transcription of whatever audio was captured.

**Dependencies injected via init:** `whisperService: any WhisperTranscribing`, `clipboardService: ClipboardService`, `bufferAccumulator: AudioBufferAccumulator`. All have defaults for production. `ActivationStore.shared` uses `WhisperService.shared`.

**bufferAccumulator** exposed as `internal let` so AppDelegate can pass it to `AudioCaptureService.start()`.

### AudioCaptureService.swift (buffer accumulation)

`start(levelMonitor:bufferAccumulator:)` — `bufferAccumulator` parameter added (optional, default nil). Tap callback now calls `self?.bufferAccumulator?.append(buffer)` alongside `levelMonitor.process(buffer:)`. `stop()` calls `bufferAccumulator?.reset()` and nils the reference. `handleSelectedDeviceDisconnect()` preserves accumulator reference across device reconnect.

### AudioLevelMonitor.swift (silence detection)

Added `onSilenceWarning` and `onSilenceTimeout` callbacks. Tracks `silenceStartTime: Date?` updated in each `process()` call via `Task { @MainActor in ... }`. Silence threshold: normalized level < 0.01 (~-80dB). At 45s: fires `onSilenceWarning` once. At 60s: fires `onSilenceTimeout` once. Any non-silent buffer resets all tracking. `reset()` clears all silence state.

### AppDelegate.swift (full state machine wiring)

- `SpacebarInterceptor` instance added; `start()` on launch, `stop()` on terminate, `isActive = true` on recording, `isActive = false` on processing.
- `onSpacebarPressed` calls `activationStore.finish()`.
- State observation sink expanded from 2 cases to 5: `.recording`, `.processing`, `.success`, `.failure`, `.idle`.
- `removeDuplicates()` removed from pipeline.
- `onRecordingStarted()`: passes `activationStore.bufferAccumulator` to `audioCaptureService.start()`, wires silence callbacks.
- `onProcessingStarted()`: stops audio capture, deactivates spacebar, clears silence callbacks.
- `onTranscriptionSucceeded/Failed()`: update menu bar icon.
- `onReturnedToIdle()`: clears callbacks, resets menu bar icon.
- `updateMenuBarIcon(state:)`: replaces old `updateMenuBarIcon(recording:)` — maps all 5 states to SF symbols.
- Whisper model loaded async on launch from bundle (`ggml-small.en.bin`), errors logged.

### WhisperService.swift

Added `static let shared = WhisperService()` singleton for shared model lifecycle.

### ClipboardService.swift / AudioBufferAccumulator.swift

Removed `final` keyword from both classes to allow test subclassing in `ActivationStoreTests`.

### ActivationStoreTests.swift (8 new tests)

| Test | What it verifies |
|------|-----------------|
| test_finish_transitions_to_processing | arm() -> finish() -> .processing synchronously |
| test_finish_no_op_when_not_recording | finish() from idle is a no-op |
| test_finish_succeeds_writes_clipboard | Mock transcriber "Hello world" -> clipboard written |
| test_finish_fails_no_speech | noSpeechDetected -> .failure(.noSpeechDetected), clipboard unchanged |
| test_arm_while_recording_calls_finish | arm() -> arm() -> .processing (toggle triggers finish) |
| test_auto_paste_enabled | autoPaste() called when preference is true |
| test_auto_paste_disabled | autoPaste() NOT called when preference is false |
| test_failure_does_not_write_clipboard | On failure, clipboard write not called |

New mock types: `ActivationStoreMockTranscriber` (name-scoped to avoid conflict with `WhisperServiceTests.MockWhisperTranscriber`), `ActivationStoreMockClipboard` (subclass), `StubBufferAccumulator` (subclass returning `[0.0, 0.0, 0.0]`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ClipboardService and AudioBufferAccumulator were final — prevented test subclassing**
- **Found during:** Task 1 (TDD RED phase — test file failed to compile)
- **Issue:** Both classes marked `final`, making subclassing in test mocks impossible.
- **Fix:** Removed `final` keyword from both class declarations.
- **Files modified:** `Speech2Test/Clipboard/ClipboardService.swift`, `Speech2Test/Audio/AudioBufferAccumulator.swift`
- **Commit:** 6c6ca29

**2. [Rule 2 - Missing] WhisperService lacked a shared singleton**
- **Found during:** Task 2 — plan specified `WhisperService.shared.loadModel(at:)` but no `shared` property existed.
- **Fix:** Added `static let shared = WhisperService()` to the actor.
- **Files modified:** `Speech2Test/Transcription/WhisperService.swift`
- **Commit:** b8eff16

**3. [Rule 1 - Bug] removeDuplicates() on state pipeline would suppress terminal state transitions**
- **Found during:** Task 2 — consecutive `.success(text:)` calls with identical text would be swallowed; more importantly, success/failure states were not observed at all in the old switch.
- **Fix:** Removed `removeDuplicates()` from state observation pipeline.
- **Files modified:** `Speech2Test/App/AppDelegate.swift`
- **Commit:** b8eff16

### Out-of-Scope Discoveries (Not Fixed)

**Pre-existing failure:** `AudioCaptureServiceTests.testAudioLevelMonitorProcessesRMSLevel` continues to fail (expects level=0.5, gets 1.0). Previously logged to `deferred-items.md` in Plan 01. Not caused by this plan's changes.

## Self-Check: PASSED

Verified files exist:
- Speech2Test/Activation/ActivationStore.swift — FOUND (contains `func finish()`)
- Speech2Test/Audio/AudioLevelMonitor.swift — FOUND (contains `onSilenceTimeout`)
- Speech2Test/Audio/AudioCaptureService.swift — FOUND (contains `bufferAccumulator`)
- Speech2Test/App/AppDelegate.swift — FOUND (contains `spacebarInterceptor`, 5-case switch)
- Speech2Test/Transcription/WhisperService.swift — FOUND (contains `shared`)

Commits verified:
- 6c6ca29 — feat(03-02): wire finish flow in ActivationStore, buffer accumulation, silence detection
- b8eff16 — feat(03-02): wire AppDelegate for full state machine and spacebar interceptor lifecycle
