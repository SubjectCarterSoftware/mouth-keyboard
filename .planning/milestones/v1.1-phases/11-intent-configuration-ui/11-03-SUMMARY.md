---
phase: 11-intent-configuration-ui
plan: "03"
subsystem: conversion
tags: [swift, activation-store, intent-detection, llm-rewrite, user-intent-store, tdd]

# Dependency graph
requires:
  - phase: 11-01
    provides: UserIntentStore actor with allEntries(), addOrUpdateBuiltInOverride(), addOrUpdateCustomMode()
  - phase: 11-02
    provides: IntentCatalog.effective(store:), IntentDetector.detect(transcript:definitions:), LLMRewriting.rewrite(body:instructions:), ConvertIntent.customIntentID

provides:
  - ActivationStore.finalizeSession wired to UserIntentStore — merged catalog for detection, effective prompt resolution for LLM call routing
  - Built-in override path: rewrite(body:instructions:) called when UserIntentStore has entry matching mode id
  - Custom intent path: rewrite(body:instructions:) called with entry systemPrompt resolved via modeName lookup
  - Unoverridden built-in path: rewrite(body:mode:) unchanged (no regression for standard users)
  - Passthrough path: completely unchanged (LLM-02 verified)
  - UserIntentStore.shared singleton added

affects:
  - 11-04 (UI — reads effective definitions for display, writes to UserIntentStore)
  - 11-05 (phrase generation — writes phrasePatterns/keywordSignal back to UserIntentStore)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Session-start snapshot: allEntries() called once per finalizeSession, avoiding repeated actor hops"
    - "Dual-overload routing: if resolvedInstructions != nil -> instructions overload, else -> mode overload"
    - "modeName lookup for custom intents: storeEntries.first { !$0.isBuiltIn && $0.modeName == customID }"

key-files:
  created: []
  modified:
    - Speech2Text/Activation/ActivationStore.swift
    - Speech2Text/Conversion/UserIntentStore.swift
    - Speech2TextTests/ActivationStoreTests.swift

key-decisions:
  - "allEntries() snapshot taken once at session-start — avoids multiple actor hops, provides consistent view for the whole finalizeSession call"
  - "passthrough check updated to intent.mode == .passthrough && intent.customIntentID == nil — custom intents use .passthrough mode but are NOT passthrough"
  - "resolvedInstructions guards: customIntentID path checked first, then built-in override, else nil → fallback to mode-based rewrite"
  - "UserIntentStore.shared singleton added alongside existing init(storeURL:) injection pattern"

patterns-established:
  - "Dual-path LLM routing: instructions overload for user-configured intents, mode overload for defaults — zero behavior change for unconfigured modes"

requirements-completed: [CONFIG-01, CONFIG-02, CONFIG-03]

# Metrics
duration: 12min
completed: "2026-03-20"
---

# Phase 11 Plan 03: ActivationStore Wiring Summary

**ActivationStore.finalizeSession wired to UserIntentStore — override/custom intents use rewrite(body:instructions:), unoverridden built-ins unchanged, passthrough path untouched**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-20T11:01:50Z
- **Completed:** 2026-03-20T11:13:15Z
- **Tasks:** 2 (TDD RED + GREEN)
- **Files modified:** 3

## Accomplishments
- `UserIntentStore.shared` singleton added — ActivationStore can reference it as default parameter
- `ActivationStore.init` gains `userIntentStore: UserIntentStore = UserIntentStore.shared` parameter — no breaking changes
- `finalizeSession` snapshots merged catalog via `IntentCatalog.effective(store:)` at session-start, then routes LLM call via `resolvedInstructions`
- 4 new test cases covering override, custom, unoverridden built-in, and passthrough paths — all green
- `MockLLMRewriter` extended with `lastCalledOverload`, `lastInstructions`, `lastMode` tracking for routing assertions

## Task Commits

Each task was committed atomically:

1. **Task 1: RED — ActivationStore override + custom intent routing tests** - `aa405e1` (test)
2. **Task 2: GREEN — Wire ActivationStore to UserIntentStore** - `4ad475a` (feat)

## Files Created/Modified
- `Speech2Text/Activation/ActivationStore.swift` - Added userIntentStore property + init parameter; wired finalizeSession with store snapshot, effective catalog detection, and dual-path LLM routing
- `Speech2Text/Conversion/UserIntentStore.swift` - Added `static let shared` singleton
- `Speech2TextTests/ActivationStoreTests.swift` - Extended MockLLMRewriter with overload tracking; updated makeStore with userIntentStore param; added 4 new routing test cases

## Decisions Made
- `allEntries()` called once per `finalizeSession` to snapshot entries — avoids repeated actor hops and ensures a consistent view for the whole session
- `passthrough` check updated to `intent.mode == .passthrough && intent.customIntentID == nil` — custom intents carry `mode: .passthrough` but must go through LLM rewrite
- `resolvedInstructions` computed as: customIntentID path first → built-in override → nil (falls back to mode-based overload)

## Deviations from Plan

None - plan executed exactly as written. The `customIntentID` passthrough-check update (adding `&& intent.customIntentID == nil`) was a necessary correctness fix implied by the design — custom entries use `mode: .passthrough` to avoid new ConvertMode cases but are not actually passthrough.

## Issues Encountered
- Pre-existing test failures (`HotkeyServiceTests.testDefaultActivationShortcutIsControlV`, `ShellPreferencesModelTests.testLaunchAtLoginDefaultsToFalse`) remain present and documented in STATE.md — both unrelated to this plan's changes.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `ActivationStore` now fully wired to `UserIntentStore` — override and custom intents work end-to-end in the production pipeline
- Plans 11-04 (Settings UI) and 11-05 (Phrase Generation) can now write to `UserIntentStore` knowing their data reaches the LLM call
- No blockers for Plans 11-04 and 11-05

## Self-Check: PASSED

- ActivationStore.swift: FOUND
- UserIntentStore.swift: FOUND
- ActivationStoreTests.swift: FOUND
- 11-03-SUMMARY.md: FOUND
- Commit aa405e1: FOUND
- Commit 4ad475a: FOUND

---
*Phase: 11-intent-configuration-ui*
*Completed: 2026-03-20*
