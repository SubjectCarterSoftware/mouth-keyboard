# Phase 14: Instruction Routing via Existing Intents - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Route post-trigger instruction text through existing predefined intent shortcuts first, then custom-instruction LLM fallback when no shortcut matches, while preserving existing conversion guards (word-limit gate and silent raw fallback behavior).

</domain>

<decisions>
## Implementation Decisions

### Built-In Shortcut Match Policy
- Shortcut matching should be conservative: only high-confidence matches route to built-in modes.
- If instruction mixes mode keywords with additional style language (for example, "email this but keep it casual and short"), prefer custom-instruction fallback over forcing a built-in mode.
- Built-in shortcut detection should only fire when command phrasing appears at the end of the post-trigger instruction.
- If built-in scores are ambiguous (tie/near-tie), do not choose a shortcut; route to custom instructions.

### Carry-Forward Contracts (Already Decided)
- Trigger segmentation remains unchanged: only the post-trigger instruction segment is evaluated for routing.
- No-trigger and invalid-trigger sessions remain passthrough behavior.
- Existing conversion guards remain intact: 350-word gate and silent raw-transcript fallback on LLM rewrite failure.

### Claude's Discretion
- Exact confidence threshold/margin tuning used to enforce conservative shortcut matching.
- Exact tie/near-tie scoring margin constant and where it is applied.
- Exact internal helper/type structure for end-position-only shortcut evaluation.
- Exact test corpus wording for end-position, ambiguous-score, and mixed-intent edge cases.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Speech2Text/Activation/ActivationStore.swift`: current routing control point where trigger split output and intent resolution are already integrated.
- `Speech2Text/Activation/TriggerTranscriptParser.swift`: provides valid/invalid/no-trigger split outcomes and minimum-instruction guard.
- `Speech2Text/Conversion/IntentDetector.swift`: existing fuzzy scoring pipeline and zone-based command detection behavior.
- `Speech2Text/Conversion/IntentCatalog.swift`: built-in intent definitions and effective merged catalog from user overrides/custom entries.
- `Speech2TextTests/ActivationStoreTests.swift` and `Speech2TextTests/IntentDetectorTests.swift`: established unit-test patterns for routing and guard behavior.

### Established Patterns
- Routing decisions are centralized in `ActivationStore.finalizeSession` after parser split and store snapshot.
- Built-in vs custom rewrite path is already distinguished by `ConvertIntent.customIntentID` and resolved instructions lookup.
- Guard behavior (word limit + silent fallback) is enforced in ActivationStore before/around LLM calls.
- Intent matching relies on deterministic normalization/scoring helpers and is tested with focused corpus-style unit tests.

### Integration Points
- Phase 14 implementation should adjust only post-trigger instruction routing branch (`.validTrigger`) while preserving passthrough behavior for `.noTrigger` and `.invalidTrigger`.
- End-of-instruction shortcut requirement likely maps to `IntentDetector` zone/position logic used by ActivationStore for instruction-only detection.
- Ambiguous-match handling should feed directly into custom-instruction rewrite path, not raw passthrough.

</code_context>

<specifics>
## Specific Ideas

- Prioritize avoiding accidental built-in mode routing when users speak natural mixed instructions after the trigger name.
- Make custom fallback the default safety valve when shortcut confidence is not clearly decisive.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>

---

*Phase: 14-instruction-routing-via-existing-intents*
*Context gathered: 2026-03-20*
