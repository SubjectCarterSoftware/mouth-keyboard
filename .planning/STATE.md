---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Convert Modes
current_plan: 07-02
status: ready_to_execute
stopped_at: Completed 07-01-PLAN.md
last_updated: "2026-03-19T16:45:31.940Z"
last_activity: 2026-03-19
progress:
  total_phases: 10
  completed_phases: 6
  total_plans: 16
  completed_plans: 15
  percent: 94
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-18)

**Core value:** From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.
**Current focus:** Phase 7 — Core Types and Intent Detection

## Current Position

Phase: 7 of 10 (Core Types and Intent Detection)
Current Plan: 2
Total Plans in Phase: 2
Status: Ready to execute Plan 2
Last Activity: 2026-03-19
Progress: [█████████░] 94%

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
| Phase 06-dependency-integration-and-build-gate P01 | 20 | 4 tasks | 4 files |
| Phase 07-core-types-and-intent-detection P01 | 5 min | 2 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: LLM-02 (passthrough unchanged) is verified in Phase 9, not Phase 6 — Phase 6 confirms no regression from adding the SPM dependency; Phase 9 verifies the behavior is preserved through ActivationStore integration
- [Roadmap]: GUARD-02 (LLM failure fallback) spans Phase 8 (error contract defined in LLMRewriteService) and Phase 9 (fallback wired in ActivationStore) — assigned to Phase 8 for traceability, verified in Phase 9 success criteria
- [Research]: swift-transformers version conflict (WhisperKit 0.17.0 pins 1.1.x, mlx-swift-lm requires 1.2.0+) is a go/no-go gate — must resolve before Phase 6 plan execution
- [Research]: Metal shaders require xcodebuild; swift build will silently miss default.metallib — CI constraint must be documented in Phase 6
- [Research]: LLM inference must never run on @MainActor — LLMRewriteService actor pattern mirrors WhisperService
- [Phase 06-dependency-integration-and-build-gate]: mlx-swift-lm 2.30.6 uses upToNextMinorVersion; swift-transformers conflict did not materialize; Package.resolved committed for reproducible builds
- [Phase 07-core-types-and-intent-detection]: ConvertMode owns activationPhraseCandidates so future detector callers can consume mode contracts directly.
- [Phase 07-core-types-and-intent-detection]: Plan 01 remains intentionally RED: IntentDetector.detect stays passthrough until Plan 02 turns the corpus green.

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 6 gate]: swift-transformers version conflict between WhisperKit 0.17.0 and mlx-swift-lm 2.30.6 must be resolved before any LLM code is written. Check WhisperKit release notes first; fallback is vendoring MLXLLM/MLXLMCommon source.
- [Phase 8 flag]: ChatSession per-call vs. per-session lifetime needs validation against mlx-swift-lm 2.30.6 before Phase 8 implementation begins.
- [Phase 10 flag]: swift-transformers issue #335 (download progress handler) needs validation against current 1.2.0 release before Phase 10 planning begins.

## Session Continuity

Last session: 2026-03-19T16:45:31.929Z
Stopped at: Completed 07-01-PLAN.md
Resume file: .planning/phases/07-core-types-and-intent-detection/07-02-PLAN.md
