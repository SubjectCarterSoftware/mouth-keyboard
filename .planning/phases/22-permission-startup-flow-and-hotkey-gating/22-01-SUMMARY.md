---
phase: 22-permission-startup-flow-and-hotkey-gating
plan: 01
subsystem: permissions, ui
tags: [swift, swiftui, macos-permissions, input-monitoring, accessibility, enum-rename]

# Dependency graph
requires:
  - phase: 20-permission-model-and-ui-wiring
    provides: "PermissionKind enum with .holdToTranscribe case, PostEventPermissionService, ShellPreferences flags"
provides:
  - "PermissionKind.keyboardShortcuts enum case (renamed from .holdToTranscribe)"
  - "Updated user-facing strings: 'Keyboard Shortcuts' title, 'Ready — shortcuts enabled.' message"
  - "Accessibility auto-prompt at startup with 0.75s delay, guarded by hasRequestedPostEventPermission"
affects: [ui-tests, permission-recovery-flows, hotkey-gating]

# Tech tracking
tech-stack:
  added: []
  patterns: [delayed-permission-prompt, fire-once-guard-flag]

key-files:
  created: []
  modified:
    - Speech2Text/Readiness/ReadinessSnapshot.swift
    - Speech2Text/Readiness/ReadinessStore.swift
    - Speech2Text/Shell/SetupWindowView.swift
    - Speech2Text/Shell/PermissionChecklistView.swift
    - Speech2Text/App/AppDelegate.swift

key-decisions:
  - "Renamed .holdToTranscribe → .keyboardShortcuts since Input Monitoring gates all keyboard shortcuts, not just hold-to-transcribe"
  - "Auto-prompt uses 0.75s delay to avoid stacking with Input Monitoring dialog"
  - "Guard flag set before delayed block for crash safety"

patterns-established:
  - "Fire-once permission prompts: set guard flag before async block, not after"
  - "Delayed permission chaining: stagger permission dialogs with asyncAfter"

requirements-completed: [P22-RENAME, P22-STARTUP]

# Metrics
duration: 4min
completed: 2026-03-24
---

# Phase 22 Plan 01: Permission Rename and Startup Auto-Prompt Summary

**Renamed PermissionKind.holdToTranscribe → .keyboardShortcuts across model/UI layers and added Accessibility auto-prompt at startup with 0.75s delay**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-24T20:00:24Z
- **Completed:** 2026-03-24T20:04:28Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Renamed all PermissionKind.holdToTranscribe references to .keyboardShortcuts across 4 source files (25 occurrences)
- Updated user-facing strings: title "Keyboard Shortcuts", message "Ready — shortcuts enabled.", actions "Enable/Fix Keyboard Shortcuts", guide "How to enable Keyboard Shortcuts"
- Added Accessibility permission auto-prompt at startup with 0.75s delay after Input Monitoring, guarded by hasRequestedPostEventPermission flag
- ReadinessStore refreshes both immediately (Input Monitoring) and after delay (Accessibility)

## Task Commits

Each task was committed atomically:

1. **Task 1: Rename .holdToTranscribe → .keyboardShortcuts across all source files** - `5478679` (refactor)
2. **Task 2: Add Accessibility auto-prompt at startup with delay** - `52bb8f4` (feat)

## Files Created/Modified
- `Speech2Text/Readiness/ReadinessSnapshot.swift` - Renamed enum case, updated title/messages for keyboardShortcuts
- `Speech2Text/Readiness/ReadinessStore.swift` - Updated switch case from .holdToTranscribe to .keyboardShortcuts
- `Speech2Text/Shell/SetupWindowView.swift` - Renamed HoldToTranscribeRow → KeyboardShortcutsRow, updated all accessibility IDs and strings
- `Speech2Text/Shell/PermissionChecklistView.swift` - Updated tile routing and setup guide title for .keyboardShortcuts
- `Speech2Text/App/AppDelegate.swift` - Added postEventService property and delayed auto-prompt block

## Decisions Made
- Renamed .holdToTranscribe → .keyboardShortcuts since Input Monitoring gates all keyboard shortcuts, not just hold-to-transcribe
- Auto-prompt uses 0.75s delay to stagger behind Input Monitoring dialog
- Guard flag (hasRequestedPostEventPermission) set before delayed block for crash safety — ensures no re-prompting even if app crashes during prompt

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Permission model fully renamed — ready for UI test updates in subsequent phases
- Accessibility auto-prompt wired — startup flow complete
- HoldToTranscribeMonitor in HotkeyService.swift intentionally preserved (feature implementation, not permission reference)

---
*Phase: 22-permission-startup-flow-and-hotkey-gating*
*Completed: 2026-03-24*
