# Phase 13: Last-Name-Wins Parser Integration - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement transcript splitting against the active trigger alias set so AI routing only evaluates text after the last valid trigger occurrence. This phase delivers parser contracts and ActivationStore integration gates, but does not implement instruction-to-intent routing strategy (Phase 14) or settings UI (Phase 15).

</domain>

<decisions>
## Implementation Decisions

### Trigger Matching Contract
- Matching must be case-insensitive over normalized aliases from `activeTriggerProfile.activeAliases`.
- Use last occurrence of any alias (`last-name-wins`) as the only split boundary.
- Matching should enforce token boundaries so content words that merely contain alias substrings do not trigger splits.

### Split Output Contract
- Parser returns explicit content segment (pre-trigger) and instruction segment (post-trigger).
- If no alias match is found, parser returns a no-trigger result and existing passthrough behavior is preserved.
- If post-trigger instruction is empty or below minimum token threshold, parser must return a non-activating result.

### ActivationStore Integration Contract
- `ActivationStore.finalizeSession` consumes parser output and keeps convert-mode behavior unchanged for no-trigger/invalid-trigger cases.
- Trigger parsing must use the persisted alias contract from Phase 12 with no app-restart requirement.

### Claude's Discretion
- Concrete type names and helper extraction layout.
- Exact token-threshold constant placement, provided behavior matches PARSE-04.

</decisions>

<code_context>
## Existing Code Insights

- `Speech2Text/Activation/ActivationStore.swift` currently reads trigger aliases from `ShellPreferences.activeTriggerProfile.activeAliases`.
- `Speech2Text/Conversion/IntentDetector.swift` has legacy leading-trigger stripping and should not remain the primary split boundary source once parser contract is introduced.
- Phase 12 introduced normalized alias contract via `TriggerAliasNormalizer` and persisted trigger profile state.

</code_context>

<specifics>
## Specific Ideas

- Introduce parser-focused model types (split result + boundary metadata) in Activation domain for deterministic tests.
- Build RED corpus tests first for repeated trigger mentions, content-only mentions, no-trigger passthrough, and short-instruction guard cases.

</specifics>

<deferred>
## Deferred Ideas

- Intent shortcut routing and custom instruction fallback (Phase 14).
- Settings interaction flow for changing assistant name and calibrating aliases (Phase 15).

</deferred>

---
*Phase: 13-last-name-wins-parser-integration*
*Context gathered: 2026-03-20*
