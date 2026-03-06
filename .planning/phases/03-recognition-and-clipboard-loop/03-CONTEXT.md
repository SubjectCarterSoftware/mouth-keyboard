# Phase 3: Recognition and Clipboard Loop - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce local transcription from captured audio using whisper.cpp, finish recording via spacebar or hotkey, write the result to the clipboard with optional auto-paste, and show trustworthy recording/processing/success/failure feedback through the existing pill indicator. Cancel, restart, long-dictation segmentation, and multi-engine support are separate later phases.

</domain>

<decisions>
## Implementation Decisions

### Speech Engine
- Use **whisper.cpp** via the Swift Package Manager wrapper (whisper.spm), compiled directly into the app.
- Default model: **small** (~500MB) for accuracy with punctuation.
- Transcription mode: **batch after finish** — all audio processed after the user ends recording, not real-time streaming.
- English-only is sufficient for v1.

### Spacebar Finish Flow
- Spacebar ends the active recording and triggers transcription.
- Hotkey also ends recording (both spacebar and hotkey serve as finish keys).
- Spacebar intercepted via the **same CGEventTap** used by HotkeyService, only active when `RecordingState == .recording`.
- Spacebar is **consumed** (swallowed) — not passed through to the active application.
- Audio capture **stops immediately** on finish — no trailing buffer.
- Always attempt transcription regardless of recording duration (no minimum length gate).

### Clipboard and Auto-Paste
- On successful transcription, write text to the system clipboard via `NSPasteboard`.
- **Auto-paste enabled by default** — after clipboard write, simulate Cmd+V with a ~50-100ms delay.
- Auto-paste is toggleable in settings (user can disable).
- On failure, clipboard is **left unchanged** (preserves user's previous clipboard content).

### Silence Timeout
- If **60 seconds** of continuous silence (no speech input), auto-stop recording.
- Still attempt transcription on whatever audio was captured (may succeed if speech occurred earlier).
- **Visual warning at ~45s** — pill color shifts or subtle indicator before auto-stop fires.
- Timeout duration is **fixed at 60s** (not user-configurable in v1).

### Processing State UX
- During transcription: pill shows a **pulsing animation** (replaces waveform). No text change, no spinner.
- On success: pill flashes a **checkmark / "Copied!"** for ~1.5s, then auto-dismisses.
- On failure: pill turns **red** with a **specific failure message** (e.g., "No speech detected", "Model error") for ~2s, then auto-dismisses.
- Failure messages distinguish between types: no speech, model error, audio too short, timeout.

### Indicator Visibility (FEED-03)
- The visibility toggle **hides the pill entirely** across all states (recording, processing, success, failure).
- When pill is hidden, the **menu bar icon still changes** to reflect state (recording, processing, idle).
- Toggle lives in existing settings alongside other preferences.

### Claude's Discretion
- Exact pulsing animation style and timing for the processing state.
- Exact red color treatment for failure pill.
- Exact checkmark/success visual treatment.
- Audio buffer accumulation strategy (in-memory vs temp file) and format conversion to whisper-compatible PCM.
- RecordingState enum expansion (adding processing, success, failure cases) and transition timing.
- How the ~45s silence warning manifests visually (color shift, subtle countdown, etc.).
- Whisper model storage location and initialization strategy.
- Auto-paste implementation details (CGEvent posting vs accessibility API).

</decisions>

<specifics>
## Specific Ideas

- The pill should stay minimal and unobtrusive — pulsing is preferred over spinners or text-heavy processing states.
- Silence timeout is a safety net for forgotten recordings — user wants it to still try transcribing whatever was captured rather than discarding.
- Auto-paste is the expected default workflow: dictate, spacebar, text appears where you were typing.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AudioCaptureService` (`Speech2Test/Audio/AudioCaptureService.swift`): Captures audio via AVAudioEngine tap with buffer callbacks. Phase 3 needs to accumulate these buffers for whisper input instead of just feeding them to `AudioLevelMonitor`.
- `AudioLevelMonitor` (`Speech2Test/Audio/AudioLevelMonitor.swift`): Already processes audio buffers for RMS levels. Can be extended or paralleled to detect silence for the 60s timeout.
- `RecordingPillPanel` / `RecordingPillView` (`Speech2Test/Shell/`): Existing pill UI. Needs new visual states for processing, success, and failure.
- `ActivationStore` (`Speech2Test/Activation/ActivationStore.swift`): Manages `RecordingState` transitions. Needs expansion for processing/success/failure states.
- `HotkeyService` (`Speech2Test/Activation/HotkeyService.swift`): CGEventTap-based hotkey system. Spacebar interception during recording should integrate here.
- `ShellPreferences` (`Speech2Test/Persistence/ShellPreferences.swift`): UserDefaults-backed store. Add keys for auto-paste toggle and indicator visibility.
- `AppDelegate` (`Speech2Test/App/AppDelegate.swift`): Wires state changes to pill/audio/icon. Needs to orchestrate the new finish → process → clipboard → auto-paste → dismiss flow.

### Established Patterns
- `@MainActor` on all stores and app-level objects.
- `ObservableObject` + `@Published` for reactive state.
- ObjC exception safety via `S2TCatchObjCException` for AVAudioEngine operations.
- Lazy AVAudioEngine creation per start/stop cycle.
- UserDefaults accessed through `ShellPreferences` typed wrapper.

### Integration Points
- Audio buffer tap in `AudioCaptureService.start()` currently only feeds `levelMonitor.process(buffer:)` — needs to also accumulate buffers for whisper.
- `ActivationStore.arm()` / `.stop()` drive `AppDelegate.onRecordingStarted()` / `onRecordingStopped()` — the finish flow inserts a processing phase between stop and idle.
- `RecordingState` enum (`Speech2Test/Activation/RecordingState.swift`) is the central state machine — expanding it drives all downstream UI and logic changes.
- Pill panel show/hide is driven from `AppDelegate` observing `activationStore.$state`.

</code_context>

<deferred>
## Deferred Ideas

- Silence timeout as user-configurable duration — keep fixed at 60s for v1, revisit if users need adjustment.

</deferred>

---

*Phase: 03-recognition-and-clipboard-loop*
*Context gathered: 2026-03-06*
