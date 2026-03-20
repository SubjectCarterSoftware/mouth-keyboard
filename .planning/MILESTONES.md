# Milestones

## v1.2 AI Trigger Name (Shipped: 2026-03-20)

**Phases completed:** 4 phases, 9 plans
**Stats:** 35 commits | 40 files | +4,619/−102 lines | ~94 min execution

**Key accomplishments:**
- Named AI trigger identity (Zeus/Atlas/Gaia + custom) with durable file-backed persistence isolated from convert-mode store
- Three-sample voice calibration pipeline with `TriggerAliasNormalizer` and profile-scoped alias replacement
- Last-name-wins transcript parser with whole-word boundary detection; content/instruction split typed as `TriggerTranscriptSplit`
- Parser gated into `ActivationStore.finalizeSession` — intent routing sees only post-trigger instruction segment
- Conservative predefined shortcut resolver; unmatched valid-trigger instructions fall back to custom LLM rewrite
- AI Assistant settings tile + sheet + `LiveCalibrationSampleCapturer` for production audio calibration
- 97 unit tests + 14 UI tests, 0 failures at milestone close

---

## v1.1 Convert Modes (Shipped: 2026-03-20)

**Phases completed:** 11 phases, 28 plans, 0 tasks

**Key accomplishments:**
- (none recorded)

---

