---
phase: 14-instruction-routing-via-existing-intents
plan: 01
subsystem: api
tags: [swift, intent-routing, activationstore, tests]
requires:
  - phase: 13-last-name-wins-parser-integration
    provides: trigger-segmented validTrigger instruction parsing in ActivationStore finalize
provides:
  - Conservative trailing-only predefined shortcut resolver for post-trigger instructions
  - Deterministic ambiguity fallback that avoids forced built-in routing
  - ActivationStore integration using predefined-first routing with preserved custom-intent fallback
affects: [14-02 fallback routing, intent detection behavior, finalize conversion path]
tech-stack:
  added: []
  patterns: [trailing-only built-in shortcut gating, exact multi-command ambiguity rejection]
key-files:
  created: [.planning/phases/14-instruction-routing-via-existing-intents/14-01-SUMMARY.md]
  modified:
    - Speech2Text/Conversion/IntentDetector.swift
    - Speech2Text/Activation/ActivationStore.swift
    - Speech2TextTests/IntentDetectorTests.swift
    - Speech2TextTests/ActivationStoreTests.swift
key-decisions:
  - "Use a dedicated detectPredefinedShortcut path for valid-trigger built-ins instead of changing general detector semantics."
  - "Reject ambiguous built-in routing when multiple exact built-in commands are present in the post-trigger instruction."
  - "Preserve custom-intent detection as fallback when no predefined built-in shortcut is selected."
patterns-established:
  - "Post-trigger built-in shortcuts must be end-qualified to route conversion."
  - "Non-exact built-in fuzzy shortcut matches require keyword-signal presence to avoid custom-command false positives."
requirements-completed: [ROUTE-01, ROUTE-02, ROUTE-03, ROUTE-04]
duration: 8min
completed: 2026-03-20
---

# Phase 14 Plan 01: Instruction Routing via Existing Intents Summary

**Deterministic post-trigger shortcut routing now selects built-in intents only for clear trailing commands while ambiguous/mixed instructions avoid forced built-in conversion.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-20T16:43:29Z
- **Completed:** 2026-03-20T16:50:58Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added RED corpus for conservative trailing-only built-in shortcut routing and ambiguous/mixed fallback behavior.
- Implemented `IntentDetector.detectPredefinedShortcut` with end-position gating and explicit multi-command ambiguity rejection.
- Wired `ActivationStore.finalizeSession` valid-trigger handling to predefined-first routing while preserving custom-intent fallback behavior.
- Updated scoped activation fixtures to trailing-command phrasing where conversion is expected under Phase 14 policy.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add RED corpus for conservative trailing shortcut resolution and ambiguity fallback** - `50405cd` (test)
2. **Task 2: Implement conservative predefined shortcut resolver and wire valid-trigger routing to it** - `201ad78` (feat)

## Files Created/Modified

- `.planning/phases/14-instruction-routing-via-existing-intents/14-01-SUMMARY.md` - execution summary and traceability
- `Speech2Text/Conversion/IntentDetector.swift` - conservative predefined shortcut resolver and scoring safeguards
- `Speech2Text/Activation/ActivationStore.swift` - valid-trigger predefined-first routing integration with custom fallback
- `Speech2TextTests/IntentDetectorTests.swift` - phase-14 policy corpus targeting predefined shortcut resolver
- `Speech2TextTests/ActivationStoreTests.swift` - finalize-path expectations for trailing shortcut policy

## Decisions Made

- Introduced a separate predefined shortcut detector for post-trigger routing to keep existing broad detector behavior stable for non-phase-14 paths.
- Treated multiple exact built-in commands in one instruction as ambiguous to prevent deterministic but incorrect forced mode selection.
- Required keyword-signal presence for non-exact built-in shortcut matches to prevent false positives on custom-intent command text.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Built-in fuzzy false positives on custom command phrases**
- **Found during:** Task 2 (conservative predefined resolver implementation)
- **Issue:** Non-exact built-in fuzzy scoring could classify custom command phrasing as a built-in route.
- **Fix:** Required built-in keyword signal presence for non-exact predefined shortcut candidates.
- **Files modified:** `Speech2Text/Conversion/IntentDetector.swift`
- **Verification:** `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -only-testing Speech2TextTests/IntentDetectorTests -only-testing Speech2TextTests/ActivationStoreTests -destination 'platform=macOS'`
- **Committed in:** `201ad78` (part of Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Auto-fix was required to satisfy conservative routing without regressing custom-intent behavior.

## Issues Encountered

- Initial tie-rejection logic was too aggressive for clear trailing commands; narrowed ambiguity handling to explicit exact multi-command cases.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Valid-trigger predefined shortcut routing is deterministic and conservative for built-ins.
- Ambiguous and mixed instructions are preserved on non-forced paths, ready for 14-02 fallback behavior work.

---
*Phase: 14-instruction-routing-via-existing-intents*
*Completed: 2026-03-20*

## Self-Check: PASSED

- FOUND: `.planning/phases/14-instruction-routing-via-existing-intents/14-01-SUMMARY.md`
- FOUND: `50405cd`
- FOUND: `201ad78`
