---
phase: 05-long-dictation-reliability
plan: 02
subsystem: transcription
tags: [swift, whisper, menu-bar, dictation, xctest, xcuittest]
requires:
  - phase: 05-01
    provides: queued segment sealing, long-session companion status, and deterministic segment boundaries
provides:
  - ordered multi-segment transcript assembly independent of completion order
  - one clipboard barrier for long sessions with best-effort partial-failure handling
  - persistent menu status and incomplete-result warnings for long dictation
affects: [05-03, ActivationStore, StatusMenuView, MenuBarShellSmokeTests]
tech-stack:
  added: []
  patterns:
    - finish-time assembly barrier for long dictation
    - companion incomplete-result notice outside clipboard text
    - status-window UI smoke injection for menu-bar content
key-files:
  created:
    - Speech2Test/Activation/LongDictationAssembler.swift
    - Speech2TestTests/TranscriptAssemblerTests.swift
  modified:
    - Speech2Test/Activation/ActivationStore.swift
    - Speech2Test/Activation/LongDictationSession.swift
    - Speech2Test/App/AppDelegate.swift
    - Speech2Test/App/Speech2TestApp.swift
    - Speech2Test/Shell/StatusMenuView.swift
    - Speech2TestTests/ActivationStoreTests.swift
    - Speech2TestUITests/MenuBarShellSmokeTests.swift
    - Speech2Test.xcodeproj/project.pbxproj
key-decisions:
  - "Start long-session segment transcription as segments seal, but keep clipboard writes gated behind finish-time assembly."
  - "Persist incomplete long-session results as companion menu notices so clipboard text stays clean best-effort prose."
  - "Exercise StatusMenuView through the existing status test window instead of the real MenuBarExtra for deterministic UI smoke coverage."
patterns-established:
  - "Queued assembly: settle all current-segment transcription tasks, then sort by stable segment index before joining prose."
  - "Partial failure UX: successful segments still win, while omitted-segment counts stay in menu companion state."
  - "Menu verification: inject shell-only long-session states through AppDelegate's UI-testing status window hook."
requirements-completed: [TRNS-04, TRNS-05]
duration: 16m
completed: 2026-03-08
---

# Phase 5 Plan 2: Long Dictation Finalization Summary

**Ordered long-dictation assembly with one final clipboard write and persistent menu warnings for incomplete results**

## Performance

- **Duration:** 16 min
- **Started:** 2026-03-08T20:13:48Z
- **Completed:** 2026-03-08T20:29:48Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments
- Added a dedicated `LongDictationAssembler` that trims, normalizes, orders, and joins queued segment transcripts by stable index.
- Refactored `ActivationStore.finish()` into a true long-session barrier that seals remaining audio, waits for queued segment work, and writes to the clipboard exactly once on best-effort success.
- Threaded long-session processing and incomplete-result notices into the menu surface, with stable accessibility identifiers and smoke coverage for hidden-indicator mode.

## Task Commits

Each task was committed atomically:

1. **Task 1: Settle queued segment transcription work and assemble one final transcript** - `4893f61` (feat)
2. **Task 2: Surface persistent long-session finalization and incompleteness status in the menu** - `1c4c634` (feat)

**Plan metadata:** Pending final docs/state commit at summary creation time.

## Files Created/Modified
- `Speech2Test/Activation/LongDictationAssembler.swift` - ordered best-effort transcript assembly and count reporting.
- `Speech2Test/Activation/ActivationStore.swift` - queued segment transcription orchestration, finalization barrier, and incomplete-result notice publication.
- `Speech2Test/Activation/LongDictationSession.swift` - companion incomplete-result notice model for the shell.
- `Speech2Test/App/Speech2TestApp.swift` - long-session companion state plumbing into the menu surface.
- `Speech2Test/Shell/StatusMenuView.swift` - persistent long-session status and warning rendering with stable accessibility identifiers.
- `Speech2Test/App/AppDelegate.swift` - UI-testing status-window overrides for deterministic menu smoke coverage.
- `Speech2TestTests/ActivationStoreTests.swift` - final clipboard barrier, partial failure, all-failure, and stale completion regression coverage.
- `Speech2TestTests/TranscriptAssemblerTests.swift` - direct assembly coverage for ordering, whitespace normalization, and failure counting.
- `Speech2TestUITests/MenuBarShellSmokeTests.swift` - hidden-indicator status and incomplete-warning smoke tests.
- `Speech2Test.xcodeproj/project.pbxproj` - build graph updates for the new assembler and test target file.

## Decisions Made
- Long-session segments can transcribe as they are sealed, but only `finish()` is allowed to convert that work into a clipboard write.
- All partial-failure metadata stays in companion shell state, not in pasted text, so the clipboard output remains seamless prose.
- Menu smoke tests use the existing status-window harness with launch-argument overrides instead of trying to automate the live menu bar extra.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added status-window launch overrides in `AppDelegate` for menu smoke coverage**
- **Found during:** Task 2 (Surface persistent long-session finalization and incompleteness status in the menu)
- **Issue:** `MenuBarShellSmokeTests` could not reliably inspect the real macOS `MenuBarExtra`, so the new long-session status identifiers had no deterministic automation path.
- **Fix:** Extended the existing UI-testing status-window hook in `AppDelegate` with long-session state and warning launch overrides, then exercised `StatusMenuView` through that path.
- **Files modified:** `Speech2Test/App/AppDelegate.swift`, `Speech2TestUITests/MenuBarShellSmokeTests.swift`
- **Verification:** `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestUITests/MenuBarShellSmokeTests -destination 'platform=macOS'`
- **Committed in:** `1c4c634` (part of Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The deviation stayed within the planned UI verification scope and only added the deterministic test harness needed to automate the requested smoke coverage.

## Issues Encountered
- The first UI smoke pass over-asserted on dynamic status copy. The identifiers were present, so the assertions were narrowed to the accessibility contract the plan actually required.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Long-session output now settles into ordered best-effort prose with one clipboard barrier and menu-visible incomplete-result warnings.
- Phase `05-03` can build on a stable finalization surface without revisiting clipboard-safety or menu discoverability basics.

## Self-Check: PASSED

- FOUND: `.planning/phases/05-long-dictation-reliability/05-02-SUMMARY.md`
- FOUND: `4893f61`
- FOUND: `1c4c634`
