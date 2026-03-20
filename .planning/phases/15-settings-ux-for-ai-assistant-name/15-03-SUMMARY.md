---
phase: 15-settings-ux-for-ai-assistant-name
plan: "03"
subsystem: ui
tags: [swift, swiftui, calibration, audio, whisper]

# Dependency graph
requires:
  - phase: 15-01
    provides: AssistantCalibrationRunner + CalibrationSampleCapturing protocol + TriggerCalibrationSession
  - phase: 15-02
    provides: AIAssistantSettingsView sheet scaffold + AIAssistantSettingsViewModel
provides:
  - LiveCalibrationSampleCapturer (production CalibrationSampleCapturing conformer wrapping AudioCaptureService + AudioBufferAccumulator + WhisperService)
  - AIAssistantSettingsView calibration section (Start Calibration, Skip, Cancel, progress, retry feedback, completion state)
  - SETT-03 fully satisfied: calibration entry point in assistant settings sheet
affects:
  - Any future phase that adds calibration triggers or additional calibration UX

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@MainActor final class conforming to Sendable protocol for production audio capture"
    - "AssistantCalibrationRunner instantiated with LiveCalibrationSampleCapturer in startCalibration() private method on View"
    - "Calibration UI state managed via @State on View struct; runner stored as @State runner: AssistantCalibrationRunner?"

key-files:
  created:
    - Speech2Text/Audio/LiveCalibrationSampleCapturer.swift
  modified:
    - Speech2Text/Shell/AIAssistantSettingsView.swift
    - Speech2Text.xcodeproj/project.pbxproj

key-decisions:
  - "LiveCalibrationSampleCapturer uses @MainActor final class (not struct) because AudioCaptureService.start/stop are @MainActor methods requiring actor-bound context"
  - "captureSample returns nil (retry) on most errors; only throws CalibrationCapturingDone.exhausted on microphonePermissionDenied to exit runner cleanly"
  - "isCalibrationRequired consumed in view by appending (Recommended) to button label — closes dead-state anti-pattern"
  - "Sheet frame increased to minHeight 460 / idealHeight 500 to accommodate calibration section"

patterns-established:
  - "Calibration cancel: nil out runner @State; running async Task will exit on next captureSample call via CalibrationCapturingDone path"

requirements-completed: [SETT-01, SETT-02, SETT-03]

# Metrics
duration: 5min
completed: 2026-03-20
---

# Phase 15 Plan 03: Settings UX for AI Assistant Name — Calibration Integration Summary

**LiveCalibrationSampleCapturer + AIAssistantSettingsView calibration section close SETT-03: production audio-capture-and-transcribe capturer wired into the settings sheet with Start/Skip/Cancel/progress UI**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-20T18:43:40Z
- **Completed:** 2026-03-20T18:48:44Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created `LiveCalibrationSampleCapturer` — production `CalibrationSampleCapturing` conformer that records 3 seconds via `AudioCaptureService` + `AudioBufferAccumulator`, transcribes with `WhisperService`, and returns `CalibrationSample(rawTranscript:)`
- Wired calibration section into `AIAssistantSettingsView` sheet with accessibility-identified Start Calibration, Skip, Cancel buttons, ProgressView, retry text, and completion text
- `startCalibration()` instantiates `AssistantCalibrationRunner` with `LiveCalibrationSampleCapturer` and drives it from the view via an async Task
- All 21 existing Phase 15 unit tests continue to pass; the 2 pre-existing failures (HotkeyServiceTests, ShellPreferencesModelTests) are unaffected

## Task Commits

Each task was committed atomically:

1. **Task 1: Create LiveCalibrationSampleCapturer** - `c1969a1` (feat)
2. **Task 2: Wire calibration section into AIAssistantSettingsView** - `42f7c20` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified
- `Speech2Text/Audio/LiveCalibrationSampleCapturer.swift` - Production CalibrationSampleCapturing conformer
- `Speech2Text/Shell/AIAssistantSettingsView.swift` - Added @State calibration vars, calibration section body, startCalibration() method, updated frame
- `Speech2Text.xcodeproj/project.pbxproj` - Registered LiveCalibrationSampleCapturer.swift in Speech2Text target Audio/ group

## Decisions Made
- `LiveCalibrationSampleCapturer` uses `@MainActor final class` (not struct) because `AudioCaptureService.start/stop` are `@MainActor` methods that must be called from within the same actor context
- `captureSample` returns `nil` on most errors (triggering runner retry); only throws `CalibrationCapturingDone.exhausted` on `microphonePermissionDenied` to exit the runner cleanly without completing
- `isCalibrationRequired` ViewModel property consumed in view — appends "(Recommended)" to the Start Calibration button label when true, closing the dead-state anti-pattern identified in VERIFICATION.md
- Sheet `minHeight`/`idealHeight` increased to 460/500 to accommodate the new calibration section

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. The 2 pre-existing test failures (`HotkeyServiceTests.testDefaultActivationShortcutIsControlV`, `ShellPreferencesModelTests.testLaunchAtLoginDefaultsToFalse`) are documented in STATE.md as out of scope.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SETT-01, SETT-02, SETT-03 all satisfied — Phase 15 milestone complete
- The calibration entry point now exists in the assistant settings sheet; future work could add real-time audio level visualization during calibration
- Pre-existing HotkeyServiceTests / ShellPreferencesModelTests failures need separate attention

---
*Phase: 15-settings-ux-for-ai-assistant-name*
*Completed: 2026-03-20*
