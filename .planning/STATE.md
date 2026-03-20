---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: AI Trigger Name
status: Ready
stopped_at: Completed 13-02-PLAN.md
last_updated: "2026-03-20T16:07:33.621Z"
last_activity: 2026-03-20 — completed 13-02 parser-gated ActivationStore integration plan
progress:
  total_phases: 4
  completed_phases: 2
  total_plans: 4
  completed_plans: 4
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.
**Current focus:** Begin v1.2 Phase 14 instruction routing work (14-01 next).

## Current Position

Phase: 14 of 15 (Instruction Routing via Existing Intents)
Plan: 01 of 02 (14-01-PLAN.md next)
Status: Ready
Last activity: 2026-03-20 — completed 13-02 parser-gated ActivationStore integration plan

## Performance Metrics

**Velocity (v1.0 reference):**
- Total plans completed: 13 (v1.0)
- Average duration: ~25 min (excluding multi-session 02-03)
- Total execution time: ~3h 03m

**By Phase (v1.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 foundation-and-permissions | 2 | — | — |
| 02 activation-and-capture | 3 | ~2h | ~40m |
| 03 recognition-and-clipboard-loop | 3 | ~22m | ~7m |
| 04 recovery-controls | 2 | ~5h | ~2.5h |
| 05 long-dictation-reliability | 3 | ~63m | ~21m |

**By Phase (v1.1):**

| Phase | Plans | Duration | Tasks | Files |
|-------|-------|----------|-------|-------|
| 06-dependency-integration-and-build-gate | 1 | 20m | 4 | 4 |
| 07-core-types-and-intent-detection | 2 | 9m | 4 | 7 |
| 08-llm-rewrite-service | 2 | 35m | 5 | 9 |
| 09-activationstore-integration-and-guards | 3 | 43m | 8 | 12 |
| 10-fuzzy-intent-detection | 2 | ~16m | 4 | 11 |
| 11-intent-configuration-ui | 5 | ~63m | 10 | 21 |
| Phase 12 P01 | 9 min | 2 tasks | 7 files |
| Phase 12 P02 | 5 min | 2 tasks | 10 files |
| Phase 13 P01 | 6 min | 2 tasks | 4 files |
| Phase 13 P02 | 9 min | 2 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Milestone v1.2] Named trigger boundary replaces whole-transcript fuzzy command scanning.
- [Milestone v1.2] Last-occurrence trigger split (`last-name-wins`) avoids false activation from earlier mentions.
- [Phase 10-fuzzy-intent-detection]: IntentCatalog now drives IntentDetector phrase matching; activationPhraseCandidates removed from ConvertMode.
- [Phase 10-fuzzy-intent-detection]: Windowed token JW (not full-string JW) aligns individual tokens; 3-token minimum prevents 2-token pattern false positives; exact-match priority in scoreAllZone discards fuzzy competitors when exact wins exist.
- [Phase 11-01]: UserIntentStore uses actor isolation; all mutation serialized via Swift concurrency.
- [Phase 11-03]: allEntries() snapshot taken once at session-start; passthrough check updated for custom intents.
- [Phase 11-03]: Dual-path LLM routing: instructions overload for user-configured intents, mode overload for defaults.
- [Phase 12]: Trigger identity persistence is isolated in a dedicated file-backed store separate from convert-mode UserDefaults keys.
- [Phase 12]: ShellPreferences applies trigger profile mutations only after store writes succeed to prevent half-applied runtime state.
- [Phase 12]: Centralized alias normalization in TriggerAliasNormalizer and routed TriggerProfile normalization through it.
- [Phase 12]: Calibration aliases apply in ShellPreferences only after TriggerProfileStore write succeeds to avoid half-applied runtime state.
- [Phase 13]: Parser normalizes active aliases and uses case-insensitive matching before boundary selection.
- [Phase 13]: Trigger boundaries use whole-word matching so alias substrings do not activate parsing.
- [Phase 13]: ActivationStore now routes intent detection only from TriggerTranscriptParser validTrigger instruction segments.
- [Phase 13]: IntentDetector trailing-position heuristics now use matched range lower bounds to avoid false trailing classification.

### Pending Todos

None yet.

### Blockers/Concerns

- [Unresolved pre-existing failures]: HotkeyServiceTests.testDefaultActivationShortcutIsControlV and ShellPreferencesModelTests.testLaunchAtLoginDefaultsToFalse — out of scope, need separate attention.

## Session Continuity

Last session: 2026-03-20T16:07:33.619Z
Stopped at: Completed 13-02-PLAN.md
Resume file: None
