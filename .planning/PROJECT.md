# Speech2Test

## What This Is

Speech2Test is a lightweight macOS background dictation utility that runs from the menu bar, starts from a global hotkey, records immediately, transcribes locally, and copies the result to the clipboard. The shipped v1.0 release supports cancel/restart recovery, microphone failure handling, indicator visibility control, and long-dictation segmentation with best-effort final assembly.

## Core Value

From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.

## Current State

- v1.0 shipped on 2026-03-08.
- Current shipped interaction: single-tap global hotkey start/finish, clipboard-only output, menu-bar-first shell, local transcription, and long-dictation reliability support.
- Current local model setting: `ggml-tiny.en.bin` for improved latency on the target machine.
- Milestone audit debt accepted at closeout: missing Phase 2 and Phase 5 verification reports, stale traceability around some v1 requirements, and planning docs that still mention removed activation behavior.

## Requirements

### Validated

- ✓ User can trigger recording from a configurable global hotkey with a single press — v1.0
- ✓ User can dictate, finish with the same hotkey, and receive the transcription in the clipboard without direct text insertion — v1.0
- ✓ User can cancel or restart an in-progress recording session without quitting or reconfiguring the app — v1.0
- ✓ User receives visible state feedback and recovery feedback while the app remains lightweight in the background — v1.0
- ✓ User can complete short and long dictation sessions with local-first transcription and ordered best-effort output — v1.0

### Active

- [ ] User can trigger a rewriting mode by starting or ending their dictation with "convert to [mode name]"
- [ ] User can rewrite a transcript as Clean English, Email, Slack / Teams message, Action Items list, or AI Prompt
- [ ] User sees an alert when their recording exceeds the 350-word limit for conversion
- [ ] User receives the rewritten output in the clipboard, replacing the raw transcript

### Out of Scope

- Automatic insertion into the active application — clipboard output is the compatibility boundary for v1.
- Broad consumer onboarding and packaging polish — the shipped release is still optimized for a single-user macOS workflow.
- Cloud-first architecture or mandatory remote transcription — the current product direction remains local-first.

## Context

The product exists to remove friction from dictation on macOS by avoiding app-specific insertion behavior and instead using the clipboard as the universal output path. The core shipped interaction is: trigger a global hotkey, record immediately, finish with the same hotkey, then paste anywhere with the normal paste shortcut. The recording lifecycle also includes explicit cancel and restart controls so mistakes do not force the user to restart the whole flow.

The app operates system-wide as a background utility, integrates with macOS microphone and clipboard APIs, and avoids interrupting ongoing system audio playback. Long dictation sessions are segmented into queued chunks after configurable thresholds and silence gaps, then recombined in order for final clipboard output. Visual feedback remains intentionally minimal: the pill stays quiet while the menu surface carries persistent state and warning copy.

Performance expectations remain aggressive, but the biggest remaining product pressure is transcription latency. The model has been reduced to `tiny.en` for the current shipped build because the speed gain outweighed the quality tradeoff on the target machine.

## Current Milestone: v1.1 Convert Modes

**Goal:** Add 5 transcript rewriting modes powered by a local LLM, activated when the user's dictation starts or ends with "convert to [mode name]".

**Target features:**
- Intent detection: transcript starts or ends with "convert to X" (exact mode name match)
- 5 modes: Clean English, Email, Slack / Teams, Action Items, Prompt
- Local LLM rewriting via Qwen2.5-1.5B-Instruct (MLX, 4-bit)
- 350-word hard limit: skip model call and alert user if exceeded
- No-trigger path unchanged: existing clipboard-copy behavior preserved

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

---
*Last updated: 2026-03-18 after v1.1 milestone started*
