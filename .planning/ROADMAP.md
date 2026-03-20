# Roadmap: Speech2Test

## Milestones

- ✅ **v1.0** - Phases 1-5 (shipped 2026-03-08) — See `.planning/milestones/v1.0-ROADMAP.md`
- ✅ **v1.1 Convert Modes** - Phases 6-11 (shipped 2026-03-20) — See `.planning/milestones/v1.1-ROADMAP.md`
- 🚧 **v1.2 AI Trigger Name** - Phases 12-15 (in progress)

## Archived Milestones

<details>
<summary>✅ v1.0 — Phases 1-5 — SHIPPED 2026-03-08</summary>

See full detail: `.planning/milestones/v1.0-ROADMAP.md`

Phases 1-5 shipped (13/13 plans complete).

</details>

<details>
<summary>✅ v1.1 Convert Modes — Phases 6-11 — SHIPPED 2026-03-20</summary>

See full detail: `.planning/milestones/v1.1-ROADMAP.md`

Phases 6-11 shipped (15/15 plans complete).

</details>

## 🚧 v1.2 AI Trigger Name (In Progress)

**Milestone Goal:** Replace full-transcript fuzzy command scanning with a named AI trigger boundary (`Zeus` default) so instructions are interpreted only after the trigger name.

### Phase 12: Trigger Identity and Persistence
**Goal**: Add AI assistant identity model with predefined names + custom name, persistence, and calibration-ready alias storage.
**Depends on**: Phase 11
**Requirements**: TRIG-01, TRIG-02, TRIG-03, TRIG-04, CAL-01, CAL-02
**Success Criteria** (what must be TRUE):
  1. Default trigger profile (`Zeus`) is available on first launch with zero configuration
  2. User can switch to predefined names (`Zeus`, `Atlas`, `Gaia`) and persist selection
  3. User can save custom trigger name and normalized alias list in persistent store
  4. Existing convert-mode configuration remains intact after trigger profile updates
**Plans**: 2 plans

Plans:
- [x] 12-01-PLAN.md — Data model + persistence for trigger profile (primary + aliases) with unit coverage
- [x] 12-02-PLAN.md — Calibration capture contract and alias normalization pipeline (test-first)

### Phase 13: Last-Name-Wins Parser Integration
**Goal**: Implement transcript split pipeline that finds last trigger alias and emits content + instruction segments with safety gates.
**Depends on**: Phase 12
**Requirements**: CAL-03, PARSE-01, PARSE-02, PARSE-03, PARSE-04, PARSE-05
**Success Criteria** (what must be TRUE):
  1. Last occurrence of any trigger alias is used as split boundary
  2. Content segment always includes only pre-trigger text
  3. Empty or too-short instruction segment does not activate AI rewrite path
  4. No-trigger transcripts preserve current passthrough behavior with no regressions
  5. Existing corpus includes coverage for repeated trigger mentions and false-positive content mentions
**Plans**: 2 plans

Plans:
- [x] 13-01-PLAN.md — Introduce trigger-aware split types and RED corpus for boundary rules
- [x] 13-02-PLAN.md — Implement parser + ActivationStore integration for split outputs and gates

### Phase 14: Instruction Routing via Existing Intents
**Goal**: Route post-trigger instructions through fuzzy intent shortcuts first, then custom-instruction LLM fallback, preserving existing guards.
**Depends on**: Phase 13
**Requirements**: ROUTE-01, ROUTE-02, ROUTE-03, ROUTE-04
**Success Criteria** (what must be TRUE):
  1. Post-trigger instruction can select existing predefined modes via fuzzy shortcut matching
  2. Unmatched post-trigger instruction routes to custom rewrite instruction path
  3. Word-limit and silent-fallback guarantees remain unchanged for trigger-based flows
  4. End-to-end tests verify both shortcut and custom instruction paths from spoken transcript input
**Plans**: 2 plans

Plans:
- [ ] 14-01-PLAN.md — Wire split instruction into intent shortcut resolver with deterministic tests
- [ ] 14-02-PLAN.md — Add custom instruction fallback path and regression tests for guards

### Phase 15: Settings UX for AI Assistant Name
**Goal**: Ship settings tile + change flow for assistant name selection and calibration entry point, with end-to-end verification.
**Depends on**: Phase 14
**Requirements**: SETT-01, SETT-02, SETT-03
**Success Criteria** (what must be TRUE):
  1. Settings displays active assistant name in dedicated AI Assistant tile
  2. User can switch predefined/custom names through settings flow
  3. Calibration entry point is available and updates stored aliases
  4. Manual verification confirms trigger change affects runtime parsing without app restart
**Plans**: 2 plans

Plans:
- [ ] 15-01-PLAN.md — Build settings tile + configuration flow UI with view-model tests
- [ ] 15-02-PLAN.md — End-to-end verification and UX polish for trigger-name configuration

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation and Permissions | v1.0 | 2/2 | Complete | 2026-03-08 |
| 2. Activation and Capture | v1.0 | 3/3 | Complete | 2026-03-08 |
| 3. Recognition and Clipboard Loop | v1.0 | 3/3 | Complete | 2026-03-08 |
| 4. Recovery Controls | v1.0 | 2/2 | Complete | 2026-03-08 |
| 5. Long-Dictation Reliability | v1.0 | 3/3 | Complete | 2026-03-08 |
| 6. Dependency Integration and Build Gate | v1.1 | 1/1 | Complete | 2026-03-19 |
| 7. Core Types and Intent Detection | v1.1 | 2/2 | Complete | 2026-03-19 |
| 8. LLM Rewrite Service | v1.1 | 2/2 | Complete | 2026-03-19 |
| 9. ActivationStore Integration and Guards | v1.1 | 3/3 | Complete | 2026-03-19 |
| 10. Fuzzy Intent Detection | v1.1 | 2/2 | Complete | 2026-03-20 |
| 11. Intent Configuration UI | v1.1 | 5/5 | Complete | 2026-03-20 |
| 12. Trigger Identity and Persistence | 2/2 | Complete    | 2026-03-20 | - |
| 13. Last-Name-Wins Parser Integration | 2/2 | Complete   | 2026-03-20 | - |
| 14. Instruction Routing via Existing Intents | v1.2 | 0/2 | Planned | - |
| 15. Settings UX for AI Assistant Name | v1.2 | 0/2 | Planned | - |

---
*Last updated: 2026-03-20 after v1.2 requirements and roadmap draft*
