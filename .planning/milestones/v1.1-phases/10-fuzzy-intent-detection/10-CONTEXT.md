# Phase 10: Fuzzy Intent Detection - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning
**Source:** PRD Express Path (10-PRD.md)

<domain>
## Phase Boundary

Replace `IntentDetector.swift` and its exact-phrase matching logic with a config-driven normalization + fuzzy matching classifier. The new detector handles natural speech variation, filler words, and common paraphrase patterns for all conversion intents. The remaining stack (`ConvertMode`, `ConvertIntent`, `LLMRewriteService`, `ActivationStore`) is unchanged. The `detect(transcript:modes:)` call site stays; only the internals of detection are replaced.

</domain>

<decisions>
## Implementation Decisions

### Supported Intents
- Email, Slack, Teams, Action Items, AI Prompt — the 5 explicitly named intents in the PRD
- Note: Clean English exists in `ConvertMode.allBuiltIns` but is not called out in the PRD — planner should verify against REQUIREMENTS.md and include it if needed

### Intent Catalog Shape (config-driven)
- Each intent definition contains: `id` (maps to `ConvertMode`), `aliases` (display names / canonical names), `phrasePatterns` (list of strings to match against), `confidenceThreshold` (per-intent, not global)
- Adding a new intent = adding a new entry to the catalog, no matching logic changes
- Phrase pattern examples for Email: "make this an email", "turn this into an email", "rewrite as an email", "as email", "email mode", "send as email", "format as email"
- Similar pattern lists required for Slack, Teams, Action Items, AI Prompt

### Normalization (applied before any matching)
- Lowercase entire transcript
- Trim and collapse whitespace
- Strip punctuation at boundaries (periods, commas, question marks, exclamation marks)
- Standardize known variants: "e mail" → "email", "action item" → "action items", "a i prompt" → "ai prompt"
- Remove filler words from candidate zones: "okay", "please", "can you", "real quick", "uh", "um" — applied only around likely command spans, not the full transcript body

### Command Zone Strategy
- Do NOT scan the full transcript equally
- Inspect two zones only: the beginning (first N tokens) and the end (last N tokens)
- Exact token window size is Claude's discretion (e.g., first/last 8–12 tokens)
- Each zone is normalized and compared independently against all intent patterns
- Position bonus applied when match is found in a zone (start or end)

### Scoring and Confidence
- Step 1: Exact normalized match or regex-pattern match → highest confidence
- Step 2 (if no exact match): fuzzy string similarity — pure Swift implementation (Jaro-Winkler or Levenshtein), no external library
- Composite score considers: phrase similarity, token overlap with intent keywords, presence of the target keyword (e.g., "email", "slack"), position bonus (start/end)
- Auto-trigger only if: top score exceeds per-intent threshold AND top score beats second-best by a minimum margin
- If confidence too low OR ambiguous (two intents close in score): passthrough — no transformation, raw transcript to clipboard unchanged

### Span Removal
- Once intent is detected, the matched command span is identified and removed from the transcript
- Remaining text (after span removal and trimming) = `strippedBody` passed to LLM
- `originalTranscript` is preserved (existing `ConvertIntent` contract unchanged)

### What Gets Replaced vs. Preserved
- **Replaced**: `IntentDetector.swift` internals, `ConvertMode.activationPhraseCandidates` property
- **Preserved**: `ConvertMode` enum shape, `ConvertIntent` struct, `LLMRewriting` protocol, `LLMRewriteService`, `ActivationStore` wiring, `IntentDetector.detect(transcript:modes:)` method signature (call site unchanged)
- The `detect()` signature staying the same means `ActivationStore` requires zero changes

### Fuzzy Matching Implementation
- Pure Swift — no external dependency
- Implement Jaro-Winkler similarity or Levenshtein distance directly (~50 lines)
- Applied at the zone level (short candidate string vs. short pattern strings) — not full-transcript comparison

### Claude's Discretion
- Exact token window size for command zones
- Specific similarity algorithm choice (Jaro-Winkler vs. Levenshtein vs. normalized combination)
- Numeric confidence thresholds and minimum margin values
- Complete pattern lists for each intent (beyond examples given)
- Whether Clean English is included or left as passthrough
- Internal scoring weight distribution (similarity vs. keyword presence vs. position bonus)
- Test corpus design — should reflect realistic Whisper output variation

</decisions>

<specifics>
## Specific Ideas

- The intent catalog should be a static/constant structure (e.g., `IntentCatalog.all`) — not loaded from disk, not user-editable in this phase
- Email example patterns: "make this an email", "turn this into an email", "rewrite as an email", "as email", "email mode"
- The system must not false-positive on normal speech that mentions "email" incidentally (e.g., "I got an email about this") — position bonus and threshold margin are the guard
- Filler word stripping should apply locally around the command zone, not globally (don't strip "um" from the dictation body)

</specifics>

<deferred>
## Deferred Ideas

- User-editable intent pattern lists (settings panel) — future phase
- Fuzzy matching as LLM fallback for borderline confidence cases — explicitly deferred per PRD
- Import/export of intent catalogs — future
- Clean English intent inclusion — verify against requirements; include if it exists in ConvertMode.allBuiltIns

</deferred>

---

*Phase: 10-fuzzy-intent-detection*
*Context gathered: 2026-03-19 via PRD Express Path*
