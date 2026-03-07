# Project Research Summary

**Project:** Speech2Test
**Domain:** macOS system-wide clipboard-first dictation utility
**Researched:** 2026-03-05
**Confidence:** HIGH

## Executive Summary

This product is best built as a native macOS menu bar utility with a strict boundary: global hotkey in, microphone capture and local transcription in the middle, clipboard text out at the end. Research points toward a native Swift implementation with `AVAudioEngine`, Core Graphics/AppKit integrations, and Apple’s current Speech framework as the primary local-first path, with a fallback engine boundary only if later compatibility or accuracy testing demands it.

The strongest launch posture is narrower than many adjacent products. Table stakes are reliable hotkey activation, visible recording state, accurate transcription with punctuation, cancel/restart recovery, microphone/device handling, and fast clipboard delivery. The biggest risks are not “can speech-to-text work?” but whether the app feels instant on first use, whether global key handling remains reliable, and whether long dictation segmentation can avoid repeated or missing text.

## Key Findings

### Recommended Stack

The most defensible stack is native Swift 6.2 on current Apple tooling, using SwiftUI plus AppKit for the shell, `AVAudioEngine` for capture, Speech framework APIs for on-device transcription, Core Graphics event taps for in-session key handling, and `NSPasteboard` for output. That keeps the entire hotkey-to-clipboard loop inside the macOS-native runtime and avoids the startup and integration penalties of cross-platform wrappers.

**Core technologies:**
- Swift 6.2: Native implementation language — best fit for low-latency macOS APIs and a small background utility.
- `AVAudioEngine`: Microphone capture and buffering — standard streaming path for low-latency live audio on Apple platforms.
- Speech framework: Local-first transcription and speech analysis — strongest current native path for on-device speech on recent macOS versions.
- Core Graphics/AppKit: Global key handling and clipboard output — required for reliable system-wide controls and pasteboard writes.

### Expected Features

Research and the supplied spec align closely: launch scope should stay centered on the speech-to-clipboard loop and not drift into direct insertion, voice assistant behavior, or transcript-management software.

**Must have (table stakes):**
- Global hotkey activation with reliable in-session finish/cancel/restart controls — users expect the app to work without app switching.
- Fast, accurate local transcription with punctuation — the product fails if output is slow or consistently messy.
- Clear state feedback and microphone/device resilience — users must trust recording state and recover from device/permission issues.
- Long-dictation segmentation and ordered reassembly — required to keep reliability acceptable beyond short utterances.

**Should have (competitive):**
- Clipboard-first output — differentiates by reducing app-specific brittleness.
- Restart-from-here during recording — preserves flow better than forcing full-session cancel/retry.
- No disruption to system audio playback — important for real daily use alongside music, calls, or reference audio.

**Defer (v2+):**
- Direct insertion into active apps — high fragility, weak fit for the chosen product boundary.
- AI rewrite / formatting modes — useful later, but they dilute the speed-first proposition and add latency.
- Meeting recording / transcript-management workflows — adjacent market, different architecture.

### Architecture Approach

The best architecture is a small session coordinator at the center, with explicit boundaries for hotkey monitoring, audio capture, segmentation, speech engine adaptation, clipboard output, preferences, and feedback UI. The session coordinator should own the authoritative state machine so the app never guesses whether it is idle, recording, processing, canceled, or recovering from restart.

**Major components:**
1. Session coordinator — owns product state and orchestrates start/finish/cancel/restart behavior.
2. Capture + segmentation pipeline — turns live mic input into ordered segments with silence-aware boundaries.
3. Speech engine adapter — hides engine-specific details and returns normalized transcript results.
4. Clipboard + feedback layer — writes final text and confirms state to the user without stealing focus.

### Critical Pitfalls

1. **Event tap reliability drift** — keep callbacks tiny, verify permissions explicitly, and add tap health checks.
2. **Cold-start latency** — warm audio and transcription paths before the first dictation and measure first-use separately from warm runs.
3. **Segmentation corruption** — use immutable ordered segments and assemble by sequence, not callback timing.
4. **Fake cancel/restart handling** — make these real state transitions that dispose of buffers and invalidate stale work.
5. **Clipboard success assumptions** — treat pasteboard write as a discrete completion step and verify it in logs/tests.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Foundation and Permissions
**Rationale:** Nothing else matters if the app cannot live in the menu bar, hold settings, and reliably observe the required system input permissions.
**Delivers:** Native app shell, menu bar utility, settings storage, first-run permission flow, and configurable activation hotkey.
**Addresses:** Global activation, permission handling, and state visibility foundations.
**Avoids:** Event-tap and onboarding failures.

### Phase 2: Capture and Local Recognition Core
**Rationale:** The core loop should prove immediate recording and local transcription before richer controls are layered on top.
**Delivers:** Microphone capture, audio buffering, engine warmup, local transcription, and baseline latency instrumentation.
**Uses:** `AVAudioEngine`, Speech framework, and structured metrics.
**Implements:** Capture, engine, and coordinator boundaries.

### Phase 3: Session Completion and Recovery Controls
**Rationale:** Once the basic loop works, the app must become dependable under real mistakes and session endings.
**Delivers:** Spacebar finish, Escape cancel, restart-from-here behavior, clipboard write confirmation, and failure states.
**Uses:** Event monitoring, explicit state machine transitions, and clipboard isolation.
**Implements:** Session state semantics and product-level recovery behavior.

### Phase 4: Long-Dictation Reliability
**Rationale:** Segmentation and queueing introduce the highest correctness risk and should be isolated after the short-session loop is stable.
**Delivers:** Silence-aware segmentation, ordered segment queue, partial-failure handling, and combined transcript assembly.
**Uses:** Speech detection / silence heuristics and immutable segment modeling.
**Implements:** Reliability features specific to longer sessions.

### Phase 5: Feedback, Settings Completion, and Ship Readiness
**Rationale:** Polish should follow proof of the core loop, not precede it.
**Delivers:** Final recording HUD/menu bar states, device selection, indicator preferences, diagnostics, packaging, signing, and notarization readiness.
**Uses:** UI surfaces, preferences, and distribution tooling.
**Implements:** User trust, hardware configurability, and shippable app behavior.

### Phase Ordering Rationale

- Permissions and hotkey reliability must land before capture because they gate every session.
- Capture and transcription must be proven before cancel/restart and long-dictation behavior can be implemented safely.
- Segmentation belongs after the short-session loop because it adds correctness risk and depends on stable capture/transcription boundaries.
- Polishing and distribution should come last so UI effort is shaped by the working interaction rather than guesses.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2:** Apple Speech API fit versus fallback-engine abstraction on the target macOS version and hardware.
- **Phase 4:** Silence detection thresholds, segment lifecycle, and best-effort merge behavior under failure.
- **Phase 5:** Distribution path details if the app will be shared beyond the original user.

Phases with standard patterns (skip research-phase):
- **Phase 1:** Menu bar shell, settings persistence, and permission flows are well-established macOS patterns.
- **Phase 3:** Clipboard output and explicit session-state controls are mostly product logic, not ecosystem uncertainty.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Native macOS choices are strong; exact Speech-framework fit still depends on deployment target and language coverage. |
| Features | HIGH | User spec and current dictation-tool landscape align closely on launch priorities. |
| Architecture | HIGH | The boundary-driven session-coordinator model is a strong fit for this interaction pattern. |
| Pitfalls | HIGH | The major failure modes are well-understood and directly relevant to this product category. |

**Overall confidence:** HIGH

### Gaps to Address

- **Speech engine choice on the exact deployment target:** Validate Apple Speech APIs against the target macOS release and fallback needs during Phase 2 planning.
- **Latency on real hardware:** Measure cold-start and warm-start timings on the intended machine before expanding scope.
- **Language / locale scope:** Confirm which locales matter before hardening the engine abstraction.

## Sources

### Primary (HIGH confidence)
- Apple Developer, Speech framework — https://developer.apple.com/documentation/speech
- Apple Developer, "Recognizing speech in live audio" — https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio
- Apple Developer, `CGEventTapCreate` — https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29
- Apple Developer, `AVAudioNode` / audio taps — https://developer.apple.com/documentation/avfaudio/avaudionode
- Apple Developer, `NSPasteboard.general` — https://developer.apple.com/documentation/appkit/nspasteboard/general

### Secondary (MEDIUM confidence)
- `ggml-org/whisper.cpp` — fallback local engine patterns and tradeoffs — https://github.com/ggml-org/whisper.cpp
- Wispr Flow and Superwhisper product/docs — current feature expectations and scope boundaries
- Apple Support Voice Control docs — user expectation baseline for macOS-wide speech utilities

---
*Research completed: 2026-03-05*
*Ready for roadmap: yes*
