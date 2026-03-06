# Phase 2: Activation and Capture - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Let the user configure a system-wide activation hotkey and tap mode, arm recording immediately when the hotkey fires, capture audio from the chosen microphone, and show a live recording indicator — all without interrupting system audio playback. Session finish controls (spacebar), cancel/restart, transcription, and clipboard output are separate later phases.

</domain>

<decisions>
## Implementation Decisions

### Hotkey Configuration UI
- Hotkey configuration lives in the existing setup window (Phase 1) as a new section — not a separate Preferences window.
- Interaction pattern: click-to-record field (user clicks the field, presses desired key combo, field captures it — like Raycast/Alfred).
- The hotkey field is always editable, not locked to the initial setup flow. User can re-record a new combo at any time.
- Default hotkey: **Cmd+Shift+Z**, pre-filled. User can change it but is not required to.

### Tap Mode
- Default tap mode on first launch: **double-tap**.
- Single-tap vs double-tap toggle lives in the setup/settings window alongside the hotkey field.
- In double-tap mode, a stray single tap is silently ignored — no feedback, no action.
- The inter-tap detection window is a fixed sensible default (not user-configurable in v1).

### Microphone Selection
- Device picker: user can choose a specific input device from a list of available mics.
- Picker lives in the setup/settings window (alongside hotkey and tap mode).
- Default selection: "System Default" option at the top of the picker — follows whatever the OS default input is.
- If the selected mic disconnects during use, fall back to the system default silently (no error, no interruption).

### Activation Acknowledgment
- Menu bar icon changes to a recording variant when activation fires and recording is armed.
- Optional activation sound (a brief, subtle tone to confirm recording started), toggleable in the setup/settings window.
- Sound is **on by default**. User can disable in settings.

### Recording Indicator
- A small pill/capsule floating at the **bottom center of the screen**, above all windows.
- Shows: mic icon + live audio waveform animation reflecting input levels.
- Appears on all Spaces/desktops (not just the active Space).
- Floats above all other windows including full-screen apps (NSPanel or high window level).
- **Read-only in Phase 2** — no interactive controls. Cancel/finish interactions are Phase 3.

### Claude's Discretion
- Exact visual design of the pill indicator (size, corner radius, blur backdrop, colors).
- Exact waveform animation style (bars vs line vs dots — as long as it reflects actual input levels).
- Exact recording-state menu bar icon variant.
- Exact sound clip used for the activation tone.
- Specific inter-tap window duration (suggested: 350ms).
- How hotkey conflicts with system shortcuts are reported to the user.

</decisions>

<specifics>
## Specific Ideas

- "Small and subtle and centered on the screen at the bottom" — the recording indicator should be unobtrusive, not a large overlay.
- The indicator should feel like the Dynamic Island-style pills on iOS — compact and purposeful.
- Cmd+Shift+Z is the explicit desired default hotkey.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ShellPreferences` (`Speech2Test/Persistence/ShellPreferences.swift`): UserDefaults-backed store using `com.elicarter.Speech2Test.shell` suite. Add keys for hotkey binding, tap mode, mic selection, and activation sound toggle here.
- `ReadinessStore` (`Speech2Test/Readiness/ReadinessStore.swift`): `@MainActor ObservableObject` shared singleton. A new `ActivationStore` or `RecordingStore` following the same pattern should manage activation and recording state.
- `ReadinessSnapshot` / `ReadinessState` (`Speech2Test/Readiness/ReadinessSnapshot.swift`): Established state enum pattern — a similar `RecordingState` enum (idle / armed / recording) should follow this convention.
- `AppDelegate` (`Speech2Test/App/AppDelegate.swift`): Manages NSWindow lifecycle via `NSHostingController`. The floating recording indicator panel should be created and managed here using the same approach.
- `SetupWindowView` (`Speech2Test/Shell/SetupWindowView.swift`): The existing setup window to extend with a new "Activation" settings section.
- `StatusMenuView` (`Speech2Test/Shell/StatusMenuView.swift`): The status menu to update with recording state when active.

### Established Patterns
- `@MainActor` on all stores and app-level objects.
- SwiftUI views hosted via `NSHostingController` inside `NSWindow`/`NSPanel`.
- `ObservableObject` + `@Published` for reactive state.
- UserDefaults accessed through a typed wrapper (`ShellPreferences`) — extend this, don't bypass it.
- Launch argument overrides for testing (`-ui-testing`, `-reset-shell-preferences`, etc.) — new Phase 2 flags should follow the same pattern.

### Integration Points
- The recording indicator panel hooks into `AppDelegate` — `AppDelegate` shows/hides it in response to `ActivationStore`/`RecordingStore` state changes.
- The hotkey registration service replaces or extends the existing `KeyboardPermissionService` integration — it will need `AXIsProcessTrusted()` to already be true (gated by Phase 1 readiness check).
- `ReadinessStore` readiness gate: Phase 2 activation should only arm if `ReadinessStore.snapshot.state == .ready`.
- Menu bar icon state change (idle → recording) is driven from `AppDelegate` observing the new recording store.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---
*Phase: 02-activation-and-capture*
*Context gathered: 2026-03-05*
