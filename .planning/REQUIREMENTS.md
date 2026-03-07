# Requirements: Speech2Test

**Defined:** 2026-03-05
**Core Value:** From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.

> Scope update on 2026-03-07: v1 is single-tap hotkey start/finish with clipboard-only output. Double-tap activation, spacebar finish, and auto-paste are not active v1 scope.

## v1 Requirements

### Activation

- [x] **ACTV-01**: User can configure a system-wide activation hotkey.
- [x] **ACTV-02**: User can start recording with a single press of the activation hotkey.
- [x] **ACTV-03**: User can use the same activation hotkey as the start/finish toggle for a recording session.
- [x] **ACTV-04**: User can begin speaking immediately after activation without a second confirmation step.

### Session Controls

- [x] **SESS-01**: User can finish the active recording with the activation hotkey while remaining in the current application.
- [ ] **SESS-02**: User can cancel the active recording with Escape and leave the clipboard unchanged.
- [ ] **SESS-03**: User can restart the current recording from a clean point without leaving recording state.
- [ ] **SESS-04**: User receives a clear visual confirmation when a session is canceled or restarted.

### Audio Capture

- [x] **AUDI-01**: User can record speech from the system microphone through a continuous audio stream.
- [x] **AUDI-02**: User can choose which microphone input device is used for dictation.
- [x] **AUDI-03**: User can keep system audio playback uninterrupted while dictating.
- [ ] **AUDI-04**: User receives a clear error when the selected microphone is unavailable or access is denied.

### Transcription

- [x] **TRNS-01**: User receives local-first speech transcription for captured audio.
- [x] **TRNS-02**: User receives punctuation in the transcribed text without manual cleanup for normal dictation.
- [ ] **TRNS-03**: User can dictate longer than 30 seconds without losing earlier audio because the app segments and queues the recording automatically.
- [ ] **TRNS-04**: User receives a combined transcript in the original spoken order when a session spans multiple segments.
- [ ] **TRNS-05**: User still receives the best available combined transcript if one segment fails to transcribe.
- [x] **TRNS-06**: User receives a clear failure state instead of a silent or misleading success when transcription cannot produce usable text.

### Clipboard Output

- [x] **CLIP-01**: User receives the final transcription in the system clipboard after a successful session.
- [ ] **CLIP-02**: User can rely on the app to avoid overwriting the clipboard when a session is canceled or produces no usable transcription.

### Feedback

- [x] **FEED-01**: User can distinguish idle, recording, and processing states from visual indicators.
- [ ] **FEED-02**: User can keep the app in the background while using any other application during dictation.
- [x] **FEED-03**: User can choose whether the recording indicator is visible.

### Permissions and Setup

- [ ] **CONF-01**: User is prompted for microphone permission before first recording and receives recovery guidance if access is denied.
- [ ] **CONF-02**: User is prompted for accessibility permission before global keyboard monitoring is used and receives recovery guidance if access is denied.
- [x] **CONF-03**: User can configure activation settings from the setup window without a separate preferences surface.

## v2 Requirements

### Engine Modes

- **ENGN-01**: User can switch between local and cloud transcription modes.
- **ENGN-02**: User can choose among multiple transcription engines or model profiles.

### Enhanced Feedback

- **HUD-01**: User can view a live waveform or richer recording HUD while dictating.
- **HUD-02**: User can review recent transcription history for retry or recovery.

### Expanded Output

- **OUTP-01**: User can insert transcription directly into the active application instead of using the clipboard.
- **OUTP-02**: User can apply optional formatting or rewrite modes to the transcription before output.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Direct insertion into the active application | Conflicts with the clipboard-first product boundary and adds fragile app-specific behavior too early |
| Cloud-first or mandatory remote transcription | Conflicts with the chosen local-first v1 posture and adds network latency to the core loop |
| Meeting recording or system-audio transcription | Expands the product into long-form recording software instead of fast dictation capture |
| AI rewrite, formatting, or tone modes in v1 | Dilutes the speed-first, faithful-transcription promise and increases latency/UX complexity |
| Cross-platform support | macOS-native integration is the shortest path to a reliable first release |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ACTV-01 | Phase 2 | Complete |
| ACTV-02 | Phase 2 | Complete |
| ACTV-03 | Phase 3 | Complete |
| ACTV-04 | Phase 2 | Complete |
| SESS-01 | Phase 3 | Complete |
| SESS-02 | Phase 4 | Pending |
| SESS-03 | Phase 4 | Pending |
| SESS-04 | Phase 4 | Pending |
| AUDI-01 | Phase 2 | Complete |
| AUDI-02 | Phase 2 | Complete |
| AUDI-03 | Phase 2 | Complete |
| AUDI-04 | Phase 4 | Pending |
| TRNS-01 | Phase 3 | Complete |
| TRNS-02 | Phase 3 | Complete |
| TRNS-03 | Phase 5 | Pending |
| TRNS-04 | Phase 5 | Pending |
| TRNS-05 | Phase 5 | Pending |
| TRNS-06 | Phase 3 | Complete |
| CLIP-01 | Phase 3 | Complete |
| CLIP-02 | Phase 4 | Pending |
| FEED-01 | Phase 3 | Complete |
| FEED-02 | Phase 1 | Pending |
| FEED-03 | Phase 3 | Complete |
| CONF-01 | Phase 1 | Pending |
| CONF-02 | Phase 1 | Pending |
| CONF-03 | Phase 2 | Complete |

**Coverage:**
- v1 requirements: 26 total
- Mapped to phases: 26
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-05*
*Last updated: 2026-03-05 after roadmap creation*
