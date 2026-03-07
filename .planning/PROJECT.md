# Speech2Test

## What This Is

Speech2Test is a lightweight macOS background utility that captures speech system-wide from a user-defined hotkey, transcribes it, and copies the result to the clipboard. It is optimized for minimal interaction and fast hotkey-to-clipboard turnaround so the user can paste dictated text into any application without building per-app insertion logic. The first release is for a single macOS user workflow, with local-first transcription and speed as the primary product priority.

## Core Value

From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] User can trigger recording from a configurable global hotkey with a single press.
- [ ] User can dictate, finish with the same hotkey, and receive the transcription in the clipboard without direct text insertion.
- [ ] User can cancel or restart an in-progress recording session without quitting or reconfiguring the app.
- [ ] The app provides visible state feedback for idle, recording, processing, canceled, and restarted states while remaining lightweight in the background.
- [ ] The app supports local-first transcription with strong latency and reliability for short and long dictation sessions.

### Out of Scope

- Automatic insertion into the active application — clipboard output is the compatibility boundary for v1.
- Broad consumer onboarding and packaging polish — the first release is optimized for a single-user macOS workflow.
- Cloud-first architecture or mandatory remote transcription — v1 prioritizes local privacy, offline capability, and reduced network dependence.

## Context

The product exists to remove friction from dictation on macOS by avoiding app-specific insertion behavior and instead using the clipboard as the universal output path. The core interaction is: trigger a global hotkey, record immediately, finish with the same hotkey, then paste anywhere with the normal paste shortcut. The recording lifecycle also includes explicit cancel and restart controls so mistakes do not force the user to restart the whole flow.

The app must operate system-wide as a background utility, integrate with macOS microphone and clipboard APIs, and avoid interrupting ongoing system audio playback. Long dictation reliability matters, so sessions may be segmented into queued chunks after configurable thresholds and silence gaps, then recombined in order for final clipboard output. Visual feedback is required, but the interaction model should remain minimal and low-distraction.

Performance expectations are aggressive: activation delay below 100 ms, immediate recording start, transcription latency under 1.5 seconds after finish, and clipboard update under 100 ms once text is ready. The first release should favor the smallest architecture that proves this user experience reliably before expanding to hybrid engines or broader distribution.

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
| Clipboard is the only output path in v1 | It preserves system-wide compatibility without building fragile direct-insertion logic | — Pending |
| v1 is single-user first | The project should prove the interaction and performance model before optimizing for mass-market polish | — Pending |
| Transcription is local-first in v1 | Privacy, offline capability, and minimal external dependency fit the initial product goals | — Pending |
| Speed is the primary tradeoff driver | The product only works if hotkey-to-clipboard turnaround feels almost immediate | — Pending |
| Recording starts and ends with the same hotkey while clipboard remains the only output path | The interaction stays minimal without app-specific insertion behavior or extra finishing keys | — Pending |

---
*Last updated: 2026-03-05 after initialization*
