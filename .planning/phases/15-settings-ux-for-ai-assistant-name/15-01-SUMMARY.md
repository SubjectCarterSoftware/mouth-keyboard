---
phase: 15-settings-ux-for-ai-assistant-name
plan: 01
subsystem: ui
tags: [swiftui, settings, trigger-profile, calibration, view-model]

requires:
  - phase: 12-trigger-identity-and-persistence
    provides: TriggerProfile, TriggerProfileStore, ShellPreferences mutation APIs (setTriggerPreset, setCustomTrigger, applyCalibrationAliases)
  - phase: 13-last-name-wins-parser-integration
    provides: TriggerCalibrationSession with 3-sample contract and retry semantics

provides:
  - AIAssistantSettingsViewModel: @MainActor ObservableObject driving tile status, preset/custom mutations, and alias summary
  - AIAssistantSettingsView: single-page sheet with preset rows, custom name entry, and alias summary display
  - AIAssistantTileView: settings window tile showing active name, Default/Preset/Custom status, and Change button
  - AssistantCalibrationRunner: session coordinator over CalibrationSampleCapturing protocol
  - CalibrationSampleCapturing: testable seam for calibration capture, decoupled from ActivationStore
  - CalibrationCapturingDone: exit sentinel for capturer exhaustion

affects: [phase-15-02, end-to-end assistant configuration automation]

tech-stack:
  added: []
  patterns:
    - "View model drives tile status from activeTriggerProfile via Combine sink; no direct coupling to ShellPreferences internals"
    - "CalibrationSampleCapturing protocol decouples AssistantCalibrationRunner from live audio, making it deterministically testable via StubCalibrationSampleCapturer"
    - "CalibrationCapturingDone error type enables clean session exit when capturer is exhausted (test stub) or user cancels"

key-files:
  created:
    - Speech2Text/Shell/AIAssistantSettingsView.swift
    - Speech2Text/Shell/AssistantCalibrationRunner.swift
    - Speech2TextTests/AIAssistantSettingsViewModelTests.swift
    - Speech2TextTests/AssistantCalibrationRunnerTests.swift
  modified:
    - Speech2Text/Shell/SetupWindowView.swift
    - Speech2Text.xcodeproj/project.pbxproj

key-decisions:
  - "AIAssistantSettingsViewModel initialized directly from preferences; pendingSelection tracks sheet state separately from activeTriggerProfile so preset selections are staged before apply"
  - "CalibrationCapturingDone error type used as exit sentinel so runSession() terminates cleanly when capturer exhausts samples (both in tests and when user cancels real capture)"
  - "Tile placed between keyboard shortcuts form and Conversion Modes section to stay visible without being buried"
  - "AliasSummary shows only non-primary aliases; nil when only canonical alias present (no calibration done)"
  - "SaveCustomName gated by empty-check on trimmedInput; pendingSelection only switches to .custom after explicit save"

patterns-established:
  - "Sheet-based configuration subflows driven by @State showingXxxSheet flags on the parent view"
  - "Protocol-based capture seam (CalibrationSampleCapturing) with error-based exhaustion signal for testability without live microphone"

requirements-completed: [SETT-01, SETT-02, SETT-03]

duration: 33min
completed: 2026-03-20
---

# Phase 15 Plan 01: Settings UX for AI Assistant Name Summary

**AI Assistant tile in settings window with preset/custom name sheet, CalibrationSampleCapturing protocol, and AssistantCalibrationRunner backed by 25 passing tests**

## Performance

- **Duration:** 33 min
- **Started:** 2026-03-20T17:29:32Z
- **Completed:** 2026-03-20T18:03:19Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- SetupWindowView now exposes an AI Assistant tile (active name, Default/Preset/Custom status, Change button) between the shortcuts form and Conversion Modes section
- AIAssistantSettingsView sheet provides preset selection (immediate apply) and custom name entry (save-gated) in one page with alias summary display
- AssistantCalibrationRunner coordinates TriggerCalibrationSession loop over CalibrationSampleCapturing, fires retry/accepted/complete callbacks, calls applyCalibrationAliases on completion
- 25 tests pass: 14 view-model tests (tile state, preset switching, custom name normalization, alias summary) and 7 calibration runner tests (retry, completion, alias replacement) plus 4 existing TriggerCalibrationSession tests

## Task Commits

1. **Task 1: Add RED tests for assistant settings state and calibration runner behavior** - `42dbd55` (test)
2. **Task 2: Implement AI Assistant tile, single-sheet configuration flow, and guided calibration capture** - `0c7ce6a` (feat)

**Plan metadata:** (docs commit — created after task commits)

## Files Created/Modified

- `Speech2Text/Shell/AIAssistantSettingsView.swift` - AIAssistantSettingsViewModel, AIAssistantTileView, AIAssistantSettingsView with accessibility IDs
- `Speech2Text/Shell/AssistantCalibrationRunner.swift` - AssistantCalibrationRunner + CalibrationSampleCapturing protocol + CalibrationCapturingDone
- `Speech2Text/Shell/SetupWindowView.swift` - AI Assistant tile + sheet presentation state
- `Speech2Text.xcodeproj/project.pbxproj` - 4 new files registered (2 production, 2 test)
- `Speech2TextTests/AIAssistantSettingsViewModelTests.swift` - 14 state-level tests
- `Speech2TextTests/AssistantCalibrationRunnerTests.swift` - 7 deterministic runner tests

## Decisions Made

- `CalibrationCapturingDone` error type used as exit sentinel so `runSession()` terminates cleanly when the capturer exhausts its samples — this covers both test stubs and real-device cancellation flows
- `aliasSummary` shows only non-primary aliases (nil when only canonical alias present), keeping the tile quiet until calibration has actually produced useful variants
- `pendingSelection` tracks in-sheet state separately from `activeTriggerProfile` so preset rows show the current selection without triggering a store write on every render
- Tile placed between keyboard shortcuts form and Conversion Modes to remain visible and easy to find without interrupting the permissions/microphone top section

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] StubCalibrationSampleCapturer infinite loop on exhaustion**
- **Found during:** Task 1 (AssistantCalibrationRunnerTests)
- **Issue:** Original stub returned `nil` after exhausting results; `runSession()` loop treated nil as retry and spun forever, causing `testDoesNotCompleteBeforeThreeAcceptedSamples` to hang
- **Fix:** Introduced `CalibrationCapturingDone.exhausted` error; stub throws on exhaustion; runner exits cleanly via `catch is CalibrationCapturingDone { return }`
- **Files modified:** Speech2Text/Shell/AssistantCalibrationRunner.swift, Speech2TextTests/AssistantCalibrationRunnerTests.swift
- **Verification:** All 7 runner tests pass including the hang-prone incomplete-session test
- **Committed in:** `42dbd55` (Task 1 commit)

**2. [Rule 1 - Bug] ForEach TriggerNamePreset compile failure (missing Hashable)**
- **Found during:** Task 2 (AIAssistantSettingsView body)
- **Issue:** `TriggerNamePreset` is `Equatable` but not `Hashable`; `ForEach` with `id: \.self` required Hashable conformance causing compile errors
- **Fix:** Replaced `ForEach` loop with explicit `presetRow(for:)` calls for `.zeus`, `.atlas`, `.gaia`
- **Files modified:** Speech2Text/Shell/AIAssistantSettingsView.swift
- **Verification:** Build succeeded
- **Committed in:** `0c7ce6a` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 logic bug, 1 compile bug)
**Impact on plan:** Both fixes required for correctness and build success. No scope creep.

## Issues Encountered

- Background xcodebuild tasks did not write output to task files; resolved by running all test verifications inline
- `@StateObject` init with referenced `preferences` parameter not accessible in SwiftUI property defaults; resolved by creating `AIAssistantSettingsViewModel` inline at sheet presentation callsite

## Next Phase Readiness

- AI Assistant tile, sheet, and calibration runner are fully implemented and test-backed
- All production types export stable accessibility identifiers for Phase 15-02 end-to-end automation
- `CalibrationSampleCapturing` protocol ready for real `AudioCaptureService`-based implementation in 15-02
