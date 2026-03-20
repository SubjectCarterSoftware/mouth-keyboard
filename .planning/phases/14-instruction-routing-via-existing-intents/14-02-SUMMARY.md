---
phase: 14-instruction-routing-via-existing-intents
plan: 02
subsystem: routing
tags: [trigger-routing, intent-detection, llm-rewrite, regression-tests]
requires:
  - phase: 14-01
    provides: conservative predefined shortcut detection for post-trigger instructions
provides:
  - valid-trigger unresolved built-in instructions now route through custom instruction rewrite
  - built-in shortcut winners remain on predefined mode pipeline
  - guard/fallback regressions lock 350-word gate and silent LLM failure behavior for trigger routes
affects: [activationstore, trigger-routing, conversion-guards]
tech-stack:
  added: []
  patterns: ["valid-trigger split routing: built-in winner first, instruction-text fallback second"]
key-files:
  created: []
  modified:
    - Speech2Text/Activation/ActivationStore.swift
    - Speech2TextTests/ActivationStoreTests.swift
    - Speech2TextTests/IntentDetectorTests.swift
key-decisions:
  - "Use ConvertIntent.effectiveSystemPrompt to carry post-trigger instruction text into rewrite(body:instructions:) fallback."
  - "Preserve existing custom-intent definition routing when matched; only unresolved valid-trigger cases use instruction-text fallback."
patterns-established:
  - "Trigger fallback pattern: built-in shortcut detection failure no longer implies passthrough for validTrigger."
requirements-completed: [ROUTE-01, ROUTE-02, ROUTE-03, ROUTE-04]
duration: 7 min
completed: 2026-03-20
---

# Phase 14 Plan 02: Instruction Routing via Existing Intents Summary

**Valid-trigger transcripts now route unresolved built-in instructions through custom rewrite instructions while preserving predefined shortcut wins and guard/fallback contracts.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-20T16:52:00Z
- **Completed:** 2026-03-20T16:59:01Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Added RED/green integration coverage for trigger-route custom fallback, trigger-route word-limit enforcement, and silent rewrite-failure fallback behavior.
- Updated `ActivationStore.finalizeSession` valid-trigger routing to use `content` as rewrite body and instruction text as custom instructions when no built-in shortcut wins.
- Kept built-in shortcut winners on the existing predefined mode path and preserved no-trigger/invalid-trigger passthrough behavior.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add RED integration tests for valid-trigger custom fallback and guard preservation** - `9e91570` (test)
2. **Task 2: Implement ActivationStore custom instruction fallback for unresolved valid-trigger instructions** - `d35993c` (feat)

## Files Created/Modified
- `Speech2TextTests/ActivationStoreTests.swift` - Added trigger-route regressions for unresolved built-in fallback, word-limit gate, and silent-fallback behavior.
- `Speech2TextTests/IntentDetectorTests.swift` - Strengthened unresolved built-in detector passthrough coverage with candidate-signal assertions.
- `Speech2Text/Activation/ActivationStore.swift` - Implemented valid-trigger custom instruction fallback routing and effective instruction resolution in rewrite path.

## Decisions Made
- Reused `ConvertIntent.effectiveSystemPrompt` as the explicit per-session instruction carrier for unresolved valid-trigger fallback.
- Preserved existing custom-intent definition detection path to avoid regressing user-defined mode routing while adding instruction-text fallback.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Cleared stale `.git/index.lock` during staged task commit**
- **Found during:** Task 1 commit staging
- **Issue:** Parallel `git add` calls created lock contention and blocked staging.
- **Fix:** Removed stale lock and re-ran staging sequentially.
- **Files modified:** none
- **Verification:** Commit completed successfully for Task 1.
- **Committed in:** `9e91570`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No scope impact; execution flow restored immediately.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 14 plans are now complete (`14-01` and `14-02` summaries present).
- Ready for roadmap transition to the next planned phase.

---
*Phase: 14-instruction-routing-via-existing-intents*
*Completed: 2026-03-20*

## Self-Check: PASSED
- Verified summary file exists.
- Verified task commits exist: `9e91570`, `d35993c`.
