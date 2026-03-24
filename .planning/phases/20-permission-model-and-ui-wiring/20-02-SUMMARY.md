---
phase: 20-permission-model-and-ui-wiring
plan: 02
subsystem: ui
tags: [swiftui, permissions, input-monitoring, macos]

# Dependency graph
requires:
  - phase: 20-permission-model-and-ui-wiring (plan 01)
    provides: "PermissionKind.holdToTranscribe case, ReadinessStore keyboard wiring, KeyboardPermissionService"
provides:
  - "InputMonitoringSetupGuide view in PermissionChecklistView"
  - "HoldToTranscribeRow rewired to KeyboardPermissionService"
  - "Feature-oriented labels replacing Accessibility wording"
  - "PermissionTile popover routing for .holdToTranscribe kind"
affects: [ui-tests, permission-checklist, setup-window]

# Tech tracking
tech-stack:
  added: []
  patterns: [kind-based popover routing in PermissionTile]

key-files:
  created: []
  modified:
    - Speech2Text/Shell/PermissionChecklistView.swift
    - Speech2Text/Shell/SetupWindowView.swift

key-decisions:
  - "InputMonitoringSetupGuide follows same structure as AccessibilitySetupGuide with Input Monitoring wording"
  - "PermissionTile uses Group + conditional to route .holdToTranscribe vs .postEvent to different guides"
  - "HoldToTranscribeRow renamed showsAccessibilityGuide → showsSetupGuide for semantic clarity"

patterns-established:
  - "Kind-based popover routing: PermissionTile dispatches to guide views based on item.kind"

requirements-completed: [HTT-01, HTT-02, HTT-04, HTT-05, HTT-09]

# Metrics
duration: 2min
completed: 2026-03-24
---

# Phase 20 Plan 02: UI Wiring Summary

**InputMonitoringSetupGuide created and HoldToTranscribeRow rewired to KeyboardPermissionService with feature-oriented labels**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-24T18:25:59Z
- **Completed:** 2026-03-24T18:27:28Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created InputMonitoringSetupGuide view with locked CONTEXT.md wording (headline, steps, button, frame)
- Updated PermissionTile popover routing to show correct guide based on permission kind
- Rewired HoldToTranscribeRow to KeyboardPermissionService for Input Monitoring status
- Replaced all Accessibility-oriented labels with feature-oriented wording (keyboard access)
- Recovery now targets .holdToTranscribe → Privacy > Input Monitoring pane

## Task Commits

Each task was committed atomically:

1. **Task 1: Create InputMonitoringSetupGuide and update PermissionTile popover routing** - `0818dbc` (feat)
2. **Task 2: Rewire HoldToTranscribeRow and SetupWindowView to use KeyboardPermissionService** - `291ec0b` (feat)

## Files Created/Modified
- `Speech2Text/Shell/PermissionChecklistView.swift` - Added InputMonitoringSetupGuide view; updated PermissionTile button action and popover routing for .holdToTranscribe
- `Speech2Text/Shell/SetupWindowView.swift` - Added keyboardPermissionService; rewired holdToTranscribeStatus, requestHoldToTranscribeAccess, HoldToTranscribeRow labels and popover

## Decisions Made
- InputMonitoringSetupGuide mirrors AccessibilitySetupGuide structure but with Input Monitoring content from locked CONTEXT.md decisions
- PermissionTile uses Group + conditional ViewBuilder to dispatch to correct guide based on item.kind
- Renamed `showsAccessibilityGuide` → `showsSetupGuide` in HoldToTranscribeRow for semantic accuracy

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Hold to Transcribe UI fully rewired to Input Monitoring permission
- All user-facing labels reference keyboard access / Hold to Transcribe (no Accessibility references)
- Ready for UI test updates to assert corrected strings

---
*Phase: 20-permission-model-and-ui-wiring*
*Completed: 2026-03-24*

## Self-Check: PASSED
