---
phase: 04-recovery-controls
plan: 01
subsystem: ui
tags: [macos, swiftui, recovery, keyboard-monitoring, clipboard, xctest]
requires:
  - phase: 03-recognition-and-clipboard-loop
    provides: finish-to-transcription flow, clipboard success path, pill state rendering
provides:
  - explicit cancel and restart session controls owned by ActivationStore
  - background Escape cancellation via the session-key interception path
  - menu and pill recovery confirmation without opening a new window
affects: [04-02, phase-05-long-dictation-reliability, recovery-ui, clipboard-safety]
tech-stack:
  added: []
  patterns: [session-token invalidation for stale async work, menu-first recovery controls, transient recovery feedback]
key-files:
  created: []
  modified:
    - Speech2Test/Activation/ActivationStore.swift
    - Speech2Test/Activation/RecordingState.swift
    - Speech2Test/Activation/SpacebarInterceptor.swift
    - Speech2Test/App/AppDelegate.swift
    - Speech2Test/App/Speech2TestApp.swift
    - Speech2Test/Permissions/KeyboardPermissionService.swift
    - Speech2Test/Readiness/ReadinessSnapshot.swift
    - Speech2Test/Shell/RecordingPillView.swift
    - Speech2Test/Shell/RecordingPillPanel.swift
    - Speech2Test/Shell/StatusMenuView.swift
    - Speech2TestTests/ActivationStoreTests.swift
    - Speech2TestTests/PermissionServiceTests.swift
    - Speech2TestTests/SpacebarInterceptorTests.swift
    - Speech2TestUITests/PermissionRecoveryFlowTests.swift
    - Speech2TestUITests/MenuBarShellSmokeTests.swift
key-decisions:
  - "Recovery feedback is modeled alongside RecordingState so restart can stay in recording while still showing transient confirmation."
  - "Literal Escape cancel uses the event-tap session-key path and surfaces keyboard-monitoring readiness instead of silently assuming the hotkey permission model is enough."
  - "Recovery actions remain menu-driven in Phase 4, with the pill limited to visual confirmation to avoid adding new focus or input risk."
patterns-established:
  - "Session invalidation before async completion prevents late transcription from mutating state or clipboard after cancel/restart."
  - "Idle transitions are teardown boundaries: audio capture stops and silence callbacks are cleared whenever recovery lands back at idle."
requirements-completed: [SESS-02, SESS-03, SESS-04, CLIP-02]
duration: 6min
completed: 2026-03-08
---

# Phase 4 Plan 01: Recovery Controls Summary

**Explicit cancel/restart recovery with background Escape cancellation, stale-result suppression, and menu-plus-pill confirmation for safe clipboard-preserving session recovery**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-08T14:08:00Z
- **Completed:** 2026-03-08T14:13:53Z
- **Tasks:** 4
- **Files modified:** 15

## Accomplishments
- Added store-owned cancel and restart session orchestration that invalidates in-flight transcription work and preserves the clipboard on recovery paths.
- Extended the existing session-key path to support live background `Escape` cancellation with explicit keyboard-monitoring readiness handling.
- Added menu recovery controls and transient pill/menu confirmation so canceled and restarted sessions stay visible without opening a new surface.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add store-owned cancel/restart recovery orchestration and stale-result suppression** - `2981c85` (feat)
2. **Task 2: Generalize the session-key path and make literal Escape dependencies explicit** - `fd888a4` (feat)
3. **Task 3: Add menu recovery affordances and transient cancel/restart confirmation UI** - `87f9c2d` (feat)
4. **Task 4: Human verification for live cancel and restart behavior** - Approved at checkpoint continuation; no code changes required

## Files Created/Modified
- `Speech2Test/Activation/ActivationStore.swift` - Explicit cancel/restart APIs, session invalidation, and stale-result suppression.
- `Speech2Test/Activation/SpacebarInterceptor.swift` - Generalized session-key handling for finish and cancel.
- `Speech2Test/App/AppDelegate.swift` - Live session-key wiring and teardown on idle transitions.
- `Speech2Test/Shell/StatusMenuView.swift` - Menu-first cancel/restart actions and recovery copy.
- `Speech2Test/Shell/RecordingPillView.swift` - Transient canceled/restarted feedback rendering.
- `Speech2TestTests/ActivationStoreTests.swift` - Cancel/restart and clipboard-safety regression coverage.
- `Speech2TestUITests/MenuBarShellSmokeTests.swift` - Menu smoke coverage for recovery affordances and indicator-hidden fallback.

## Decisions Made
- Kept `RecordingState` focused on lifecycle while publishing recovery feedback separately so restart can remain in `.recording`.
- Reused the existing keyboard permission/readiness surfaces for literal `Escape` requirements rather than inventing a separate product-facing permission concept.
- Limited Phase 4 interaction changes to menu actions plus passive pill feedback; no clickable pill controls were introduced.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- UI automation covers the menu affordances and indicator-hidden fallback, but it does not fully prove live background `Escape` behavior or animation-sensitive pill timing. Those behaviors remain intentionally covered by the approved human-verification checkpoint.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 4 plan 01 is complete and ready for plan `04-02`, which can focus on microphone failure handling and remaining clipboard-integrity hardening.
- The approved checkpoint confirms the live cancel/restart scenarios; no open blocker remains from this plan.

## Self-Check: PASSED
- Verified summary file exists on disk.
- Verified task commits `2981c85`, `fd888a4`, and `87f9c2d` exist in git history.

---
*Phase: 04-recovery-controls*
*Completed: 2026-03-08*
