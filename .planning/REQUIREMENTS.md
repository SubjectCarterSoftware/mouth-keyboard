# Requirements: Speech2Test

**Defined:** 2026-03-20
**Milestone:** v1.2 AI Trigger Name
**Core Value:** From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.

## v1.2 Requirements

### Trigger Identity

- [x] **TRIG-01**: AI mode works out of the box with default assistant name `Zeus` (no setup required)
- [x] **TRIG-02**: User can switch assistant name to one of 3 predefined choices: `Zeus`, `Atlas`, `Gaia`
- [x] **TRIG-03**: User can configure a custom assistant name and save it as the active trigger
- [x] **TRIG-04**: Trigger configuration persists across app relaunches and is available at session finalize time

### Voice Calibration

- [x] **CAL-01**: User can run a calibration flow that captures multiple spoken samples for the active trigger name
- [x] **CAL-02**: System stores a normalized primary trigger plus accepted alias transcriptions from calibration
- [x] **CAL-03**: Detection uses both primary trigger and aliases (case-insensitive)

### Transcript Split and Parsing

- [x] **PARSE-01**: Transcript is split at the last occurrence of any trigger alias (`last-name-wins`)
- [x] **PARSE-02**: All text before the split is treated as content; only text after the split is treated as instruction
- [x] **PARSE-03**: If no trigger alias is detected, behavior is passthrough (existing no-trigger path unchanged)
- [x] **PARSE-04**: If instruction segment is empty or below minimum token threshold, AI mode is not activated
- [x] **PARSE-05**: Mentions of trigger names in content do not activate AI mode unless a valid post-trigger instruction exists

### Instruction Interpretation and Routing

- [x] **ROUTE-01**: Post-trigger instruction is fuzzy-matched against existing predefined intents (Email, Slack, Teams, Clean English)
- [x] **ROUTE-02**: If predefined match succeeds, matching intent mode is executed with existing prompt pipeline
- [x] **ROUTE-03**: If no predefined match succeeds, instruction is passed as custom rewrite instructions to LLM
- [x] **ROUTE-04**: Existing guards still apply (word-limit gate and silent raw fallback on LLM failure)

### Settings UX

- [x] **SETT-01**: Settings shows an AI Assistant tile indicating current active assistant name
- [x] **SETT-02**: User can open an assistant configuration flow from settings and change predefined or custom name
- [x] **SETT-03**: Calibration entry point is available from the same assistant configuration flow

## Out of Scope (v1.2)

| Feature | Reason |
|---------|--------|
| Multi-assistant profiles with per-profile prompts | Adds profile management complexity beyond this milestone |
| Wake-word audio detection before transcription | Current architecture is transcript-level parsing after Whisper |
| Cloud profile sync for trigger settings | Local-first configuration remains the product default |
| Replacing existing convert-mode editor UX | v1.2 adds trigger-name controls; mode editing stays as shipped |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TRIG-01 | Phase 12 | Planned |
| TRIG-02 | Phase 12 | Planned |
| TRIG-03 | Phase 12 | Planned |
| TRIG-04 | Phase 12 | Planned |
| CAL-01 | Phase 12 | Planned |
| CAL-02 | Phase 12 | Planned |
| CAL-03 | Phase 13 | Complete |
| PARSE-01 | Phase 13 | Complete |
| PARSE-02 | Phase 13 | Complete |
| PARSE-03 | Phase 13 | Complete |
| PARSE-04 | Phase 13 | Complete |
| PARSE-05 | Phase 13 | Complete |
| ROUTE-01 | Phase 14 | Complete |
| ROUTE-02 | Phase 14 | Complete |
| ROUTE-03 | Phase 14 | Complete |
| ROUTE-04 | Phase 14 | Complete |
| SETT-01 | Phase 15 | Planned |
| SETT-02 | Phase 15 | Planned |
| SETT-03 | Phase 15 | Planned |

**Coverage:**
- v1.2 requirements: 19 total
- Mapped to phases: 19
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 — Phase 14 routing requirements completed*
