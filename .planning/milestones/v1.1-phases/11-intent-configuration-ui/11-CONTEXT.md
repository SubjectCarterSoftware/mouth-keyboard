# Phase 11: Intent Configuration UI - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning
**Source:** PRD Express Path (inline)

<domain>
## Phase Boundary

Settings panel for managing conversion modes. Users describe what they want a mode to do by writing a system prompt — everything else (phrase patterns, keyword signals, confidence thresholds) is handled automatically and invisibly. Built-in modes are editable with reset. Custom modes are fully user-created.

</domain>

<decisions>
## Implementation Decisions

### Data Layer
- Persistent `UserIntentStore` as JSON in App Support directory
- Stores per-mode overrides: system prompt, generated phrase patterns (50), mode name
- Stores custom modes: mode name, system prompt, 50 generated phrase patterns, derived keyword signal
- `IntentCatalog` and `ConvertMode` read from store first, fall back to hardcoded defaults
- No `ConvertMode` enum changes required — custom intents are represented as data, not Swift types

### Intent List (Settings Panel)
- One row per mode (built-in + custom): mode name + truncated system prompt preview
- "Add Mode" button → opens create view
- Tap any existing row → opens edit view

### Add / Edit Mode View — Left Side (Definition)
- Mode name field: editable, but auto-suggested as ghost text while user types system prompt (debounced ~1s, local LLM name-generation prompt)
- System prompt text area: freeform, primary user input. Placeholder: "Describe what this mode should do with your dictated text..."
- "Reset to default" button: built-in modes only — wipes overrides, restores hardcoded values
- "Delete" button: custom modes only

### Add / Edit Mode View — Right Side (Live Preview Panel)
- Example input field: pre-filled with generic dictation sample ("had a call with the team today we covered the roadmap and need to follow up with Sarah by Friday"). Fully editable. Never saved/persisted.
- Output panel: LLM output using current system prompt applied to example input
- Updates automatically as system prompt changes (debounced ~2s) or on manual trigger
- Primary feedback loop: "does my prompt do what I think?"

### Background Phrase Pattern Generation (Invisible to User)
- Once system prompt settles (~2s after last keystroke), silently generate 50 phrase patterns using the local LLM
- Store in `UserIntentStore` — no spinner, no button, no UI mention of "phrase patterns"
- Phrase patterns are a pure implementation detail

### Phrase Trigger Tester (Disclosure Section, Same Page)
- Collapsed by default under "Test trigger phrase" disclosure control
- Text field: "Type how you'd say this out loud..."
- Shows: match result (triggered / not triggered) + confidence score
- Optional/advanced — not required to use the app

### What Users Never See
- Phrase patterns array
- Confidence thresholds
- Keyword signals
- `IntentDefinition` struct internals

### Scope Boundary (v1)
- No new `ConvertMode` enum cases — custom intents are data-driven
- No reordering or enabling/disabling individual modes (future)
- No import/export of intent configs (future)

### Claude's Discretion
- Exact SwiftUI layout approach (HStack split, NavigationSplitView, sheet, etc.)
- Debounce implementation mechanism
- LLM prompt templates for name generation and phrase pattern generation
- Persistence format details within JSON store
- Error handling for LLM generation failures in settings context
- Whether mode name suggestion uses streaming or waits for full completion

</decisions>

<specifics>
## Specific Ideas

- Example input pre-fill: "had a call with the team today we covered the roadmap and need to follow up with Sarah by Friday"
- Name suggestion: ghost text in mode name field, appears while typing system prompt
- 50 phrase patterns generated per intent (local Qwen 2.5 1.5B model is fast enough)
- Phrase trigger tester shows confidence score alongside triggered/not triggered result
- LLM already available via `LLMRewriteService` — phrase generation reuses same actor with custom instruction

</specifics>

<deferred>
## Deferred Ideas

- Reordering modes
- Enabling/disabling individual modes
- Import/export of intent configs
- Sharing custom intents between users

</deferred>

---

*Phase: 11-intent-configuration-ui*
*Context gathered: 2026-03-19 via PRD Express Path*
