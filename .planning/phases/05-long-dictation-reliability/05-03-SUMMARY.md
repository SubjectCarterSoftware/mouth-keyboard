---
phase: 05-long-dictation-reliability
plan: 03
subsystem: testing
tags: [swift, xctest, xcuittest, whisper, dictation, macos]
requires:
  - phase: 05-01
    provides: sealed-segment queueing and deterministic threshold/pause/soft-cap boundaries
  - phase: 05-02
    provides: ordered long-session assembly, incomplete-result notices, and menu status surfaces
provides:
  - long-session flow coverage for multi-segment success, spoken-order assembly, soft-cap sealing, partial failure, all-failure, and short-session regressions
  - deterministic UI-testing failure injection through a long-session segment launch flag
  - verified hotkey re-entry reliability immediately after terminal long-session feedback
affects: [phase-closeout, ActivationStore, AppDelegate, LongDictationFlowTests, MenuBarShellSmokeTests]
tech-stack:
  added: []
  patterns:
    - integration-style long-session flow tests with mocked transcriber timing
    - ui-testing launch-argument failure injection for sealed segment transcription
    - terminal-state reactivation after long-session success or failure feedback
key-files:
  created:
    - Speech2TestTests/LongDictationFlowTests.swift
  modified:
    - Speech2Test/Activation/ActivationStore.swift
    - Speech2Test/App/AppDelegate.swift
    - Speech2TestTests/ActivationStoreTests.swift
    - Speech2TestUITests/MenuBarShellSmokeTests.swift
    - Speech2Test.xcodeproj/project.pbxproj
key-decisions:
  - "Cover long-session reliability with integration-style ActivationStore tests that exercise real queue-settlement behavior instead of building a second verification-only path."
  - "Drive partial-failure verification through a non-production launch flag so UI and manual checks can force a chosen sealed segment to fail deterministically."
  - "Allow ActivationStore re-arming from terminal success or failure feedback while continuing to block activation during in-flight processing."
patterns-established:
  - "Long-session matrix: assert success, out-of-order completion, soft-cap preservation, partial failure, all-failure, and short-session fallback in one focused regression suite."
  - "Verification plumbing: AppDelegate translates UI-testing launch arguments into ActivationStore fault injection and menu warning state."
  - "Hotkey recovery: terminal feedback is interruptible by a new recording request, but processing remains non-interruptible."
requirements-completed: [TRNS-03, TRNS-04, TRNS-05]
duration: 37m
completed: 2026-03-08
---

# Phase 5 Plan 3: Long-Dictation Reliability Verification Summary

**Long-session regression coverage, deterministic failure injection, and verified hotkey re-entry after successful long dictation**

## Performance

- **Duration:** 37 min
- **Started:** 2026-03-09T00:30:11Z
- **Completed:** 2026-03-09T01:07:14Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Added `LongDictationFlowTests` to prove multi-segment settlement, spoken-order assembly, soft-cap preservation, partial failure, all-failure no-clipboard behavior, and the short-session fallback path.
- Added deterministic `-ui-testing-long-session-fail-segment <index>` plumbing so UI smoke tests and manual verification can force one sealed segment to fail without changing production behavior.
- Closed a real post-checkpoint reliability gap where the hotkey could not immediately start a new session while terminal long-session success feedback was still visible.
- Completed the human verification checkpoint for natural-pause dictation, continuous-speech soft-cap handling, hidden-indicator persistent status, and partial-failure warning visibility.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the long-session regression matrix and close any targeted reliability gaps it reveals** - `1346a21` (feat), `9460be4` (fix)
2. **Task 2: Human verification of long-session capture, soft-cap behavior, and persistent warning visibility** - approved during checkpoint (no code commit)

**Plan metadata:** Pending final docs/state commit at summary creation time.

## Files Created/Modified
- `Speech2TestTests/LongDictationFlowTests.swift` - integration-style long-session regression matrix using mocked transcriber timing and deterministic queued segments.
- `Speech2Test/Activation/ActivationStore.swift` - UI-testing segment-failure injection plus terminal-state re-arming so hotkey reuse works immediately after long-session completion.
- `Speech2Test/App/AppDelegate.swift` - launch-argument parsing for long-session failure injection and derived warning overrides in the status-window test harness.
- `Speech2TestTests/ActivationStoreTests.swift` - regression coverage for immediate reactivation after long-session success feedback.
- `Speech2TestUITests/MenuBarShellSmokeTests.swift` - smoke coverage for the launch-flag-driven long-session warning identifier.
- `Speech2Test.xcodeproj/project.pbxproj` - build graph update for the new long-session flow test target entry.

## Decisions Made
- Kept the verification path inside `ActivationStore` and `AppDelegate` so the suite exercises the same queueing/finalization seams production uses.
- Forced manual and UI partial-failure verification through a test-only segment index flag rather than embedding failure markers in clipboard text or adding extra shell state.
- Treated terminal `.success` and `.failure` states as safe to interrupt with a new `arm()` call, while preserving the processing-state activation guard.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Allow hotkey re-entry during terminal long-session feedback**
- **Found during:** Task 2 (Human verification of long-session capture, soft-cap behavior, and persistent warning visibility)
- **Issue:** After a successful long dictation session, pressing the hotkey again before auto-dismiss completed left `ActivationStore` in terminal success feedback instead of starting a fresh recording, which matched the reported post-completion freeze.
- **Fix:** Updated `ActivationStore.arm()` to allow reactivation from terminal success/failure states and added a regression covering long-session success followed by immediate restart.
- **Files modified:** `Speech2Test/Activation/ActivationStore.swift`, `Speech2TestTests/ActivationStoreTests.swift`
- **Verification:** `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -destination 'platform=macOS'` plus human re-test of the original long-dictation hotkey flow
- **Committed in:** `9460be4` (post-checkpoint fix)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** The fix stayed within the planned reliability scope and closed a real long-session workflow regression surfaced by the human checkpoint.

## Issues Encountered
- Human verification exposed a lifecycle gap after successful long dictation: terminal feedback blocked immediate hotkey reuse and made the app appear stuck until auto-dismiss returned to idle. A targeted guard change in `ActivationStore.arm()` resolved it without altering in-flight processing behavior.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 5 exit criteria are satisfied: long sessions preserve early audio, assemble in spoken order, keep clipboard output best-effort clean under partial failure, and retain a persistent menu status surface when the indicator is hidden.
- The roadmap can mark Phase 5 complete, with the long-dictation regression suite now guarding both queued-segment correctness and immediate post-success re-entry.

## Self-Check: PASSED

- FOUND: `.planning/phases/05-long-dictation-reliability/05-03-SUMMARY.md`
- FOUND: `1346a21`
- FOUND: `9460be4`

---
*Phase: 05-long-dictation-reliability*
*Completed: 2026-03-08*
