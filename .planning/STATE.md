---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: AI Trigger Name
status: Complete
stopped_at: v1.2 milestone archived
last_updated: "2026-03-20T19:11:48.975Z"
last_activity: 2026-03-20 — v1.2 AI Trigger Name milestone shipped and archived
progress:
  total_phases: 4
  completed_phases: 4
  total_plans: 9
  completed_plans: 9
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.
**Current focus:** v1.2 complete. Plan next milestone with `$gsd-new-milestone`.

## Current Position

Phase: — (milestone complete)
Plan: —
Status: Complete
Last activity: 2026-03-20 — v1.2 AI Trigger Name shipped and archived

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
| Phase 14 P01 | 8m | 2 tasks | 4 files |
| Phase 14-instruction-routing-via-existing-intents P02 | 7 min | 2 tasks | 3 files |
| Phase 15 P01 | 33m | 2 tasks | 6 files |
| Phase 15 P02 | 12m | 2 tasks | 5 files |
| Phase 15-settings-ux-for-ai-assistant-name P02 | ~20min | 3 tasks | 5 files |

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
- [Phase 14]: Use a dedicated detectPredefinedShortcut path for valid-trigger built-ins instead of changing general detector semantics.
- [Phase 14]: Reject ambiguous built-in routing when multiple exact built-in commands are present in the post-trigger instruction.
- [Phase 14]: Preserve custom-intent detection as fallback when no predefined built-in shortcut is selected.
- [Phase 14-instruction-routing-via-existing-intents]: Used ConvertIntent.effectiveSystemPrompt to carry post-trigger instruction text into rewrite(body:instructions:) fallback.
- [Phase 14-instruction-routing-via-existing-intents]: Preserved existing custom-intent definition routing when matched; unresolved valid-trigger cases use instruction-text fallback.
- [Phase 15]: CalibrationCapturingDone error type used as exit sentinel so runSession() terminates cleanly when capturer exhausts samples
- [Phase 15]: AIAssistantSettingsViewModel pendingSelection tracks sheet state separately from activeTriggerProfile; preset rows show selection without triggering store write
- [Phase 15]: UI tests use temporary /tmp/Speech2Text.UITests/ store (deleted on each launch) to isolate trigger-profile state from real Application Support store
- [Phase 15]: -seed-trigger-preset and -seed-trigger-profile-calibrated launch args seed isolated trigger-profile state for UI tests without touching production storage
- [Phase 15-settings-ux-for-ai-assistant-name]: UI tests use temporary /tmp/Speech2Text.UITests/ store (deleted on each launch) to isolate trigger-profile state from real Application Support store
- [Phase 15-settings-ux-for-ai-assistant-name]: -seed-trigger-preset and -seed-trigger-profile-calibrated launch args seed isolated trigger-profile state for UI tests without touching production storage
- [Phase 15-settings-ux-for-ai-assistant-name]: LiveCalibrationSampleCapturer uses @MainActor final class; captureSample returns nil on most errors, throws CalibrationCapturingDone.exhausted only on microphonePermissionDenied
- [Phase 15-settings-ux-for-ai-assistant-name]: isCalibrationRequired consumed in AIAssistantSettingsView button label as (Recommended) hint to close dead-state anti-pattern

### Pending Todos

None yet.

### Blockers/Concerns

- [Unresolved pre-existing failures]: HotkeyServiceTests.testDefaultActivationShortcutIsControlV and ShellPreferencesModelTests.testLaunchAtLoginDefaultsToFalse — out of scope, need separate attention.

## Session Continuity

Last session: 2026-03-20T18:49:36.641Z
Stopped at: Completed 15-03-PLAN.md
Resume file: None
