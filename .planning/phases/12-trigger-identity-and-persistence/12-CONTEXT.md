# Phase 12: Trigger Identity and Persistence - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the AI assistant identity model and persistence layer for trigger-name operation: predefined names (`Zeus`, `Atlas`, `Gaia`), custom name support, calibration-ready alias storage, and safe fallback behavior. This phase defines how trigger identity is stored and updated, not transcript parsing (`last-name-wins`), instruction routing, or settings UX polish from later phases.

</domain>

<decisions>
## Implementation Decisions

### Profile Lifecycle
- Switching assistant names resets active aliases to that name's defaults (no cross-name alias carryover).
- Custom profile state is remembered; if user leaves custom and later returns, restore the last custom name + aliases.
- First launch defaults to active profile `Zeus` with a single canonical alias (`zeus`).
- Selecting `Atlas` or `Gaia` activates immediately without requiring calibration first.

### Calibration Contract
- A calibration run captures 3 valid spoken samples for the active profile.
- If a captured sample is empty/noise, prompt retry for that sample rather than accepting partial quality.
- Re-running calibration for the same profile replaces the prior alias set from calibration (not merge).
- Calibration aliases are scoped per assistant profile; no shared global alias pool.

### Alias Normalization Rules
- Canonical storage format: lowercase, trimmed, internal whitespace collapsed to single spaces.
- Alias dedupe uses exact match after normalization (no fuzzy dedupe).
- Minimum valid alias length is 2 characters after normalization.
- Multi-word assistant names/aliases are allowed.

### Persistence Safety and Runtime Guarantees
- If trigger profile data is missing or corrupted on launch, runtime falls back to Zeus default profile (`zeus`).
- If profile save fails, keep the previous persisted profile active (no partial/half-committed runtime state).
- Trigger identity updates must never modify existing conversion mode configuration.
- Trigger profile changes take effect immediately for subsequent sessions; no app relaunch required.

### Claude's Discretion
- Exact user-facing copy and micro-interaction details for calibration retry prompts.
- Exact internal error logging/reporting strategy for persistence failures, as long as fallback and no-partial-state guarantees hold.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Speech2Text/Persistence/ShellPreferences.swift`: established `@Published` + `UserDefaults` pattern for stable preference persistence and reset behavior.
- `Speech2Text/Conversion/UserIntentStore.swift`: actor-based JSON store with lazy load, atomic writes, and corruption-safe fallback to empty state; good precedent for persisted model actor behavior.
- `Speech2Text/Activation/ActivationStore.swift`: central runtime integration point where persisted trigger profile will be consumed at finalize-time in later phases.
- `Speech2Text/Shell/SetupWindowView.swift`: current settings surface where later trigger identity UI entry points can integrate.

### Established Patterns
- Main app stores and UI-facing preference objects are `@MainActor` with `ObservableObject` / `@Published` state.
- Durable, user-editable data uses file-backed actor stores (`UserIntentStore`) with directory auto-create and atomic JSON writes.
- Corrupted persisted data degrades safely to defaults rather than blocking runtime.
- Existing convert-mode pipeline snapshots dynamic intent configuration at session finalize (`ActivationStore.finalizeSession`) and must remain isolated from trigger profile persistence changes.

### Integration Points
- Trigger profile persistence should coexist with `ShellPreferences` and `UserIntentStore` without changing current convert-mode keys/data contracts.
- Activation runtime must observe the active trigger profile immediately after updates so next session behavior reflects changes without restart.
- Future Phase 13 parser work will consume this phase's normalized alias list contract as the matching input set.

</code_context>

<specifics>
## Specific Ideas

- Keep profile behavior deterministic: active name and alias set should always be explainable to users after a switch or recalibration.
- Prioritize reliability over aggressive alias accumulation; replace-on-recalibrate and exact dedupe keep alias sets clean.
- Preserve current conversion-mode behavior completely while introducing trigger identity persistence.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---
*Phase: 12-trigger-identity-and-persistence*
*Context gathered: 2026-03-20*
