---
phase: 09-activationstore-integration-and-guards
plan: 01
subsystem: activation
tags: [swift, activationstore, llm, intentdetector, llmrewriting, recordingstate, shellpreferences, convertmode]

# Dependency graph
requires:
  - phase: 08-llm-rewrite-service
    provides: LLMRewriting protocol + LLMRewriteService actor with rewrite(body:mode:) async throws
  - phase: 07-core-types-and-intent-detection
    provides: IntentDetector.detect(transcript:modes:) + ConvertMode + ConvertIntent types
provides:
  - RecordingState extended with .converting (non-terminal) + .wordLimitExceeded + success(converted:Bool)
  - ConvertMode.allBuiltIns static computed property
  - ShellPreferences.convertModes [ConvertMode] with UserDefaults persistence
  - ActivationStore.llmRewriteService DI injection
  - ActivationStore.finalizeSession() intent-branching logic (passthrough / word-gate / LLM path)
  - ActivationStore.lastConvertedTranscription @Published property
affects:
  - 09-activationstore-integration-and-guards/09-02 (UI guard rendering, .converting state display)
  - 10-model-download-and-progress (downstream state shape consumers)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Intent branching in finalizeSession(): passthrough unchanged; conversion gated by 350-word limit; LLM failure silently falls back to raw transcript"
    - "DI via protocol existential (any LLMRewriting) in ActivationStore init — matches WhisperTranscribing pattern"
    - "MockLLMRewriter in tests mirrors existing mock pattern (MockResult enum, @unchecked Sendable)"

key-files:
  created: []
  modified:
    - Speech2Text/Activation/RecordingState.swift
    - Speech2Text/Conversion/ConvertMode.swift
    - Speech2Text/Persistence/ShellPreferences.swift
    - Speech2Text/Activation/ActivationStore.swift
    - Speech2Text/App/AppDelegate.swift
    - Speech2Text/Shell/RecordingPillView.swift
    - Speech2Text/Shell/StatusMenuView.swift
    - Speech2TextTests/ActivationStoreTests.swift

key-decisions:
  - "Passthrough path in finalizeSession() is completely unchanged (LLM-02 contract): pasteOnCompletion honored, raw text to clipboard, converted: false"
  - "Word count gate (GUARD-01) checks strippedBody (trigger removed), not full trimmed transcript"
  - "LLM failure (GUARD-02) is silent: raw transcript to clipboard, state .success(converted: false)"
  - ".converting is non-terminal so arm() is blocked during conversion but cancelCurrentSession() guard remains .recording || .processing only"
  - "scheduleDismissToIdle handles .converting as a non-transitioning case (same as .idle/.recording/.processing)"

patterns-established:
  - "Intent-branch pattern: detect intent first, then branch on mode == .passthrough vs conversion path"
  - "All new RecordingState cases require exhaustive switch coverage across AppDelegate, RecordingPillView, StatusMenuView"

requirements-completed: [LLM-02, GUARD-01, UX-01]

# Metrics
duration: 25min
completed: 2026-03-19
---

# Phase 9 Plan 01: ActivationStore Integration and Guards Summary

**IntentDetector + LLMRewriteService wired into ActivationStore.finalizeSession() with 350-word guard, silent fallback, and .converting non-terminal state**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-19T20:36:00Z
- **Completed:** 2026-03-19T20:38:20Z
- **Tasks:** 3 (Task 0 + Task 1 + Task 2)
- **Files modified:** 8

## Accomplishments
- RecordingState extended: .converting non-terminal, .wordLimitExceeded FailureReason, success(text:pasted:converted:Bool)
- ConvertMode.allBuiltIns returns all 6 non-passthrough modes; ShellPreferences.convertModes persists via UserDefaults
- ActivationStore.finalizeSession() now branches on IntentDetector.detect(): passthrough (unchanged), word-limit gate, LLM rewrite with silent failure fallback
- All 25 ActivationStoreTests pass including 2 new Phase 9 tests (trigger + passthrough)
- Zero build errors across the entire project

## Task Commits

Each task was committed atomically:

1. **Task 0: Test scaffold — MockLLMRewriter, Phase 9 tests, .success pattern updates** - `e33beb7` (test)
2. **Task 1: Extend RecordingState, add ConvertMode.allBuiltIns, add ShellPreferences.convertModes** - `9b2a21f` (feat)
3. **Task 2: Wire ActivationStore — DI injection, finalizeSession() branch, lastConvertedTranscription** - `8eaeaed` (feat)

_Note: Task 0 was intentionally RED until Task 2 brought the project to GREEN._

## Files Created/Modified
- `Speech2Text/Activation/RecordingState.swift` - Added .converting, .wordLimitExceeded, success(converted:Bool)
- `Speech2Text/Conversion/ConvertMode.swift` - Added static allBuiltIns computed property
- `Speech2Text/Persistence/ShellPreferences.swift` - Added convertModes with UserDefaults persistence + reset
- `Speech2Text/Activation/ActivationStore.swift` - DI injection, intent branch, lastConvertedTranscription
- `Speech2Text/App/AppDelegate.swift` - Fixed exhaustive switch for .converting + preview constants
- `Speech2Text/Shell/RecordingPillView.swift` - Added .converting and .wordLimitExceeded switch cases
- `Speech2Text/Shell/StatusMenuView.swift` - Added .converting and .wordLimitExceeded to all switch sites
- `Speech2TextTests/ActivationStoreTests.swift` - MockLLMRewriter, makeStore(llmRewriter:), 2 new tests, updated .success patterns

## Decisions Made
- Passthrough path in finalizeSession() is completely unchanged — `pasteOnCompletion` is honored, raw text to clipboard, `converted: false` (LLM-02)
- Word count gate (GUARD-01) measures `strippedBody` (trigger phrase removed), not the full `trimmed` transcript
- LLM failure (GUARD-02) is silent: raw transcript to clipboard, state `.success(converted: false)` — no error surfaced to user
- `.converting` is non-terminal so `arm()` is blocked but `cancelCurrentSession()` guard unchanged (`.recording || .processing` only)
- `scheduleDismissToIdle` treats `.converting` as non-transitioning (parallel to `.processing`)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed non-exhaustive switch for .converting in RecordingPillView and AppDelegate**
- **Found during:** Task 2 (first test run)
- **Issue:** Adding `.converting` to RecordingState made existing switches non-exhaustive; Swift compiler caught them as errors
- **Fix:** Added `.converting` case to all switch sites: RecordingPillView body, AppDelegate state sink, StatusMenuView statusDescription
- **Files modified:** Speech2Text/Shell/RecordingPillView.swift, Speech2Text/App/AppDelegate.swift, Speech2Text/Shell/StatusMenuView.swift
- **Verification:** Project builds with zero errors; all 25 tests pass
- **Committed in:** 8eaeaed (Task 2 commit)

**2. [Rule 1 - Bug] Fixed non-exhaustive switch for .wordLimitExceeded in RecordingPillView and StatusMenuView**
- **Found during:** Task 2 (first test run)
- **Issue:** Adding `.wordLimitExceeded` to FailureReason made failureMessage/showsMicrophoneSettingsAction/showsMicrophoneRecoveryAction switches non-exhaustive
- **Fix:** Added `.wordLimitExceeded` case with appropriate messages to all FailureReason switch sites
- **Files modified:** Speech2Text/Shell/RecordingPillView.swift, Speech2Text/Shell/StatusMenuView.swift
- **Verification:** Project builds with zero errors
- **Committed in:** 8eaeaed (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (Rule 1 — non-exhaustive switch coverage for new enum cases)
**Impact on plan:** Both fixes were direct consequences of extending RecordingState. No scope creep.

## Issues Encountered
None — plan executed as specified. The intentionally-RED Wave 0 pattern worked correctly: Task 0 added test scaffold, Tasks 1+2 turned it GREEN atomically.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All data model + behavior contracts are complete and tested
- RecordingState.converting, FailureReason.wordLimitExceeded, ActivationStore.lastConvertedTranscription are available for Phase 9 Plan 02 UI rendering
- ConvertMode.allBuiltIns and ShellPreferences.convertModes are available for any settings UI in future plans

---
*Phase: 09-activationstore-integration-and-guards*
*Completed: 2026-03-19*
