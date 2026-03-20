# Speech2Test

## What This Is

Speech2Test is a lightweight macOS background dictation utility that runs from the menu bar, starts from a global hotkey, records immediately, transcribes locally, and copies the result to the clipboard. It supports cancel/restart recovery, long-dictation segmentation, and a local-LLM rewriting pipeline that converts dictated text to formatted output (Email, Slack, Teams, Clean English) when triggered by natural language at the start or end of dictation. Built-in modes are editable; custom modes can be created by writing a system prompt.

## Core Value

From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.

## Current Milestone: v1.2 AI Trigger Name

**Goal:** Replace fuzzy transcript scanning with a named AI trigger system where the user says a trigger name (e.g. "Zeus") to separate dictated content from AI instructions.

**Target features:**
- Named AI trigger detection (Zeus/Atlas/Gaia or custom)
- Trigger-based content/instruction splitting
- Instruction interpretation: predefined mode shortcuts + custom LLM passthrough
- Voice calibration for custom trigger names
- Settings UI for AI assistant name configuration
- Safety rules (last-name-wins, minimum instruction length)

## Current State

- v1.1 shipped on 2026-03-20.
- Current shipped interaction: single-tap global hotkey start/finish, clipboard-only output with optional LLM rewriting, menu-bar-first shell, local transcription, long-dictation reliability, and a settings UI for managing conversion modes.
- Local models: `ggml-tiny.en.bin` for transcription; `Qwen2.5-1.5B-Instruct-4bit` (MLX) for rewriting.
- 4 built-in modes: Clean English, Email, Slack, Teams. Custom modes are user-created via the settings UI.
- Orange "No match · Copied/Pasted" pill shown when fuzzy intent detection fires but no mode matches.

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

### Active

<!-- v1.2 AI Trigger Name — requirements defined in REQUIREMENTS.md -->

- [ ] Named AI trigger system replaces fuzzy transcript scanning
- [ ] Predefined trigger names (Zeus default, Atlas, Gaia) selectable in settings
- [ ] Custom trigger name with voice calibration for transcription aliases
- [ ] Last-occurrence trigger detection splits transcript into content + instruction
- [ ] Instruction fuzzy-matches predefined modes as shortcuts; unmatched instructions pass to LLM as custom
- [ ] Settings UI tile for AI assistant name configuration
- [ ] Safety rules: command only after name, last occurrence wins, minimum instruction length

### Out of Scope

- Automatic insertion into the active application — clipboard output is the compatibility boundary for v1.
- Broad consumer onboarding and packaging polish — the shipped release is still optimized for a single-user macOS workflow.
- Cloud-first architecture or mandatory remote transcription — the current product direction remains local-first.

## Context

The product exists to remove friction from dictation on macOS by avoiding app-specific insertion behavior and instead using the clipboard as the universal output path. The core shipped interaction is: trigger a global hotkey, record immediately, finish with the same hotkey, then paste anywhere with the normal paste shortcut. The recording lifecycle also includes explicit cancel and restart controls so mistakes do not force the user to restart the whole flow.

The app operates system-wide as a background utility, integrates with macOS microphone and clipboard APIs, and avoids interrupting ongoing system audio playback. Long dictation sessions are segmented into queued chunks after configurable thresholds and silence gaps, then recombined in order for final clipboard output. Visual feedback remains intentionally minimal: the pill stays quiet while the menu surface carries persistent state and warning copy.

Performance expectations remain aggressive, but the biggest remaining product pressure is transcription latency. The model has been reduced to `tiny.en` for the current shipped build because the speed gain outweighed the quality tradeoff on the target machine.


## Constraints

- **Platform**: macOS only — the product depends on global keyboard hooks, microphone capture, and clipboard APIs specific to macOS.
- **Interaction Model**: Clipboard-only output — avoids per-app insertion logic and keeps the product compatible with any application.
- **Performance**: Very low latency — the product target is near-immediate recording start and fast post-recording transcription/clipboard updates.
- **Privacy**: Local-first transcription — v1 should work without requiring cloud connectivity or sending audio off-device by default.
- **Audio Behavior**: No interruption of system playback — dictation cannot pause, mute, or otherwise break the user’s current audio environment.
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

---
*Last updated: 2026-03-20 after v1.2 milestone started*
