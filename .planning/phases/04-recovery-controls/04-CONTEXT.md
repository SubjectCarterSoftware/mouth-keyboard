# Phase 4: Recovery Controls - Context

**Gathered:** 2026-03-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver safe cancel, restart, and microphone failure handling around the existing recording/transcription/clipboard loop. This phase hardens recovery inside the current background utility workflow so mistaken recordings or lost input devices do not corrupt output or strand the user. It does not add new UI surfaces, new output modes, or long-dictation behavior.

</domain>

<decisions>
## Implementation Decisions

### Cancel Behavior
- `Escape` should cancel an in-flight session during both recording and processing.
- Cancel should act as a hard stop: discard captured audio or transcription work in progress, return to a safe idle state, and leave the clipboard unchanged.
- Cancel should remain lightweight and should not require opening setup or another window.

### Restart Behavior
- Phase 4 should preserve the roadmap's in-session restart behavior rather than replacing it with "finish and start again."
- There should not be a dedicated restart keyboard shortcut.
- If restart is exposed during the session, it should be a low-friction affordance that clears the current captured audio and immediately continues recording from a clean point.
- Restart should not force the user back through setup or preferences, and should not break the background-utility flow.

### Microphone Failure Handling
- If no usable microphone is available when recording starts, show an immediate failure in the existing pill and leave recovery actions available in the menu.
- If microphone access is denied or revoked, recovery messaging should be visible and explicit but should not forcibly steal focus by opening setup automatically.
- If the selected microphone disappears during an active session, stop the session with a clear error instead of silently switching to a different microphone.
- A microphone failure after partial capture should discard the partial session and leave the clipboard unchanged.

### Claude's Discretion
- The exact restart affordance, as long as it is not a dedicated restart shortcut and still satisfies the in-session restart requirement.
- The exact copy for microphone-failure, canceled, and restarted confirmations.
- The exact visual treatment and timing of cancel or restart confirmation states, since presentation details were left open.
- Whether menu copy, menu actions, or both are used to complement the pill for recovery messaging, as long as the current app does not lose focus automatically.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ActivationStore` (`Speech2Test/Activation/ActivationStore.swift`): already owns recording state and includes a `stop()` hard-stop path that can back cancel behavior.
- `RecordingState` (`Speech2Test/Activation/RecordingState.swift`): central state machine for `.idle`, `.recording`, `.processing`, `.success`, and `.failure`.
- `RecordingPillView` / `RecordingPillPanel` (`Speech2Test/Shell/`): existing bottom-center overlay and failure surface; Phase 4 should reuse this instead of inventing a new confirmation UI.
- `AppDelegate` (`Speech2Test/App/AppDelegate.swift`): current integration point where state changes start or stop capture and update the menu-bar icon.
- `AudioCaptureService` / `AudioDeviceService` (`Speech2Test/Audio/`): current audio start, selected-device handling, and disconnect logic.

### Established Patterns
- The app remains a background or menu-bar utility; recovery should not default to opening a foreground window.
- The existing flow already protects the clipboard on transcription failure; Phase 4 should extend that same safety guarantee to cancel and microphone failures.
- The pill is the immediate transient surface; the menu is the persistent recovery surface.
- State transitions are centralized in `ActivationStore` and observed by `AppDelegate`, so recovery work should fit that pattern rather than scattering ad hoc UI control.

### Integration Points
- `AppDelegate.onRecordingStarted()` currently logs audio start failures and returns to `.idle`; this is where user-visible microphone failure handling needs to be inserted.
- `AudioCaptureService.handleSelectedDeviceDisconnect()` currently attempts silent fallback to the system default mic; Phase 4 needs to replace or wrap this with explicit failure handling.
- Any restart implementation will need to coordinate `ActivationStore`, `AudioBufferAccumulator`, and active capture so the buffer is invalidated and recording continues immediately from a clean point.
- `RecordingPillView` and menu-bar icon updates already respond to `RecordingState`; Phase 4 can reuse those hooks for cancel, restart, and failure confirmations.

</code_context>

<specifics>
## Specific Ideas

- "Visible but quiet" is the preferred recovery posture: clear failures and recovery cues without yanking focus away from the current app.
- No dedicated restart shortcut is desired.
- If the user needs to recover from a bad session, the app should prioritize safety of the clipboard and clarity of state over trying to salvage partial audio.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---
*Phase: 04-recovery-controls*
*Context gathered: 2026-03-07*
