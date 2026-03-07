# Roadmap: Speech2Test

## Overview

Speech2Test reaches its first useful release by proving one thing in order: a native macOS background utility can move the user from hotkey to trustworthy clipboard text with almost no friction. The roadmap starts with permissions and app-shell readiness, then adds activation and capture, then makes completion and clipboard behavior dependable, then hardens recovery and long-dictation reliability.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation and Permissions** - Establish the background utility shell, readiness state, and permission flows.
- [x] **Phase 2: Activation and Capture** - Deliver configurable hotkey activation, microphone capture, and immediate recording start.
- [ ] **Phase 3: Recognition and Clipboard Loop** - Turn recordings into final clipboard text with clear user-visible states.
- [ ] **Phase 4: Recovery Controls** - Make cancel, restart, and input failure handling trustworthy.
- [ ] **Phase 5: Long-Dictation Reliability** - Add segmentation, queued transcription, and best-effort recovery for longer sessions.

## Phase Details

### Phase 1: Foundation and Permissions
**Goal**: Ship a native menu bar utility that can stay in the background, persist basic settings, and clearly onboard the required macOS permissions.
**Depends on**: Nothing (first phase)
**Requirements**: [FEED-02, CONF-01, CONF-02]
**Success Criteria** (what must be TRUE):
  1. The app runs as a background/menu bar utility while another application remains frontmost.
  2. First-run flow clearly reports microphone and accessibility permission states and recovery steps.
  3. The app can tell the user whether it is ready or blocked before any recording attempt.
**Plans**: 2 plans

Plans:
- [ ] 01-01: Build the native app shell, menu bar presence, and persistent settings foundation.
- [ ] 01-02: Implement permission detection, onboarding flow, and readiness state handling.

### Phase 2: Activation and Capture
**Goal**: Let the user configure activation behavior and start recording immediately from any app with the chosen microphone and uninterrupted system audio.
**Depends on**: Phase 1
**Requirements**: [ACTV-01, ACTV-02, ACTV-03, ACTV-04, AUDI-01, AUDI-02, AUDI-03, CONF-03]
**Success Criteria** (what must be TRUE):
  1. The user can configure a system-wide activation hotkey and choose single-tap or double-tap mode.
  2. Recording begins quickly enough that the user can speak immediately after activation.
  3. The app captures from the selected microphone while other system audio playback continues normally.
**Plans**: 3 plans

Plans:
- [x] 02-01-PLAN.md — ShellPreferences extension, RecordingState/ActivationStore/HotkeyService with CGEventTap + double-tap detection, SetupWindowView Activation section.
- [x] 02-02-PLAN.md — AudioCaptureService (AVAudioEngine tap), AudioDeviceService (CoreAudio enumeration + selection), AudioLevelMonitor (RMS metering), mic picker UI.
- [x] 02-03-PLAN.md — RecordingPillPanel floating overlay, AppDelegate wiring (state → audio + pill + icon + sound), human verification checkpoint.

### Phase 3: Recognition and Clipboard Loop
**Goal**: Produce local transcription with punctuation, finish via spacebar, write the result to the clipboard, and show trustworthy recording/processing feedback.
**Depends on**: Phase 2
**Requirements**: [SESS-01, TRNS-01, TRNS-02, TRNS-06, CLIP-01, FEED-01, FEED-03]
**Success Criteria** (what must be TRUE):
  1. Pressing spacebar ends the active session and produces clipboard text when transcription succeeds.
  2. Idle, recording, and processing states are obvious, and indicator visibility can be configured.
  3. Empty or failed recognition attempts surface as explicit failure states instead of false success.
**Plans**: 3 plans

Plans:
- [ ] 03-01-PLAN.md — Type contracts, standalone services (WhisperService, AudioBufferAccumulator, ClipboardService, SpacebarInterceptor), RecordingState expansion, ShellPreferences Phase 3 keys, Wave 0 test scaffolds.
- [ ] 03-02-PLAN.md — Wire finish flow (spacebar/hotkey -> transcription -> clipboard -> auto-paste), buffer accumulation in AudioCaptureService, silence timeout in AudioLevelMonitor, full AppDelegate state machine.
- [ ] 03-03-PLAN.md — Multi-state pill UI (processing pulse, success checkmark, failure message), indicator visibility toggle, human verification checkpoint.

### Phase 4: Recovery Controls
**Goal**: Make cancel, restart, and microphone failure handling safe so the user can recover from mistakes without corrupting output.
**Depends on**: Phase 3
**Requirements**: [SESS-02, SESS-03, SESS-04, AUDI-04, CLIP-02]
**Success Criteria** (what must be TRUE):
  1. Escape cancels a session and leaves the clipboard unchanged.
  2. Restart discards current captured audio and keeps the user in recording state with clear confirmation.
  3. Microphone availability failures are reported clearly and never masquerade as successful output.
**Plans**: 2 plans

Plans:
- [ ] 04-01: Implement cancel and restart state transitions with buffer invalidation and confirmation UI.
- [ ] 04-02: Harden input-failure handling and protect clipboard integrity under cancellation and empty results.

### Phase 5: Long-Dictation Reliability
**Goal**: Support longer dictation sessions by segmenting capture, queueing transcription work, and combining best-available results in order.
**Depends on**: Phase 4
**Requirements**: [TRNS-03, TRNS-04, TRNS-05]
**Success Criteria** (what must be TRUE):
  1. Sessions longer than the configured threshold segment on natural speech gaps without losing or duplicating content.
  2. Queued segments combine into final text in the same order they were spoken.
  3. If a segment fails, the user still receives the best available combined output with a clear warning.
**Plans**: 3 plans

Plans:
- [ ] 05-01: Implement silence-aware segmentation thresholds and immutable segment queueing.
- [ ] 05-02: Add ordered transcript assembly and best-effort partial failure handling.
- [ ] 05-03: Verify long-session reliability, latency impact, and regression cases.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation and Permissions | 2/2 | Complete | 2026-03-05 |
| 2. Activation and Capture | 3/3 | Complete | 2026-03-06 |
| 3. Recognition and Clipboard Loop | 1/3 | In Progress|  |
| 4. Recovery Controls | 0/2 | Not started | - |
| 5. Long-Dictation Reliability | 0/3 | Not started | - |
