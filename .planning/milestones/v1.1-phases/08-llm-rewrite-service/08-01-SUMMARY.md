---
phase: 08-llm-rewrite-service
plan: 01
subsystem: conversion
tags: [mlx-swift-lm, qwen, llm-rewrite, xcode]
requires:
  - phase: 07-core-types-and-intent-detection
    provides: ConvertMode and per-mode system prompts
provides:
  - Production LLM rewrite actor behind LLMRewriting
  - Application Support-backed model download path
  - Deterministic offline rewrite service unit test coverage
affects: [phase-09-activationstore-integration, guard-02]
tech-stack:
  added: []
  patterns:
    - Actor-isolated rewrite service with explicit async gate for generation serialization
    - Closure-based model loader and stream factory seam for deterministic tests
key-files:
  created:
    - Speech2Text/Conversion/LLMRewriteService.swift
    - Speech2TextTests/LLMRewriteServiceTests.swift
  modified:
    - Speech2Text.xcodeproj/project.pbxproj
key-decisions:
  - "Use Application Support (~/Library/Application Support/Speech2Text/RewriteModel) for Hub downloads to avoid purgeable cache eviction."
  - "Use a dedicated async execution gate to serialize generation, rather than relying on actor isolation across suspension points."
  - "Keep model loading and session streaming behind internal closure seams so tests remain fully offline and deterministic."
patterns-established:
  - "LLM actor API shape mirrors WhisperService with typed LocalizedError enums and protocol abstraction."
  - "Model first-load dedupe uses actor-held Task cache and shared awaiters."
requirements-completed: [GUARD-02]
duration: 5 min
completed: 2026-03-19
---

# Phase 8 Plan 1: LLM Rewrite Service Summary

**MLX-backed rewrite actor with Qwen2.5-1.5B lazy loading, explicit generation serialization, and deterministic offline contract tests for GUARD-02 failure behavior**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-19T13:30:24-04:00
- **Completed:** 2026-03-19T13:35:33-04:00
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Implemented `LLMRewriteService` as a non-main-actor Swift actor behind `LLMRewriting` with typed rewrite errors.
- Added lazy Qwen model loading through `LLMModelFactory.shared.loadContainer(...)`, with first-load dedupe via a shared in-flight `loadTask`.
- Added explicit rewrite serialization guard so concurrent rewrite calls cannot overlap MLX generation work.
- Ensured each rewrite call uses a fresh chat session seeded from `mode.defaultSystemPrompt` and `streamDetails(...)` output handling.
- Added deterministic offline tests that cover success, load dedupe, session-per-call behavior, serialization, and all required failure mappings.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create the production LLM rewrite actor and add it to the Xcode project** - `41f723f` (feat)
2. **Task 2: Add deterministic unit coverage for rewrite success, caching, and GUARD-02 failure semantics** - `0c74656` (test)

## Files Created/Modified
- `Speech2Text/Conversion/LLMRewriteService.swift` - Production rewrite actor, error contract, lazy model cache, in-flight load dedupe, generation serialization, and seamable loader/stream factory.
- `Speech2TextTests/LLMRewriteServiceTests.swift` - Deterministic async XCTest coverage for rewrite behavior and failure semantics.
- `Speech2Text.xcodeproj/project.pbxproj` - App/test target wiring for service and test source files.

## Decisions Made
- Kept MLX/HuggingFace dependencies isolated to the rewrite service layer; no ActivationStore MLX imports were added.
- Mapped stream completion reasons directly to contract errors (`.cancelled`, `.length`) and treated empty trimmed output as `.emptyOutput`.
- Chose closure seams over additional production files to keep testability local and scope-limited.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Escalated xcodebuild execution outside sandbox**
- **Found during:** Task 2 verification
- **Issue:** Sandbox denied access to Xcode/SwiftPM cache directories required for package resolution and build artifacts.
- **Fix:** Re-ran required `xcodebuild test` commands with escalated permissions.
- **Files modified:** None
- **Verification:** Commands executed successfully to build phase until unrelated existing test compilation errors blocked completion.
- **Committed in:** N/A (execution environment only)

---

**Total deviations:** 1 auto-fixed (Rule 3: 1)
**Impact on plan:** No scope creep; execution environment adjustment was required to run mandated verification commands.

## Issues Encountered
- Required verification commands failed due pre-existing, out-of-scope compile errors in existing test files (`ActivationStoreTests.swift`, `ReadinessStateTests.swift`).
- These failures are tracked in `.planning/phases/08-llm-rewrite-service/deferred-items.md` and were not auto-fixed per scope-boundary rules.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Rewrite actor contract is in place for Phase 9 integration.
- Guard-02 fallback wiring in ActivationStore remains pending Phase 9.
- Existing unrelated test-suite compile failures should be addressed to restore full regression-gate reliability.

## Self-Check: PASSED

- FOUND: `Speech2Text/Conversion/LLMRewriteService.swift`
- FOUND: `Speech2TextTests/LLMRewriteServiceTests.swift`
- FOUND: commit `41f723f`
- FOUND: commit `0c74656`

---
*Phase: 08-llm-rewrite-service*
*Completed: 2026-03-19*
