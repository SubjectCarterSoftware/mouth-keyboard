---
phase: 07-core-types-and-intent-detection
plan: 01
subsystem: testing
tags: [swift, xcodeproj, xctest, intent-detection, conversion]
requires:
  - phase: 06-dependency-integration-and-build-gate
    provides: xcode project with resolved package graph and committed Package.resolved for v1.1 work
provides:
  - ConvertMode enum with locked prompts, activation phrases, and trigger candidates
  - ConvertIntent value type carrying mode, stripped body, and original transcript
  - IntentDetector namespace stub for RED-first TDD sequencing
  - IntentDetector XCTest corpus covering mode metadata and trigger behavior requirements
affects: [phase-07-plan-02, phase-08-llm-rewrite-service, phase-09-activationstore-integration, phase-10-settings]
tech-stack:
  added: []
  patterns: [one-type-per-file Swift conversion types, mode-owned trigger phrase contracts, RED corpus before detector implementation]
key-files:
  created: [Speech2Text/Conversion/ConvertMode.swift, Speech2Text/Conversion/ConvertIntent.swift, Speech2Text/Conversion/IntentDetector.swift, Speech2TextTests/IntentDetectorTests.swift]
  modified: [Speech2Text.xcodeproj/project.pbxproj]
key-decisions:
  - "ConvertMode owns activationPhraseCandidates so later detection logic can consume mode contracts instead of rebuilding built-in names."
  - "Plan 01 stays intentionally RED by keeping IntentDetector.detect as a passthrough stub while the full corpus lands first."
patterns-established:
  - "Phase 7 conversion types remain pure value types with no external service dependencies."
  - "The intent corpus mixes metadata assertions that pass now with trigger assertions that stay RED until Plan 02."
requirements-completed: [MODE-01, MODE-02, MODE-03, MODE-04, MODE-05, MODE-06, INTENT-01, INTENT-02, INTENT-03]
duration: 5 min
completed: 2026-03-19
---

# Phase 7 Plan 1: Core Types and Intent Detection Summary

**Conversion type scaffolding plus a 40-test RED intent corpus for leading, trailing, case-insensitive, and passthrough trigger behavior**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-19T16:39:00Z
- **Completed:** 2026-03-19T16:44:14Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added `ConvertMode`, `ConvertIntent`, and a stub `IntentDetector` under a new `Speech2Text/Conversion/` source group.
- Locked the six built-in mode prompts, default activation phrases, and phase-specific trigger phrase candidates directly onto `ConvertMode`.
- Added a 40-test `IntentDetectorTests` corpus that encodes the Phase 7 metadata and trigger requirements ahead of the real detector implementation.

## Task Commits

Each task was committed atomically:

1. **Task 1: Define ConvertMode, ConvertIntent, and IntentDetector stubs** - `b9ccc7b` (feat)
2. **Task 2: Add Conversion group to Xcode project and write failing test suite** - `8e94816` (test)

## Files Created/Modified

- `Speech2Text/Conversion/ConvertMode.swift` - seven-case mode enum with locked prompts and ordered activation phrase candidates
- `Speech2Text/Conversion/ConvertIntent.swift` - intent payload storing mode, strippedBody, and originalTranscript
- `Speech2Text/Conversion/IntentDetector.swift` - passthrough detector stub reserved for Plan 02 implementation
- `Speech2TextTests/IntentDetectorTests.swift` - 40 RED/metadata XCTest cases covering Phase 7 corpus expectations
- `Speech2Text.xcodeproj/project.pbxproj` - app/test target wiring plus new `Conversion` group membership

## Decisions Made

- Stored trigger phrase candidates on `ConvertMode` so Phase 10 custom-mode support can reuse the same contract shape.
- Added two extra tests beyond the plan snippet to explicitly lock `ConvertIntent` field storage and the current stub passthrough behavior while still exceeding the 39-test minimum.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

- `xcodebuild build` and the focused `xcodebuild test` command could not complete in this environment. First, the sandbox blocked writes to `/Users/elicarter/Library/Caches` and related Xcode cache locations. After redirecting writable caches into the workspace, package resolution still failed because outbound GitHub host resolution was unavailable. File-level verification, project wiring checks, and test-count checks passed, but the build/RED run could not be completed inside this execution environment.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02 can now replace the passthrough stub with the real leading/trailing, case-insensitive, end-wins algorithm against an already-written corpus.
- The Xcode project and test target already reference all Phase 7 Plan 1 files, so Plan 02 can focus on implementation and GREEN verification.

## Self-Check: PASSED

- Found `.planning/phases/07-core-types-and-intent-detection/07-01-SUMMARY.md`
- Found commit `b9ccc7b`
- Found commit `8e94816`

---
*Phase: 07-core-types-and-intent-detection*
*Completed: 2026-03-19*
