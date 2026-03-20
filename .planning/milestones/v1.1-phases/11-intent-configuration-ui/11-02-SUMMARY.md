---
phase: 11-intent-configuration-ui
plan: "02"
subsystem: conversion
tags: [swift, intent-detection, llm-rewrite, catalog-merge, tdd]

# Dependency graph
requires:
  - phase: 11-01
    provides: UserIntentEntry Codable struct used as parameter type in IntentCatalog.effective(store:)
provides:
  - IntentCatalog.effective(store:) — merges UserIntentEntry overrides into built-in definitions and appends custom entries
  - LLMRewriting.rewrite(body:instructions:) — new protocol overload + actor implementation passing raw instructions string to streamFactory
  - IntentDetector.detect(transcript:definitions:) — new overload accepting [IntentDefinition] directly, bypassing IntentCatalog.all
  - ConvertIntent.effectiveSystemPrompt: String? — carried through pipeline, set by ActivationStore (Plan 03)
  - ConvertIntent.customIntentID: String? — non-nil when matched definition has .passthrough mode (custom intent)
affects:
  - 11-03 (ActivationStore wiring — calls rewrite(body:instructions:) when effectiveSystemPrompt non-nil, resolves customIntentID via UserIntentStore)
  - 11-04 (UI — reads effective definitions for display)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Delegate pattern: rewrite(body:mode:) delegates to rewriteCore(body:instructions:) private helper — single implementation, two entry points"
    - "Defs-based scoring: scoreZoneDefs/scoreAllZoneDefs accept [IntentDefinition] directly, bypassing catalog — enables custom intent matching without new ConvertMode cases"
    - "customIntentID: aliases.first for .passthrough definitions — ActivationStore resolves prompt by modeName lookup"

key-files:
  created:
    - Speech2TextTests/IntentCatalogDynamicTests.swift
  modified:
    - Speech2Text/Conversion/ConvertIntent.swift
    - Speech2Text/Conversion/LLMRewriteService.swift
    - Speech2Text/Conversion/IntentCatalog.swift
    - Speech2Text/Conversion/IntentDetector.swift
    - Speech2TextTests/LLMRewriteServiceTests.swift
    - Speech2TextTests/ActivationStoreTests.swift

key-decisions:
  - "rewrite(body:mode:) delegates to rewriteCore(body:instructions:) — single code path, zero duplication, backward compatible"
  - "Custom intent mode field is .passthrough (no new ConvertMode cases); caller distinguishes via customIntentID"
  - "customIntentID = aliases.first for .passthrough matches — ActivationStore looks up UserIntentEntry by modeName to resolve systemPrompt"
  - "effectiveSystemPrompt nil from detector — ActivationStore (Plan 03) resolves it; detector stays pure detection logic"
  - "scoreZoneDefs/scoreAllZoneDefs added as private helpers — avoid duplication without breaking existing modes-based API"

patterns-established:
  - "Private core helper pattern: extract implementation to private func, public methods are thin wrappers"
  - "Defs-based overload pattern: add [IntentDefinition]-accepting private scoring helpers alongside existing modes-based ones"

requirements-completed:
  - CONFIG-02

# Metrics
duration: 11min
completed: "2026-03-20"
---

# Phase 11 Plan 02: Service Layer Extensions Summary

**Catalog merge + LLM instructions overload + detect(definitions:) — contracts for ActivationStore and UI Plans 03-04**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-20T10:47:33Z
- **Completed:** 2026-03-20T10:58:00Z
- **Tasks:** 2 (TDD RED + GREEN)
- **Files modified:** 7

## Accomplishments
- `LLMRewriting` protocol and actor get `rewrite(body:instructions:)` overload — existing mode-based method delegates to shared core
- `IntentCatalog.effective(store:)` merges `UserIntentEntry` overrides into built-in definitions and appends custom entries as `.passthrough` mode definitions
- `IntentDetector.detect(transcript:definitions:)` overload accepts `[IntentDefinition]` directly — full scoring algorithm with custom intent ID resolution
- `ConvertIntent` extended with `effectiveSystemPrompt: String?` and `customIntentID: String?`; backward-compat 3-arg convenience init preserves all call sites

## Task Commits

Each task was committed atomically:

1. **Task 1: RED — Write failing tests + add stubs** - `1947e46` (test)
2. **Task 2: GREEN — Implement catalog merge, instructions overload, detect overload** - `4250807` (feat)

## Files Created/Modified
- `Speech2TextTests/IntentCatalogDynamicTests.swift` - New test file: 16 tests covering catalog merge, ConvertIntent fields, detect overload
- `Speech2Text/Conversion/ConvertIntent.swift` - Added `effectiveSystemPrompt: String?`, `customIntentID: String?`, backward-compat init
- `Speech2Text/Conversion/LLMRewriteService.swift` - Added `rewrite(body:instructions:)` to protocol; refactored actor to use private `rewriteCore(body:instructions:)`
- `Speech2Text/Conversion/IntentCatalog.swift` - Added `effective(store:)` static method with built-in merge + custom append logic
- `Speech2Text/Conversion/IntentDetector.swift` - Added `detect(transcript:definitions:)` overload + private `scoreZoneDefs`/`scoreAllZoneDefs` helpers
- `Speech2TextTests/LLMRewriteServiceTests.swift` - Added instructions overload test verifying string pass-through to streamFactory
- `Speech2TextTests/ActivationStoreTests.swift` - `MockLLMRewriter` conforms to updated `LLMRewriting` protocol

## Decisions Made
- `rewrite(body:mode:)` delegates to private `rewriteCore(body:instructions:)` — single code path, zero duplication
- Custom intent entries get `mode: .passthrough`; `customIntentID` carries `aliases.first` so ActivationStore can do a modeName lookup
- `effectiveSystemPrompt` is nil from the detector — resolution is ActivationStore's responsibility (Plan 03)
- Private `scoreZoneDefs`/`scoreAllZoneDefs` added as separate helpers to avoid breaking existing modes-based API surface

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] LLMRewriteServiceTests RED test updated to GREEN behavior**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** `testRewriteWithInstructionsOverloadExists` was written in RED expecting `.modelLoadFailed`; after real implementation, it needed to verify actual behavior
- **Fix:** Updated test to verify instructions string is passed through to streamFactory (stronger assertion than stub existence)
- **Files modified:** Speech2TextTests/LLMRewriteServiceTests.swift
- **Committed in:** `4250807` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (test update to stronger assertion)
**Impact on plan:** No scope creep. Test quality improved — verifies behavioral contract instead of stub error.

## Issues Encountered
- None — plan executed cleanly. Pre-existing test failures (HotkeyServiceTests, ShellPreferencesModelTests) remain documented non-regression.

## Next Phase Readiness
- `LLMRewriting.rewrite(body:instructions:)` contract established — ActivationStore (Plan 03) can call it when `effectiveSystemPrompt` is non-nil
- `IntentCatalog.effective(store:)` available — ActivationStore uses it with live `UserIntentStore` entries
- `ConvertIntent.customIntentID` available — ActivationStore resolves custom intent system prompt via `UserIntentStore.entry(for:)`
- Plans 11-03 through 11-05 unblocked

---
*Phase: 11-intent-configuration-ui*
*Completed: 2026-03-20*
