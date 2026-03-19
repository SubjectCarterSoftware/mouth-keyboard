# Requirements: Speech2Test

**Defined:** 2026-03-18
**Core Value:** From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.

## v1.1 Requirements

### Intent Detection

- [x] **INTENT-01**: User can trigger a rewriting mode by starting their dictation with the mode's activation phrase
- [x] **INTENT-02**: User can trigger a rewriting mode by ending their dictation with the mode's activation phrase
- [x] **INTENT-03**: Intent detection is case-insensitive and strips the trigger phrase before passing content to the LLM

### Rewriting Modes

- [x] **MODE-01**: User can rewrite a transcript as Clean English (filler words removed, grammar fixed, voice preserved)
- [x] **MODE-02**: User can rewrite a transcript as an Email (subject line, professional body, sign-off)
- [x] **MODE-03**: User can rewrite a transcript as a Slack message (casual, short, scannable, no greeting)
- [x] **MODE-04**: User can rewrite a transcript as a Teams message (casual, short, scannable, no greeting)
- [x] **MODE-05**: User can extract Action Items from a transcript as a bullet list (with owner and deadline if mentioned)
- [x] **MODE-06**: User can structure a transcript as a well-formed AI Prompt (context → ask → output requirements)

### LLM Pipeline

- [x] **LLM-01**: Rewriting runs locally via Qwen2.5-1.5B-Instruct-4bit (MLX), with the model downloaded on first use and cached persistently
- [x] **LLM-02**: The no-trigger dictation path is completely unchanged — plain transcriptions still copy raw text to clipboard
- [ ] **LLM-03**: User sees download progress in the menu bar when the rewrite model is downloading for the first time

### Guards & UX

- [x] **UX-01**: User sees a loading indicator in the pill while LLM conversion is in progress (distinct from the normal transcription processing state)
- [x] **GUARD-01**: When a conversion body exceeds 350 words, the pill flashes an orange alert ("Input exceeds AI limit") before copying the raw transcript to clipboard
- [x] **GUARD-02**: On any LLM failure, the raw transcript is copied to clipboard silently (no failed partial output)

### Settings

- [ ] **SETT-01**: User can view all 6 built-in modes in the settings panel, including their activation phrase and read-only system prompt
- [ ] **SETT-02**: User can edit the activation phrase for any built-in mode (defaults to "convert to [mode name]")
- [ ] **SETT-03**: User can add a custom mode with a custom activation phrase and a system prompt (max 280 characters)
- [ ] **SETT-04**: User can delete a custom mode they previously created

## Future Requirements

### Polish & Extensibility

- **FUTURE-01**: Per-mode prompt customisation for built-in modes (edit the system prompt, not just the activation phrase)
- **FUTURE-02**: Rewrite history or undo (the raw transcript fallback is the recovery path for v1.1)
- **FUTURE-03**: Cloud LLM fallback option
- **FUTURE-04**: Custom mode import/export

## Out of Scope

| Feature | Reason |
|---------|--------|
| Fuzzy mode name matching | Exact matching is safer; mode names are short and memorable; fuzzy matching introduces ambiguous activations |
| Editing built-in mode system prompts | Read-only in v1.1; built-in prompts are spec-validated; custom modes cover the extensibility need |
| Cloud transcription or rewriting | Local-first is a core product constraint |
| Rewrite history | Clipboard is the output path; raw transcript fallback is the recovery path |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INTENT-01 | Phase 7 | Complete |
| INTENT-02 | Phase 7 | Complete |
| INTENT-03 | Phase 7 | Complete |
| MODE-01 | Phase 7 | Complete |
| MODE-02 | Phase 7 | Complete |
| MODE-03 | Phase 7 | Complete |
| MODE-04 | Phase 7 | Complete |
| MODE-05 | Phase 7 | Complete |
| MODE-06 | Phase 7 | Complete |
| LLM-01 | Phase 6 | Complete |
| LLM-02 | Phase 9 | Complete |
| LLM-03 | Phase 10 | Pending |
| UX-01 | Phase 9 | Complete |
| GUARD-01 | Phase 9 | Complete |
| GUARD-02 | Phase 8 | Complete |
| SETT-01 | Phase 10 | Pending |
| SETT-02 | Phase 10 | Pending |
| SETT-03 | Phase 10 | Pending |
| SETT-04 | Phase 10 | Pending |

**Coverage:**
- v1.1 requirements: 19 total
- Mapped to phases: 19
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-18*
*Last updated: 2026-03-18 after roadmap creation — traceability corrected (MODE-01–06 to Phase 7, LLM-02 to Phase 9)*
