# Speech2Test

## What This Is

Speech2Test is a lightweight macOS background dictation utility that runs from the menu bar, starts from a global hotkey, records immediately, transcribes locally, and copies the result to the clipboard. It supports cancel/restart recovery, long-dictation segmentation, and a local-LLM rewriting pipeline that converts dictated text to formatted output (Email, Slack, Teams, Clean English) when a named AI trigger (e.g. "Zeus") is spoken to separate content from instruction. Built-in modes are editable; custom modes can be created by writing a system prompt.

## Core Value

From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.

## Current State

- v1.2 shipped on 2026-03-20.
- Current shipped interaction: single-tap global hotkey start/finish, clipboard-only output with optional LLM rewriting, menu-bar-first shell, local transcription, long-dictation reliability, settings UI for modes and AI assistant name.
- AI trigger system: user says a named trigger (Zeus/Atlas/Gaia or custom) to split dictation into content + instruction. Last occurrence wins; instruction fuzzy-matches built-in modes or passes to LLM as custom rewrite instructions.
- Voice calibration available in settings for custom trigger names (3-sample capture via Whisper).
- Local models: `ggml-tiny.en.bin` for transcription; `Qwen2.5-1.5B-Instruct-4bit` (MLX) for rewriting.
- 4 built-in modes: Clean English, Email, Slack, Teams. Custom modes are user-created via the settings UI.
- Phase 22 complete (2026-03-24): Internal permission enum renamed `.keyboardShortcuts`; user-facing Setup labels read "Hold to Transcribe"; Accessibility auto-prompt fires on startup only after Input Monitoring is already granted (IM-gated, no delay).

## Requirements

### Validated

- ✓ User can trigger recording from a configurable global hotkey with a single press — v1.0
- ✓ User can dictate, finish with the same hotkey, and receive the transcription in the clipboard without direct text insertion — v1.0
- ✓ User can cancel or restart an in-progress recording session without quitting or reconfiguring the app — v1.0
- ✓ User receives visible state feedback and recovery feedback while the app remains lightweight in the background — v1.0
- ✓ User can complete short and long dictation sessions with local-first transcription and ordered best-effort output — v1.0
- ✓ User can trigger a rewriting mode by natural language at the start or end of dictation (fuzzy-matched) — v1.1
- ✓ User can rewrite a transcript as Clean English, Email, Slack, or Teams message via local LLM — v1.1
- ✓ User sees an orange "Input exceeds AI limit" alert when recording exceeds the 350-word conversion limit — v1.1
- ✓ User receives rewritten output in the clipboard, replacing the raw transcript — v1.1
- ✓ User can view, edit, and reset built-in modes; create and delete custom modes via the settings UI — v1.1
- ✓ Named AI trigger system (Zeus/Atlas/Gaia + custom) replaces fuzzy transcript scanning — v1.2
- ✓ Predefined trigger names selectable in settings; custom trigger name with voice calibration — v1.2
- ✓ Last-occurrence trigger detection splits transcript into content + instruction — v1.2
- ✓ Instruction fuzzy-matches predefined modes as shortcuts; unmatched instructions pass to LLM as custom — v1.2
- ✓ AI Assistant settings tile for trigger name configuration — v1.2
- ✓ Safety rules: command only after name, last occurrence wins, minimum instruction length — v1.2

### Active

## Current Milestone: v1.4 Hold-to-Transcribe Permission Fix

**Goal:** Wire the Hold to Transcribe UI to the correct macOS permission (Input Monitoring) so the push-and-hold activation mode actually works.

**Target features:**
- Hold to Transcribe row in Settings checks Input Monitoring permission status
- "Enable" and recovery actions request and open the correct Input Monitoring pane
- All user-facing labels, descriptions, and setup guides reference Input Monitoring
- PermissionKind model extended with .keyboard case for Privacy_ListenEvent
- .postEvent messages decoupled from Hold to Transcribe (only reference Auto Paste)
- Existing UI tests updated to assert corrected Input Monitoring strings
- Hold mode functions end-to-end when Input Monitoring is granted

### Out of Scope

- Automatic insertion into the active application — clipboard output is the compatibility boundary for v1.
- Broad consumer onboarding and packaging polish — the shipped release is still optimized for a single-user macOS workflow.
- Cloud-first architecture or mandatory remote transcription — the current product direction remains local-first.
- Multi-assistant profiles with per-profile prompts — adds profile management complexity beyond current scope.
- Wake-word audio detection before transcription — current architecture is transcript-level parsing after Whisper.
- Cloud profile sync for trigger settings — local-first configuration remains the product default.

## Context

The product exists to remove friction from dictation on macOS by avoiding app-specific insertion behavior and instead using the clipboard as the universal output path. The core shipped interaction is: trigger a global hotkey, record immediately, finish with the same hotkey, then paste anywhere with the normal paste shortcut. The recording lifecycle also includes explicit cancel and restart controls so mistakes do not force the user to restart the whole flow.

The app operates system-wide as a background utility, integrates with macOS microphone and clipboard APIs, and avoids interrupting ongoing system audio playback. Long dictation sessions are segmented into queued chunks after configurable thresholds and silence gaps, then recombined in order for final clipboard output. Visual feedback remains intentionally minimal: the pill stays quiet while the menu surface carries persistent state and warning copy.

Performance expectations remain aggressive, but the biggest remaining product pressure is transcription latency. The model has been reduced to `tiny.en` for the current shipped build because the speed gain outweighed the quality tradeoff on the target machine.


## Constraints

- **Platform**: macOS only — the product depends on global keyboard hooks, microphone capture, and clipboard APIs specific to macOS.
- **Interaction Model**: Clipboard-only output — avoids per-app insertion logic and keeps the product compatible with any application.
- **Performance**: Very low latency — the product target is near-immediate recording start and fast post-recording transcription/clipboard updates.
- **Privacy**: Local-first transcription — v1 should work without requiring cloud connectivity or sending audio off-device by default.
- **Audio Behavior**: No interruption of system playback — dictation cannot pause, mute, or otherwise break the user's current audio environment.
- **Reliability**: Long dictation segmentation — long recordings must degrade gracefully by chunking work instead of risking single-session failure.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Clipboard is the only output path in v1 | It preserves system-wide compatibility without building fragile direct-insertion logic | ✓ Shipped |
| v1 is single-user first | The project should prove the interaction and performance model before optimizing for mass-market polish | ✓ Shipped |
| Transcription is local-first in v1 | Privacy, offline capability, and minimal external dependency fit the initial product goals | ✓ Shipped |
| Speed is the primary tradeoff driver | The product only works if hotkey-to-clipboard turnaround feels almost immediate | ✓ Shipped |
| Recording starts and ends with the same hotkey while clipboard remains the only output path | The interaction stays minimal without app-specific insertion behavior or extra finishing keys | ✓ Shipped |
| Long sessions transcribe sealed segments progressively, but clipboard writes remain gated behind final assembly | Preserves clipboard safety while reducing long-session loss risk | ✓ Shipped |
| Re-arming is allowed from terminal success/failure feedback but not during active processing | Prevents the post-success freeze while keeping in-flight transcription non-interruptible | ✓ Shipped |
| `tiny.en` is the active bundled model at v1.0 closeout | Lower latency mattered more than the accuracy delta on the target machine | — Revisit |
| Fuzzy intent matching (Jaro-Winkler + zone pipeline) instead of exact phrase matching | Natural speech variation makes exact matching too brittle in practice | ✓ Shipped v1.1 |
| Action Items and AI Prompt modes removed from built-ins | Product direction narrowed; these modes added noise without clear user value | ✓ Shipped v1.1 |
| Phrase patterns generated invisibly by LLM; never exposed in UI | Reduces cognitive load — user writes a system prompt, app handles detection config | ✓ Shipped v1.1 |
| Orange "no match" pill when fuzzy detection fires but finds no mode | Distinguishes "passthrough by design" from "tried and failed" — better feedback | ✓ Shipped v1.1 |
| Named trigger boundary replaces whole-transcript fuzzy command scanning | Eliminates false activations from ambient speech; user intent is explicit | ✓ Shipped v1.2 |
| Last-occurrence trigger split (`last-name-wins`) | Avoids false activation from trigger name appearing in content before the real command | ✓ Shipped v1.2 |
| `TriggerProfileStore` is a dedicated file-backed actor isolated from convert-mode UserDefaults | Keeps trigger persistence fully independent; prevents cross-key corruption | ✓ Shipped v1.2 |
| Save-before-publish semantics for all trigger profile mutations | Runtime state only updates after successful store write — no half-applied state | ✓ Shipped v1.2 |
| Whole-word boundary matching for alias detection | Prevents substring aliases (e.g. `atlas` in `atlases`) from activating parser | ✓ Shipped v1.2 |
| `detectPredefinedShortcut` is a separate path from general intent detection | Avoids regressing non-trigger intent detection while adding trigger-gated built-in routing | ✓ Shipped v1.2 |
| Unresolved valid-trigger instructions route to custom LLM rewrite (not passthrough) | Makes trigger-activated speech useful even without a built-in mode match | ✓ Shipped v1.2 |
| `CalibrationCapturingDone` error type as exit sentinel for capturer exhaustion | Enables clean runner termination for both test stubs and real device cancellation | ✓ Shipped v1.2 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-24 after Phase 22 (Permission Startup Flow and Hotkey Gating) complete — IM-gated Accessibility auto-prompt at startup; user-facing labels read "Hold to Transcribe" (internal enum `.keyboardShortcuts`)*
