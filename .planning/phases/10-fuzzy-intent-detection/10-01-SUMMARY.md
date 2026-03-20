---
phase: 10-fuzzy-intent-detection
plan: "01"
subsystem: testing
tags: [swift, xcode, xctest, jaro-winkler, intent-detection, tdd, red-phase]

requires:
  - phase: 07-core-types-and-intent-detection
    provides: IntentDetector.detect() signature, ConvertMode, ConvertIntent contracts
  - phase: 09-activationstore-integration-and-guards
    provides: verified end-to-end intent detection flow (exact-phrase)

provides:
  - IntentDefinition struct — value type contract for a single detectable intent
  - IntentCatalog enum — static catalog of 6 intent definitions with full phrase pattern lists
  - StringSimilarity enum — stub jaroWinkler(_ s: String, _ t: String) -> Double
  - IntentDetectorTests.swift — 65-test fuzzy corpus (11 RED filler/fuzzy tests, 54 GREEN structural)
  - StringSimilarityTests.swift — 7 Jaro-Winkler reference pair tests (4 RED)

affects:
  - 10-02-PLAN.md (Plan 02 turns these RED tests GREEN with real Jaro-Winkler + normalization)

tech-stack:
  added: []
  patterns:
    - "Config-driven intent catalog: IntentDefinition struct + IntentCatalog.all static array"
    - "TDD RED phase: write failing tests before implementation"
    - "IntentDetector uses IntentCatalog.all instead of activationPhraseCandidates"

key-files:
  created:
    - Speech2Text/Conversion/IntentDefinition.swift
    - Speech2Text/Conversion/IntentCatalog.swift
    - Speech2Text/Conversion/StringSimilarity.swift
    - Speech2TextTests/StringSimilarityTests.swift
  modified:
    - Speech2Text/Conversion/ConvertMode.swift
    - Speech2Text/Conversion/IntentDetector.swift
    - Speech2TextTests/IntentDetectorTests.swift
    - Speech2Text.xcodeproj/project.pbxproj

key-decisions:
  - "IntentCatalog now drives IntentDetector phrase matching (hasPrefix/hasSuffix reads catalog patterns, not activationPhraseCandidates)"
  - "activationPhraseCandidates removed from ConvertMode.swift; IntentCatalog.all is authoritative"
  - "StringSimilarity stub returns 0.0 always — Plan 02 provides real Jaro-Winkler"
  - "Test corpus includes exact catalog matches (GREEN with old hasPrefix logic) AND filler/fuzzy variants (RED until Plan 02)"
  - "confidenceThreshold: 0.82 for email/slack/teams/cleanEnglish; 0.80 for actionItems/aiPrompt; 0.85 for cleanEnglish"

patterns-established:
  - "Pattern: Adding a new intent = one new IntentDefinition in IntentCatalog.all; no logic changes"
  - "Pattern: phrasePatterns contains both new paraphrases AND legacy activationPhraseCandidates for backward compat"

requirements-completed: [INTENT-01, INTENT-02, INTENT-03]

duration: 8min
completed: 2026-03-20
---

# Phase 10 Plan 01: Fuzzy Intent Detection — RED Phase Summary

**IntentDefinition/IntentCatalog/StringSimilarity stubs + 65-test fuzzy corpus (11 RED filler/normalization tests); activationPhraseCandidates removed from ConvertMode**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-20T00:12:39Z
- **Completed:** 2026-03-20T00:20:53Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Created 3 new Swift stub files establishing the data contracts for fuzzy intent detection (IntentDefinition, IntentCatalog, StringSimilarity)
- Removed `activationPhraseCandidates` from ConvertMode.swift; IntentCatalog is now the authoritative phrase source
- Rewrote IntentDetectorTests.swift with 65 tests covering paraphrase, filler words, normalization, backward compat, passthrough guards, and IntentCatalog structure
- Created StringSimilarityTests.swift with 7 Jaro-Winkler reference pair tests (4 RED — stub returns 0.0)
- All 11 filler/fuzzy/normalization detection tests correctly fail with assertion errors (not compile errors)
- BUILD SUCCEEDED; 15 MODE metadata tests remain GREEN

## Task Commits

1. **Task 1: Create stubs and remove activationPhraseCandidates** - `98a4b6e` (chore)
2. **Task 2: Rewrite test corpus (TDD RED)** - `9053027` (test)

## Files Created/Modified

- `Speech2Text/Conversion/IntentDefinition.swift` — struct with mode/aliases/phrasePatterns/keywordSignal/confidenceThreshold
- `Speech2Text/Conversion/IntentCatalog.swift` — static catalog with 6 intent definitions (full pattern lists from RESEARCH.md)
- `Speech2Text/Conversion/StringSimilarity.swift` — stub enum, jaroWinkler returns 0.0
- `Speech2Text/Conversion/ConvertMode.swift` — activationPhraseCandidates removed
- `Speech2Text/Conversion/IntentDetector.swift` — updated to use IntentCatalog patterns (hasPrefix/hasSuffix logic preserved)
- `Speech2TextTests/IntentDetectorTests.swift` — rewritten: 65 tests, 11 RED filler/fuzzy/normalization
- `Speech2TextTests/StringSimilarityTests.swift` — new: 7 Jaro-Winkler reference pair tests (4 RED)
- `Speech2Text.xcodeproj/project.pbxproj` — 3 source files + 1 test file added to project

## Decisions Made

- IntentDetector.swift body kept (hasPrefix/hasSuffix logic) but updated to read from IntentCatalog instead of `activationPhraseCandidates` — this was a required deviation to fix a compile error (Rule 3 - Blocking) caused by removing the property
- Test corpus designed so that exact catalog phrases pass (GREEN — hasPrefix matches them) while filler-wrapped and fuzzy-required paraphrases fail (RED — hasPrefix can't handle "Okay make this an email" or "e mail mode")
- Added normalization tests ("e mail mode", "action item" singular) as RED since old detector has no normalization pipeline

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated IntentDetector.swift to use IntentCatalog instead of removed property**
- **Found during:** Task 1 verification (xcodebuild build)
- **Issue:** IntentDetector.swift references `mode.activationPhraseCandidates` on lines 23 and 89. Removing the property from ConvertMode.swift caused compile errors: "Value of type 'ConvertMode' has no member 'activationPhraseCandidates'"
- **Fix:** Replaced `mode.activationPhraseCandidates` with `IntentCatalog.all.first(where: { $0.mode == mode })?.phrasePatterns ?? []` in both places. The hasPrefix/hasSuffix detection logic is completely unchanged — only the data source changed.
- **Files modified:** Speech2Text/Conversion/IntentDetector.swift
- **Verification:** `xcodebuild build` → BUILD SUCCEEDED
- **Committed in:** 98a4b6e (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary fix — the property removal was explicitly planned but the plan didn't address the compile error in IntentDetector.swift. Fix preserves all hasPrefix/hasSuffix behavior so the RED/GREEN test distribution is as designed.

## Issues Encountered

- More tests pass than a strict reading of "new detection tests FAIL" might suggest — this is because the catalog now has exact patterns like "make this an email" which hasPrefix matches exactly. Only the genuinely new capability (filler stripping, normalization, fuzzy scoring) tests are RED. This is the correct outcome for the RED phase.

## Next Phase Readiness

- Plan 02 can implement real Jaro-Winkler in StringSimilarity.swift and full normalization + zone extraction in IntentDetector.swift
- Test corpus is in place — Plan 02 just needs to make the 11 RED detection tests and 4 RED similarity tests go GREEN
- IntentCatalog and IntentDefinition contracts are stable — no changes expected in Plan 02

---
*Phase: 10-fuzzy-intent-detection*
*Completed: 2026-03-20*
