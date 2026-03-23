# Roadmap: Speech2Test

## Milestones

- ✅ **v1.0** — Phases 1-5 (shipped 2026-03-08) — See `.planning/milestones/v1.0-ROADMAP.md`
- ✅ **v1.1 Convert Modes** — Phases 6-11 (shipped 2026-03-20) — See `.planning/milestones/v1.1-ROADMAP.md`
- ✅ **v1.2 AI Trigger Name** — Phases 12-15 (shipped 2026-03-20) — See `.planning/milestones/v1.2-ROADMAP.md`
- 🔄 **v1.3 Qwen 3.5 LLM Upgrade** — Phases 16-19

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

<details>
<summary>✅ v1.2 AI Trigger Name — Phases 12-15 — SHIPPED 2026-03-20</summary>

See full detail: `.planning/milestones/v1.2-ROADMAP.md`

Phases 12-15 shipped (9/9 plans complete). Named trigger boundary, voice calibration, last-name-wins parsing, predefined shortcut routing, custom LLM fallback, and AI Assistant settings UI.

</details>

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
| 12. Trigger Identity and Persistence | v1.2 | 2/2 | Complete | 2026-03-20 |
| 13. Last-Name-Wins Parser Integration | v1.2 | 2/2 | Complete | 2026-03-20 |
| 14. Instruction Routing via Existing Intents | v1.2 | 2/2 | Complete | 2026-03-20 |
| 15. Settings UX for AI Assistant Name | v1.2 | 3/3 | Complete | 2026-03-20 |
| 16. Diagnostic Logging and Error Visibility | v1.3 | 0/2 | Not started | — |
| 17. Model Loading and Configuration Fix | v1.3 | 0/2 | Not started | — |
| 18. Generation Pipeline and Chat Template Fix | v1.3 | 0/2 | Not started | — |
| 19. Tier Selector Validation and End-to-End Test | v1.3 | 0/2 | Not started | — |

## Phase Details — v1.3 Qwen 3.5 LLM Upgrade

### Phase 16: Diagnostic Logging and Error Visibility
**Goal:** Replace silent error fallback with structured, visible error reporting so failures are diagnosable.
**Requirements:** LLM-04
**Success criteria:**
1. User sees differentiated pill state when rewrite fails (not identical to raw-transcript success)
2. NSLog captures the specific error type (modelLoadFailed, generationFailed, emptyOutput, etc.)
3. Error information helps identify which stage of the pipeline failed
4. Existing tests continue to pass

### Phase 17: Model Loading and Configuration Fix
**Goal:** Ensure Qwen 3.5 models load correctly via `LLMModelFactory` with proper config handling.
**Requirements:** LLM-01, LLM-02, LLM-03, MDL-03
**Success criteria:**
1. `Qwen35TextModel` loads from local directory without crash for the 2B tier
2. `ModelConfiguration` correctly propagates EOS token IDs from the downloaded model config
3. WhisperKit and MLXLLM coexist without loading conflicts (both can be warm simultaneously)
4. Model warm state is detectable via `loadedTier()` after successful load

### Phase 18: Generation Pipeline and Chat Template Fix
**Goal:** Ensure the ChatSession produces valid rewritten output with Qwen 3.5 models.
**Requirements:** LLM-01, LLM-02, LLM-03
**Success criteria:**
1. Chat template renders correctly with system prompt (instructions) and user content (body)
2. Thinking mode is disabled or think-tags are stripped from output
3. Generation stops at the correct EOS token and returns trimmed non-empty text
4. Rewritten output appears in clipboard when trigger (Zeus) activates

### Phase 19: Tier Selector Validation and End-to-End Test
**Goal:** Validate that the settings tier selector works for all three tiers and switching produces correct behavior.
**Requirements:** MDL-01, MDL-02
**Success criteria:**
1. User can select 2B, 4B, or 9B tier in settings and the preference persists
2. Downloading a new tier shows progress and completes successfully
3. Switching tiers invalidates cached model and loads the new tier on next rewrite
4. All three tiers produce valid rewrite output when invoked via trigger

---
*Last updated: 2026-03-23 — v1.3 Qwen 3.5 LLM Upgrade roadmap created*
