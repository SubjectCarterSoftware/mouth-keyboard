---
phase: 13-last-name-wins-parser-integration
plan: 01
subsystem: activation
tags: [parser, trigger-aliases, transcript-split]
requires:
  - phase: 12-calibration-contract-and-normalization
    provides: normalized active trigger aliases via TriggerAliasNormalizer and TriggerProfile
provides:
  - Pure trigger transcript parser with last-name-wins boundary selection
  - Typed split outcomes for no-trigger, valid-trigger, and short-instruction guard paths
  - RED/green parser corpus that locks boundary and non-activation semantics
affects: [activation-store-finalize, intent-routing-phase14]
tech-stack:
  added: []
  patterns: [pure parser + value-type split contract, boundary-safe alias matching]
key-files:
  created:
    - Speech2Text/Activation/TriggerTranscriptParser.swift
    - Speech2Text/Activation/TriggerTranscriptSplit.swift
    - Speech2TextTests/TriggerTranscriptParserTests.swift
  modified:
    - Speech2Text.xcodeproj/project.pbxproj
key-decisions:
  - "Parser normalizes aliases before matching and returns normalized matchedAlias values."
  - "Boundary matching uses whole-word regex checks to avoid substring activation (e.g. atlas in atlases)."
patterns-established:
  - "Parse-first contract: split transcript before downstream intent routing."
requirements-completed: [CAL-03, PARSE-01, PARSE-02, PARSE-03, PARSE-04, PARSE-05]
duration: 6 min
completed: 2026-03-20
---

# Phase 13 Plan 01: Last-Name-Wins Parser Contract Summary

**Pure transcript splitting now selects the final trigger alias boundary and cleanly gates activation for no-trigger and short-instruction paths.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-20T15:48:00Z
- **Completed:** 2026-03-20T15:53:55Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Added a RED parser corpus that validates last-name-wins selection, passthrough behavior, and short-instruction guards.
- Implemented a pure parser (`TriggerTranscriptParser`) and typed contract (`TriggerTranscriptSplit`) for deterministic boundary handling.
- Wired new parser, split, and tests into Xcode project targets for repeatable plan-local verification.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add RED parser corpus tests for last-name-wins boundaries and safety gates** - `0e2bf3e` (test)
2. **Task 2: Implement pure trigger transcript parser and split types to satisfy corpus** - `bfdf8f3` (feat)

## Files Created/Modified
- Created: `Speech2Text/Activation/TriggerTranscriptParser.swift`
- Created: `Speech2Text/Activation/TriggerTranscriptSplit.swift`
- Created: `Speech2TextTests/TriggerTranscriptParserTests.swift`
- Modified: `Speech2Text.xcodeproj/project.pbxproj`

## Verification Results
- `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -only-testing Speech2TextTests/TriggerTranscriptParserTests -destination 'platform=macOS'` (expected RED before implementation): **failed** due to missing parser symbols
- `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -only-testing Speech2TextTests/TriggerTranscriptParserTests -destination 'platform=macOS'` (after implementation): **passed**

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Prevent substring alias matches from activating parser**
- **Found during:** Task 2
- **Issue:** Boundary regex initially matched `atlas` inside `atlases`, causing a false activation.
- **Fix:** Switched to whole-word boundary matching (`\\b...\\b`) for alias detection.
- **Files modified:** `Speech2Text/Activation/TriggerTranscriptParser.swift`
- **Commit:** `bfdf8f3`

## Authentication Gates

None.

## Deferred Issues

None.

## Next Phase Readiness

Ready for `13-02-PLAN.md`.

## Self-Check: PASSED

- FOUND: `.planning/phases/13-last-name-wins-parser-integration/13-01-SUMMARY.md`
- FOUND: `0e2bf3e`
- FOUND: `bfdf8f3`
