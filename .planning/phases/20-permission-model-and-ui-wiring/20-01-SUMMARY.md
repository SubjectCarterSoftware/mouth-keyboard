---
phase: 20-permission-model-and-ui-wiring
plan: 01
subsystem: permissions
tags: [swift, permissions, input-monitoring, readiness, caseiterable]

# Dependency graph
requires:
  - phase: 01-foundation-and-permissions
    provides: PermissionKind enum, ReadinessSnapshot, ReadinessStore, KeyboardPermissionService
provides:
  - ".holdToTranscribe case in PermissionKind with Privacy_ListenEvent URL, Input Monitoring title, keyboard.fill icon"
  - "Feature-oriented .holdToTranscribe messages (authorized/notDetermined/denied)"
  - "Updated .postEvent messages referencing only Auto Paste"
  - "ReadinessSnapshot.derive() keyboardStatus parameter"
  - "ReadinessStore KeyboardPermissionService integration for init, refresh, requestPermission"
affects: [20-02-PLAN, setup-window-ui, permission-checklist-view]

# Tech tracking
tech-stack:
  added: []
  patterns: [three-permission CaseIterable ordering for tile layout, feature-oriented wording for permission messages]

key-files:
  created: []
  modified:
    - Speech2Text/Readiness/ReadinessSnapshot.swift
    - Speech2Text/Readiness/ReadinessStore.swift

key-decisions:
  - "CaseIterable order microphone → holdToTranscribe → postEvent ensures correct tile layout (Microphone → Input Monitoring → Auto Paste)"
  - ".holdToTranscribe uses feature-oriented wording (keyboard access, hold to record) not permission-name wording"
  - ".holdToTranscribe is isRequired: true — denied state triggers Setup Blocked"
  - ".postEvent messages decoupled from Hold to Transcribe — only reference Auto Paste"

patterns-established:
  - "Three-permission model: microphone, holdToTranscribe, postEvent in CaseIterable order"
  - "KeyboardPermissionService wiring follows same pattern as PostEventPermissionService (synchronous requestAccess)"

requirements-completed: [HTT-03, HTT-06, HTT-07, HTT-09]

# Metrics
duration: 1min
completed: 2026-03-24
---

# Phase 20 Plan 01: Permission Model Summary

**PermissionKind.holdToTranscribe with Privacy_ListenEvent URL, feature-oriented messages, and ReadinessStore wiring for keyboard permission**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-24T18:22:08Z
- **Completed:** 2026-03-24T18:23:10Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added `.holdToTranscribe` case to `PermissionKind` with correct CaseIterable ordering (microphone → holdToTranscribe → postEvent)
- Wired `KeyboardPermissionService` into `ReadinessStore` for init, refresh, and permission requests
- Updated all `.postEvent` messages to reference only Auto Paste — zero "Hold to Transcribe" mentions remain
- `derive()` now accepts `keyboardStatus` parameter and creates `.holdToTranscribe` checklist item with `isRequired: true`

## Task Commits

Each task was committed atomically:

1. **Task 1: Add .holdToTranscribe to PermissionKind and update derive()** - `aeeb32b` (feat)
2. **Task 2: Wire KeyboardPermissionService into ReadinessStore** - `023c6ff` (feat)

## Files Created/Modified
- `Speech2Text/Readiness/ReadinessSnapshot.swift` - Added .holdToTranscribe case with title, icon, settingsURL, messages; updated derive() signature and body
- `Speech2Text/Readiness/ReadinessStore.swift` - Added keyboardService property, updated shared/init/refresh/requestPermission

## Decisions Made
- CaseIterable order microphone → holdToTranscribe → postEvent ensures correct tile layout
- `.holdToTranscribe` uses feature-oriented wording ("keyboard access", "hold to record") per CONTEXT.md
- `.holdToTranscribe` marked as `isRequired: true` — denied state triggers "Setup Blocked"
- `.postEvent` messages decoupled from Hold to Transcribe — only reference Auto Paste

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- Plan 02 (UI wiring) can now consume `.holdToTranscribe` from the PermissionKind model
- `ReadinessStore` passes `keyboardStatus` to all derive() call sites
- Setup window and permission checklist views ready for UI integration in Plan 02

---
*Phase: 20-permission-model-and-ui-wiring*
*Completed: 2026-03-24*
