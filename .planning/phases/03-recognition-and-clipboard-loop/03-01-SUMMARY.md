---
phase: 03-recognition-and-clipboard-loop
plan: "01"
subsystem: transcription-services
tags: [whisper, audio, clipboard, spacebar, swift-actor, spm]
dependency_graph:
  requires: [RecordingState, ShellPreferences]
  provides: [WhisperService, AudioBufferAccumulator, ClipboardService, SpacebarInterceptor, TranscriptionResult, TranscriptionError, WhisperTranscribing, SpacebarHandling]
  affects: [ActivationStore, AppDelegate]
tech_stack:
  added: [whisper.spm@master, AVAudioConverter, CGEventTap, NSPasteboard, NSLock]
  patterns: [actor-isolation, protocol-mocking-for-hardware, thread-safe-buffer-accumulation, tdd-red-green]
key_files:
  created:
    - Speech2Test/Transcription/WhisperService.swift
    - Speech2Test/Transcription/TranscriptionResult.swift
    - Speech2Test/Audio/AudioBufferAccumulator.swift
    - Speech2Test/Clipboard/ClipboardService.swift
    - Speech2Test/Activation/SpacebarInterceptor.swift
    - Speech2TestTests/WhisperServiceTests.swift
    - Speech2TestTests/AudioBufferAccumulatorTests.swift
    - Speech2TestTests/ClipboardServiceTests.swift
    - Speech2TestTests/SpacebarInterceptorTests.swift
    - Speech2TestTests/ShellPreferencesPhase3Tests.swift
  modified:
    - Speech2Test/Activation/RecordingState.swift
    - Speech2Test/Persistence/ShellPreferences.swift
    - Speech2Test/App/AppDelegate.swift
    - Speech2Test.xcodeproj/project.pbxproj
decisions:
  - "whisper.spm added with branch:master requirement to avoid unsafe build flag errors (per research)"
  - "AudioBufferAccumulator uses NSLock for thread safety since append is called from audio tap thread"
  - "WhisperService is an actor to ensure all whisper C API calls are serialized"
  - "SpacebarInterceptor tested via SpacebarHandling protocol mock — CGEventTap requires Accessibility permission in CI"
  - "ClipboardService accepts optional NSPasteboard in init for testability without polluting general pasteboard"
  - "AppDelegate switch updated with default:break to remain exhaustive after RecordingState expansion"
metrics:
  duration: "~55 minutes"
  tasks_completed: 1
  files_created: 12
  files_modified: 4
  tests_added: 25
  completed_date: "2026-03-06"
---

# Phase 3 Plan 01: Type Contracts and Standalone Services Summary

**One-liner:** whisper.cpp actor wrapper, AVAudioConverter 16kHz resampling, NSPasteboard clipboard write, CGEventTap spacebar interception, and expanded RecordingState — all with protocol-mock test scaffolds.

## What Was Built

### Production Files (6 total)

**RecordingState.swift (expanded):** Added `processing`, `success(text: String)`, `failure(reason: FailureReason)` cases. Added `FailureReason` nested enum with `noSpeechDetected`, `modelError(String)`, `silenceTimeout`. Added `isTerminal` computed property.

**TranscriptionResult.swift (new):** Simple enum `success(String)` / `failure(RecordingState.FailureReason)` as the return type for the recognition pipeline.

**WhisperService.swift (new):** `actor WhisperService` wrapping whisper.cpp C API. Defines `WhisperTranscribing` protocol for testability. Loads model via `whisper_init_from_file_with_params` with `flash_attn = true`. Transcribes via `whisper_full` with `WHISPER_SAMPLING_GREEDY`, `n_threads = max(1, min(8, processorCount - 2))`, language "en". Defines `TranscriptionError: LocalizedError` with 4 cases.

**AudioBufferAccumulator.swift (new):** Thread-safe accumulator using NSLock. Accepts `AVAudioPCMBuffer` chunks from the audio tap thread. `convertToWhisperFormat()` resamples via `AVAudioConverter` to 16kHz mono Float32 in a single pass.

**ClipboardService.swift (new):** Wraps `NSPasteboard` (injectable for tests). `writeToClipboard(_:)` clears and sets string. `autoPaste()` posts CGEvent Cmd+V with 50ms delay.

**SpacebarInterceptor.swift (new):** `final class SpacebarInterceptor: SpacebarHandling`. Creates `CGEvent.tapCreate` at `.cgSessionEventTap` / `.headInsertEventTap`. Callback checks `isActive` and keyCode 49 (space); on match, swallows event and dispatches `onSpacebarPressed` to main queue.

**ShellPreferences.swift (expanded):** Added `autoPasteEnabled` and `indicatorVisible` — both `@Published Bool` defaulting to `true`, persisting to UserDefaults, and resetting in `reset()`.

### SPM Package

**whisper.spm** added to `project.pbxproj` at `branch: master`. Resolved commit a208543. Linked to Speech2Test main target via `whisper in Frameworks` build phase.

### Test Files (5 total — 25 tests, all passing)

| File | Tests | Coverage |
|------|-------|----------|
| WhisperServiceTests | 5 | Mock protocol, error cases, real actor load/transcribe paths |
| AudioBufferAccumulatorTests | 5 | Append, reset, empty-throw, resampling ratio |
| ClipboardServiceTests | 3 | Write, replace, pasteboard contents |
| SpacebarInterceptorTests | 6 | Protocol conformance, isActive, mock handler |
| ShellPreferencesPhase3Tests | 6 | Defaults, persistence, reset |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] AppDelegate switch non-exhaustive after RecordingState expansion**
- **Found during:** Task 1 (Step 2 — expanding RecordingState)
- **Issue:** `AppDelegate.swift` switch on `RecordingState` only handled `.idle` and `.recording`. Adding new cases causes a compile error.
- **Fix:** Added `case .processing, .success, .failure: break` to make the switch exhaustive.
- **Files modified:** `Speech2Test/App/AppDelegate.swift`
- **Commit:** c83edb7 (same task commit)

### Out-of-Scope Discoveries (Deferred)

**Pre-existing failure:** `AudioCaptureServiceTests.testAudioLevelMonitorProcessesRMSLevel` was failing before Phase 3 changes (expects level=0.5, gets 1.0). Logged to `deferred-items.md`. Not related to Plan 01.

## Self-Check: PASSED

All 11 expected files verified present on disk.
Task commit c83edb7 verified in git log.
