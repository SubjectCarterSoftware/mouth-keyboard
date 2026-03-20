---
phase: 09-activationstore-integration-and-guards
plan: 02
subsystem: ui
tags: [swift, swiftui, recordingstate, recordingpillview, statusmenuview, appdelegate, activationstore]

# Dependency graph
requires:
  - phase: 09-activationstore-integration-and-guards/09-01
    provides: RecordingState.converting + .wordLimitExceeded + success(converted:Bool) + ActivationStore.lastConvertedTranscription + copyLastConvertedTranscription()
provides:
  - RecordingPillView convertingContent (blue scale-animated dots, visually distinct from processing)
  - RecordingPillView successContent(pasted:converted:) with 4-label matrix
  - RecordingPillView failureBackground(for:) — orange for .wordLimitExceeded, red for all others
  - AppDelegate.onConvertingStarted() dedicated method + separate .converting case in stateObservation sink
  - StatusMenuView lastConvertedTranscription param + 'Copy Last AI Converted Transcription' menu item (disabled when nil)
  - Speech2TextApp threads lastConvertedTranscription and copyLastConvertedTranscription from ActivationStore
affects:
  - 10-model-download-and-progress (downstream StatusMenuView consumers)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-reason failure background color via failureBackground(for:) helper — isolates future failure color changes"
    - "Always-present menu item with .disabled(condition) modifier — avoids conditional rendering for accessibility"
    - "convertingContent reuses @State pulseOpacity from processingContent but differs by color (blue vs white) and animation type (scale vs opacity)"

key-files:
  created: []
  modified:
    - Speech2Text/Shell/RecordingPillView.swift
    - Speech2Text/App/AppDelegate.swift
    - Speech2Text/Shell/StatusMenuView.swift
    - Speech2Text/App/Speech2TextApp.swift

key-decisions:
  - "convertingContent uses scale animation (scaleEffect toggled by pulseOpacity) while processingContent uses opacity animation — same @State var, different visual treatment for clear distinction"
  - "failureBackground(for:) helper pattern isolates color-per-reason logic — easy to extend for future failure types"
  - "StatusMenuView 'Copy Last AI Converted Transcription' is always-present with .disabled modifier (not conditionally hidden) — matches CONTEXT.md spec for consistent menu layout"
  - "onConvertingStarted() is a dedicated method (not merged with onProcessingStarted()) — cleaner for future icon differentiation if needed"

patterns-established:
  - "Per-state failure styling: failureBackground(for:) pattern can be extended for any FailureReason that needs distinct visual treatment"
  - "Menu item always-present + .disabled pattern for copy actions that depend on optional state"

requirements-completed: [LLM-02, GUARD-01, UX-01]

# Metrics
duration: 8min
completed: 2026-03-19
---

# Phase 9 Plan 02: UI Layer Update for Converting State Summary

**UI layer rendering for RecordingState.converting (blue scale-animated dots), .wordLimitExceeded (orange pill), extended successContent (4 text variants), and new 'Copy Last AI Converted Transcription' menu item**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-19T20:42:06Z
- **Completed:** 2026-03-19T20:50:10Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- RecordingPillView: `.converting` renders blue scale-animated dots distinct from processing's white opacity-animated dots; `.wordLimitExceeded` shows orange background; successContent handles all 4 converted/pasted text combinations
- AppDelegate: `.converting` has dedicated `onConvertingStarted()` method; state sink split from merged `.processing, .converting` case into separate cases
- StatusMenuView + Speech2TextApp: `lastConvertedTranscription` and `copyLastConvertedTranscription` threaded end-to-end; "Copy Last AI Converted Transcription" menu item always present, disabled when nil

## Task Commits

Each task was committed atomically:

1. **Task 1: Update RecordingPillView — .converting animation, .wordLimitExceeded orange, extended successContent** - `2ac8025` (feat)
2. **Task 2: Update RecordingPillPanel and AppDelegate — .converting exhaustiveness** - `f23af40` (feat)
3. **Task 3: Wire StatusMenuView and Speech2TextApp — new menu item and parameter threading** - `1ef532e` (feat)

## Files Created/Modified
- `Speech2Text/Shell/RecordingPillView.swift` - Added convertingContent, failureBackground(for:), updated successContent(pasted:converted:), updated failureMessage for .wordLimitExceeded
- `Speech2Text/App/AppDelegate.swift` - Separated .converting into dedicated onConvertingStarted() method
- `Speech2Text/Shell/StatusMenuView.swift` - Added lastConvertedTranscription + copyLastConvertedTranscription properties + 'Copy Last AI Converted Transcription' Button
- `Speech2Text/App/Speech2TextApp.swift` - Threaded lastConvertedTranscription and copyLastConvertedTranscription from ActivationStore to StatusMenuView

## Decisions Made
- `convertingContent` reuses existing `@State private var pulseOpacity: Double` but drives `scaleEffect` (not opacity) — same animation trigger, different visual effect for clear distinction from processing dots
- `failureBackground(for:)` extracted as a helper rather than inline `if-else` inside `failureContent` — easier to extend for future FailureReason color mappings
- "Copy Last AI Converted Transcription" is always present in the menu (using `.disabled` modifier) per the CONTEXT.md spec — avoids layout shift when lastConvertedTranscription transitions between nil and non-nil
- `onConvertingStarted()` is a dedicated method (not merged with `onProcessingStarted()`) — the method only calls `updateMenuBarIcon(state: .converting)` since audio is already stopped; separated for clarity and future icon differentiation

## Deviations from Plan

None — plan executed exactly as written. RecordingPillPanel's `default:` arm already correctly maps `.converting` to `defaultSize` (160x44); confirmed no change needed.

## Issues Encountered
Pre-existing test failures (not caused by this plan):
- `HotkeyServiceTests.testDefaultActivationShortcutIsControlV` — documented in STATE.md, out of scope
- `ShellPreferencesModelTests.testLaunchAtLoginDefaultsToFalse` — documented in STATE.md, out of scope
- `MenuBarShellSmokeTests` and `PermissionRecoveryFlowTests` UI tests (7 tests) — pre-existing failures confirmed via stash test; rely on unimplemented launch argument features not part of this phase

All 25 ActivationStoreTests pass. Zero build errors.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 9 complete: all data model + behavior + UI rendering changes are done
- `.converting` state is fully handled end-to-end: ActivationStore transitions, AppDelegate icon update, pill animation, menu bar status
- `lastConvertedTranscription` and `copyLastConvertedTranscription` are wired from ActivationStore to the menu
- Phase 10 (Model Download and Progress) can consume the complete RecordingState shape with confidence

---
*Phase: 09-activationstore-integration-and-guards*
*Completed: 2026-03-19*
