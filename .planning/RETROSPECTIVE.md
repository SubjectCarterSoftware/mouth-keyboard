# Retrospective: Speech2Test

## Milestone: v1.2 — AI Trigger Name

**Shipped:** 2026-03-20
**Phases:** 4 | **Plans:** 9

### What Was Built

- Named AI trigger identity (Zeus/Atlas/Gaia + custom) with durable file-backed persistence isolated from convert-mode store
- Three-sample voice calibration pipeline with `TriggerAliasNormalizer` and profile-scoped alias replacement
- Last-name-wins transcript parser with whole-word boundary detection and typed `TriggerTranscriptSplit` contract
- Parser gated into `ActivationStore.finalizeSession` — intent routing sees only post-trigger instruction segment
- Conservative predefined shortcut resolver; unmatched valid-trigger instructions fall back to custom LLM rewrite
- AI Assistant settings tile + sheet + `LiveCalibrationSampleCapturer` for production audio calibration

### What Worked

- **Test-first cadence held throughout**: every plan opened with RED corpus before implementation. Caught boundary edge cases (whole-word matching, trailing-position classification) before integration.
- **Typed split contract (`TriggerTranscriptSplit`)**: defining the enum first made all downstream integration obvious — `ActivationStore` switch over cases was clean and exhaustive.
- **Protocol-based calibration seam (`CalibrationSampleCapturing`)**: decoupled runner from live audio, making all 7 calibration runner tests deterministic without microphone access.
- **Save-before-publish pattern**: applying it consistently across all trigger mutations prevented half-applied state issues entirely — no runtime correction needed.
- **Focused phases (2-3 tasks each)**: Phase 12 through Phase 14 averaged under 10 minutes each. Small scope = fast feedback.

### What Was Inefficient

- **Phase 15 took 3 plans instead of the intended 2**: SETT-03 calibration wiring was split into a gap-closure plan (15-03) after 15-01 and 15-02 were already executed. Could have been scoped into 15-01 originally.
- **Redundant ViewModel allocation bug (15-02)**: `AIAssistantTileView` accumulated a dead `viewModel` computed property alongside the `let vm` in body. Standard SwiftUI @StateObject pattern would have avoided this.
- **`countAccepted()` always returns 0**: the callback contract was defined but the implementation was left hollow. This wasn't caught until the audit. The UI self-healed via a local counter, hiding the defect.

### Patterns Established

- **Protocol-based audio seam**: `CalibrationSampleCapturing` + `CalibrationCapturingDone` exit sentinel — reuse this for any future live-capture feature that needs deterministic tests.
- **Trigger-profile isolation in tests**: `-seed-trigger-preset` / `-seed-trigger-profile-calibrated` launch args + `/tmp/Speech2Test.UITests/` temp store — template for any future feature with persistent app state.
- **Separate detection paths for different routing contexts**: `detectPredefinedShortcut` is completely separate from the general `detect` path. Avoids unintended coupling between trigger-gated and non-trigger intent detection.
- **Save-before-publish**: always write to the persistent store before updating `@Published` properties in `ShellPreferences`.

### Key Lessons

1. **Scope calibration entry points explicitly**: if a feature has a "live production" step (real microphone, real camera, etc.), plan for it as its own task rather than hoping it fits inside the verification plan.
2. **Callback contract should be validated at implementation time**: if a function returns a count or carries data in a callback, add an assertion or test for its correctness at the same time. Don't leave it for the audit.
3. **SwiftUI `@StateObject` vs `let vm` in `body`**: SwiftUI views that create objects in `body` re-allocate on every render. Reserve `body` for layout; place `ObservableObject` instances in `@StateObject` properties.

### Cost Observations

- All 9 plans executed in a single session on 2026-03-20
- ~94 minutes total execution across all phases
- Notable: Phases 12-14 averaged ~7-9 min per plan; Phase 15 averaged ~16 min per plan (UI work is slower)

---

## Cross-Milestone Trends

### Velocity by Milestone

| Milestone | Phases | Plans | Est. Execution | Avg/Plan |
|-----------|--------|-------|----------------|----------|
| v1.0 | 5 | 13 | ~3h | ~14 min |
| v1.1 | 6 | 15 | ~3h | ~12 min |
| v1.2 | 4 | 9 | ~1.5h | ~10 min |

### Recurring Patterns

- Test-first (RED before GREEN) has held across all three milestones — no regressions introduced during implementation phases.
- Auto-fixed bugs in implementation plans: every milestone has had 1-2 edge case fixes discovered during Task 2 and committed inline. This is expected, not a problem.
- UI plans are consistently 2-3x slower than pure logic/persistence plans.

### Recurring Inefficiencies

- Scope that touches live hardware (microphone, in v1.2) tends to slip out of the primary plan into a follow-up.
- Stale documentation (traceability tables, ROADMAP plan checkboxes) accumulates across milestones — audit catches it but it's manual cleanup every time.
