# Pitfalls Research

**Domain:** macOS system-wide clipboard-first dictation utility
**Researched:** 2026-03-05
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Hotkey or finish-key capture works only on the developer machine

**What goes wrong:**
The app seems fine in development, but activation or finish/cancel keys stop working on clean machines or after distribution because permissions and event APIs behave differently.

**Why it happens:**
Developers conflate hotkey registration, global event monitors, event taps, Accessibility, and Input Monitoring into one bucket and test only on machines that already granted trust.

**How to avoid:**
Separate activation hotkeys from in-session control keys architecturally. Build explicit preflight/request flows for microphone and keyboard-related permissions, and test them on fresh macOS installs and new bundle IDs.

**Warning signs:**
- Features work only after running from Xcode multiple times
- Fresh installs never show the needed permission prompt
- Space / Escape / Backspace behavior differs between machines

**Phase to address:**
Phase 1: Foundation and permissions

---

### Pitfall 2: First transcription is dramatically slower than later ones

**What goes wrong:**
The app meets latency targets after the first run, but the first real user interaction feels broken because model load, asset installation, or Core ML compilation stalls processing.

**Why it happens:**
Local ASR stacks often have one-time costs that developers hide by repeatedly testing warm sessions.

**How to avoid:**
Warm the engine proactively after launch, expose readiness state in diagnostics, and define cold-start and warm-start latency budgets separately.

**Warning signs:**
- First dictation takes several seconds longer than subsequent ones
- CPU or Neural Engine spikes only on the initial run
- User feedback says “it works after I try twice”

**Phase to address:**
Phase 2: Recording loop and engine warm-up

---

### Pitfall 3: Audio capture logic interferes with system playback

**What goes wrong:**
Starting dictation ducks, pauses, or otherwise disturbs music, calls, or other system audio, violating a core product promise.

**Why it happens:**
Audio configuration is copied from mobile/iOS examples or speech samples without revisiting macOS-specific behavior and product requirements.

**How to avoid:**
Treat “no interruption to system audio” as a non-negotiable test case. Benchmark with common real-world scenarios like music playback, video calls, and Bluetooth input devices.

**Warning signs:**
- Users report playback volume changes or pauses when recording starts
- Bluetooth headset behavior changes when the mic becomes active
- Audio route changes are not surfaced anywhere in diagnostics

**Phase to address:**
Phase 2: Recording loop and device handling

---

### Pitfall 4: Long dictation succeeds in demos but fails under sustained use

**What goes wrong:**
Short dictations look great, but long sessions suffer memory growth, dropped audio, out-of-order segments, or incomplete final text.

**Why it happens:**
Teams implement a single in-memory buffer first and defer segmentation semantics until too late, then bolt queue behavior onto a fragile loop.

**How to avoid:**
Introduce sequence numbers, file-backed or bounded buffers, and deterministic segment merge rules early. Test with recordings that exceed the threshold several times in one session.

**Warning signs:**
- Memory usage grows linearly with speaking duration
- Final text ordering changes across runs
- A failed segment cancels the entire session instead of degrading gracefully

**Phase to address:**
Phase 4: Long-dictation reliability

---

### Pitfall 5: Restart and cancel semantics are ambiguous

**What goes wrong:**
Users think they canceled or restarted, but old audio still appears in the final result or the session exits unexpectedly.

**Why it happens:**
Restart is treated as a UI nicety instead of a hard state transition with buffer discard guarantees.

**How to avoid:**
Define restart and cancel as explicit state machine events with invariant checks: cancel writes nothing, restart discards prior in-progress audio, and neither leaks stale transcript content.

**Warning signs:**
- Restarted sessions still contain discarded words
- Cancel sometimes updates the clipboard anyway
- UI flashes confirmation without corresponding buffer reset metrics

**Phase to address:**
Phase 3: Session controls and state integrity

---

### Pitfall 6: Clipboard updates become surprising or unsafe

**What goes wrong:**
The app overwrites something valuable in the clipboard at the wrong time, or users cannot tell whether the current clipboard contents came from dictation or a previous copy action.

**Why it happens:**
Clipboard writes are treated as trivial implementation detail instead of the product’s final handoff boundary.

**How to avoid:**
Write to the clipboard exactly once per completed session, only after ordered final assembly succeeds or degrades gracefully. Consider transient UI confirmation and internal telemetry around write timing and failures.

**Warning signs:**
- Clipboard content changes before processing completes
- Partial results overwrite user clipboard history unexpectedly
- Failure cases still clear the clipboard

**Phase to address:**
Phase 3: Completion and clipboard transaction

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Single giant session manager | Faster to prototype | Hard to test, hard to reason about restart/cancel bugs | Only for a throwaway spike |
| One unbounded in-memory audio buffer | Simplest long-dictation implementation | Memory blowups and catastrophic failure radius | Never for shipped v1 |
| Shelling out to a CLI per transcription | Easy to demo with existing tools | Kills latency and complicates packaging | Acceptable only for local benchmarking scripts |
| Skipping structured metrics | Faster initial coding | No way to prove latency targets or isolate regressions | Never if speed is the core value |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Global key handling | Using one API for activation and all in-session keys | Use the simplest stable activation path, then a separate controlled capture path for session keys if background interception is required |
| Microphone permissions | Asking only when recording starts, with no preflight or UX context | Preflight early, explain why, and surface blocked states in settings and status UI |
| Local speech assets | Assuming on-device engines are ready instantly | Separate installation/warm-up from first dictation and measure cold-start behavior explicitly |
| Clipboard | Writing intermediate or failed results | Write once after final assembly, with clear cancel/failure rules |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Cold model load on first use | First dictation feels broken, later ones feel fine | Warm engine in background and cache readiness state | Immediately noticeable in first-run experience |
| Overly small segment buffers | CPU spikes, too many transcription jobs, fragmented text | Tune silence thresholds and minimum segment duration from real speech samples | Breaks under faster speakers or noisy rooms |
| Main-thread state handling for audio events | UI hitching, delayed key handling, dropped frames | Keep audio/transcription work off the main thread and publish condensed state updates | Breaks under sustained dictation or slower machines |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Requesting broader permissions than the product actually needs | App review friction and user distrust | Keep the permission surface minimal and explain each request in-product |
| Sending audio off-device by default later without explicit mode shift | Privacy expectation violation | Preserve local-first as the default and make remote modes explicit opt-in settings |
| Logging transcript contents in plaintext | Sensitive speech leaks into logs or crash reports | Log timings and error codes, not user dictation content |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Too much UI during recording | The tool feels heavier than typing | Prefer a small menu bar state plus a restrained floating confirmation |
| Ambiguous processing state | Users do not know whether to keep waiting or retry | Show a distinct processing state and success/failure confirmation |
| Hidden failure modes | Users assume the clipboard has new text when it does not | Surface explicit “canceled”, “failed”, and “clipboard updated” confirmations |

## "Looks Done But Isn't" Checklist

- [ ] **Hotkey flow:** Often missing clean-machine permission coverage — verify on a brand-new bundle ID and a fresh user profile
- [ ] **Speech loop:** Often missing cold-start metrics — verify first-run and warm-run latency separately
- [ ] **Restart behavior:** Often missing true buffer discard — verify discarded speech never reaches final output
- [ ] **Long dictation:** Often missing ordered merge and partial-failure handling — verify multiple segments, one failed chunk, and final clipboard output
- [ ] **Clipboard output:** Often missing cancel/failure guardrails — verify canceled and empty recordings never modify the clipboard

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Permission flow broken | MEDIUM | Reset TCC state, retest preflight/request sequence, and add diagnostics around blocked privilege paths |
| Cold-start latency too high | MEDIUM | Introduce background warm-up, smaller initial model, and explicit ready-state instrumentation |
| Long dictation queue instability | HIGH | Persist segments, replay merge ordering from logs, and add deterministic sequence validation before clipboard write |
| Clipboard corruption complaints | LOW | Move clipboard write later, gate on final session success only, and add session-level confirmation UI |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Permission / key capture mismatch | Phase 1 | Fresh-install test matrix covers microphone, activation, and session-key capture |
| Cold-start latency surprise | Phase 2 | Cold vs warm latency benchmarks are tracked and within explicit budget |
| Audio playback interference | Phase 2 | Recording while music/calls play leaves output uninterrupted |
| Restart/cancel ambiguity | Phase 3 | Automated and manual tests prove discard/no-clipboard invariants |
| Clipboard boundary bugs | Phase 3 | Clipboard changes only after successful completion path |
| Long-dictation queue failure | Phase 4 | Multi-segment tests pass with ordered merge and partial failure recovery |

## Sources

- Apple Documentation Archive, `Monitoring Events` — https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html
- Apple Developer Forums, input-monitoring guidance for `CGEventTap` and permission APIs — https://developer.apple.com/forums/thread/707680
- Apple Developer Documentation, `Speech` — https://developer.apple.com/documentation/speech
- Apple Developer Documentation, `Recognizing speech in live audio` — https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio
- Apple Developer Documentation, `AVAudioNode` — https://developer.apple.com/documentation/avfaudio/avaudionode
- `whisper.cpp` — https://github.com/ggml-org/whisper.cpp

---
*Pitfalls research for: macOS system-wide clipboard-first dictation utility*
*Researched: 2026-03-05*
