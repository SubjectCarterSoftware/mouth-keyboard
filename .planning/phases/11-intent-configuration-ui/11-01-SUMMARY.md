---
phase: 11-intent-configuration-ui
plan: 01
subsystem: database
tags: [swift, actor, json, persistence, codable, app-support]

# Dependency graph
requires:
  - phase: 10-fuzzy-intent-detection
    provides: IntentCatalog, IntentDefinition, ConvertMode — the types UserIntentStore entries map onto
provides:
  - UserIntentEntry Codable/Identifiable/Equatable struct with 6 fields (id, modeName, systemPrompt, phrasePatterns, keywordSignal, isBuiltIn)
  - UserIntentStore actor with full JSON persistence in App Support/Speech2Text/IntentStore.json
  - Hermetic test URL override (storeURL param) for isolation without App Support contamination
  - 9 passing unit tests covering empty store, round-trip, reset, upsert dedup, delete, and directory creation
affects:
  - 11-02-catalog-merge (reads UserIntentStore entries via IntentCatalog.effective(store:))
  - 11-03-settings-ui (binds to UserIntentStore for editing)
  - 11-04-phrase-generation (writes phrasePatterns/keywordSignal back to UserIntentStore)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Actor-isolated JSON store with lazy load (ensureLoaded flag) and atomic write (.atomic option)
    - Test URL injection via init parameter for hermetic unit testing without App Support side effects
    - Silent degradation: corrupted or missing JSON file yields empty array (no error thrown)
    - createDirectory(withIntermediateDirectories: true) mirrors existing makePersistentHub() pattern

key-files:
  created:
    - Speech2Text/Conversion/UserIntentEntry.swift
    - Speech2Text/Conversion/UserIntentStore.swift
    - Speech2TextTests/UserIntentStoreTests.swift
  modified:
    - Speech2Text.xcodeproj/project.pbxproj

key-decisions:
  - "UserIntentStore uses actor isolation — all mutation serialized; no data races possible"
  - "Lazy load with loaded flag: disk read happens once on first allEntries() call, not on init"
  - "Silent degradation on JSON decode failure: store starts fresh rather than propagating error to callers"
  - "storeURL init parameter enables hermetic tests using FileManager.temporaryDirectory UUIDs — no App Support pollution"
  - "save() calls createDirectory(withIntermediateDirectories: true) before every write — safe for first-run and nested tmp paths in tests"

patterns-established:
  - "Actor JSON store pattern: private entries array + loaded flag + ensureLoaded() + upsert() helper"
  - "Test URL injection: init(storeURL: URL = UserIntentStore.defaultStoreURL) — same pattern as LLMRewriteService seams"

requirements-completed: [CONFIG-01, CONFIG-03]

# Metrics
duration: 15min
completed: 2026-03-20
---

# Phase 11 Plan 01: UserIntentEntry + UserIntentStore Data Layer Summary

**Actor-isolated JSON persistence store for per-mode overrides and custom intents in App Support/Speech2Text/IntentStore.json with hermetic test URL injection**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-20T10:47:11Z
- **Completed:** 2026-03-20T10:55:00Z
- **Tasks:** 2 (TDD RED + GREEN)
- **Files modified:** 4

## Accomplishments
- `UserIntentEntry` Codable/Identifiable/Equatable struct with all 6 required fields
- `UserIntentStore` actor: lazy-load, upsert-by-id, reset, delete, atomic JSON write with directory creation
- 9 unit tests covering all persistence operations including disk round-trip and directory auto-creation
- Fixed pre-existing `MockLLMRewriter` compile blocker in `ActivationStoreTests` (missing `rewrite(body:instructions:)` protocol method)

## Task Commits

Each task was committed atomically:

1. **Task 1: RED — UserIntentStoreTests failing stubs** - `d30e113` (test)
2. **Task 2: GREEN — UserIntentStore JSON persistence** - `1947e46` (feat, included in 11-02 RED commit)

_Note: GREEN phase implementation was committed as part of the 11-02 RED phase commit by a prior agent._

## Files Created/Modified
- `Speech2Text/Conversion/UserIntentEntry.swift` - Codable/Identifiable/Equatable struct: id, modeName, systemPrompt, phrasePatterns, keywordSignal, isBuiltIn
- `Speech2Text/Conversion/UserIntentStore.swift` - Actor with load/save/upsert/reset/delete operations, App Support persistence, test URL injection
- `Speech2TextTests/UserIntentStoreTests.swift` - 9 unit tests: empty store, save+reload, round-trip built-in, round-trip custom, reset, reset persists, upsert dedup, delete, directory creation
- `Speech2Text.xcodeproj/project.pbxproj` - Register all 3 new files (file refs 0x43–0x45, build phase entries)
- `Speech2TextTests/ActivationStoreTests.swift` - Add missing `rewrite(body:instructions:)` to MockLLMRewriter (Rule 3 auto-fix)

## Decisions Made
- Actor isolation for all mutation: no explicit locks needed; Swift concurrency guarantees serialization
- Lazy load on first `allEntries()` call rather than `init` — avoids blocking actor initialization
- Silent degradation on JSON corruption: store starts fresh, never propagates decode errors to callers
- `storeURL` init parameter for tests — same hermetic injection pattern as `LLMRewriteService` loader/stream seams

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed MockLLMRewriter missing protocol conformance in ActivationStoreTests**
- **Found during:** Task 2 (GREEN — running full regression suite)
- **Issue:** `ActivationStoreTests.swift:566` — `MockLLMRewriter` conformed to `LLMRewriting` but only implemented `rewrite(body:mode:)`. The protocol also requires `rewrite(body:instructions:)` (added in Phase 11-02 RED commit). This caused the entire `Speech2TextTests` target to fail to build, preventing any test run.
- **Fix:** Added `func rewrite(body: String, instructions: String) async throws -> String` stub to `MockLLMRewriter` delegating to the same `result` enum
- **Files modified:** `Speech2TextTests/ActivationStoreTests.swift`
- **Verification:** `xcodebuild test -only-testing:Speech2TextTests/UserIntentStoreTests` — all 9 pass
- **Committed in:** `1947e46` (included in GREEN phase commit)

---

**Total deviations:** 1 auto-fixed (1 Rule 3 blocking)
**Impact on plan:** Fix required to run any tests in the Speech2TextTests target. No scope creep.

## Issues Encountered
- Pre-existing uncommitted Phase 11-02 work was present in the working tree when this plan started — `IntentCatalogDynamicTests`, `ConvertIntent`, `IntentCatalog`, `IntentDetector`, `LLMRewriteService` modifications. The GREEN phase changes were incorporated into the 11-02 RED commit by a prior agent. The `HotkeyServiceTests` and `ShellPreferencesModelTests` failures are documented pre-existing issues in STATE.md.

## Self-Check: PASSED

- UserIntentEntry.swift: FOUND
- UserIntentStore.swift: FOUND
- UserIntentStoreTests.swift: FOUND
- 11-01-SUMMARY.md: FOUND
- Commit d30e113: FOUND
- Commit 1947e46: FOUND

## Next Phase Readiness
- `UserIntentEntry` and `UserIntentStore` are ready for consumption by Phase 11-02 (`IntentCatalog.effective(store:)`)
- Test URL injection enables downstream test isolation without App Support side effects
- No blockers for Plan 11-02

---
*Phase: 11-intent-configuration-ui*
*Completed: 2026-03-20*
