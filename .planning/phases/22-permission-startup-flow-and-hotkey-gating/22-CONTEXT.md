# Phase 22: Permission Startup Flow and Hotkey Gating - Context

**Gathered:** 2025-07-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Auto-prompt Accessibility permission at startup (like Input Monitoring already does), and gate global hotkey status on Input Monitoring. This phase fixes permission timing and UI accuracy — no new features, no new permissions.

</domain>

<decisions>
## Implementation Decisions

### Accessibility auto-prompt at startup
- **D-01:** Call `CGRequestPostEventAccess()` explicitly in `applicationDidFinishLaunching`, after the existing `hotkeyService.start()` (which already triggers Input Monitoring via `CGEvent.tapCreate()`).
- **D-02:** Add a small delay (0.5–1s) between the Input Monitoring side-effect prompt and the Accessibility prompt so they don't stack.
- **D-03:** Always prompt for Accessibility regardless of Input Monitoring result — don't gate one on the other.
- **D-04:** Fire-and-forget — prompt once, respect the answer. Use the existing `hasRequestedPostEventPermission` flag in `ShellPreferences` to ensure we only auto-prompt once per install.
- **D-05:** Call `readinessStore.refresh()` after both prompts complete so the setup window reflects current status.

### Hotkey gating on Input Monitoring
- **D-06:** The Input Monitoring permission row gates ALL hotkey functionality (Control+V, Control+B, Hold-to-Transcribe), not just Hold-to-Transcribe.
- **D-07:** Rename `PermissionKind.holdToTranscribe` → `.keyboardShortcuts` throughout the codebase (ReadinessSnapshot, ReadinessStore, SetupWindowView, and all references).
- **D-08:** Update row title from "Hold to Transcribe" → "Keyboard Shortcuts".
- **D-09:** Update status messages: "Ready — shortcuts enabled." / "Needs keyboard access." / "Keyboard access is blocked."

### Dual-prompt startup UX
- **D-10:** Prompt order: Input Monitoring first (via existing `hotkeyService.start()` side-effect), then Accessibility (via explicit `CGRequestPostEventAccess()`).
- **D-11:** Small delay (0.5–1s) between prompts.
- **D-12:** Both prompts fire regardless of each other's outcome.

### The Agent's Discretion
- Exact delay duration between prompts (anywhere in 0.5–1s range)
- Whether to log prompt results for debugging
- Internal naming of the delay mechanism (DispatchQueue.asyncAfter, Task.sleep, etc.)

</decisions>

<specifics>
## Specific Ideas

- Input Monitoring already auto-prompts at launch because `hotkeyService.start()` → `holdMonitor.start()` → `CGEvent.tapCreate()` triggers macOS's system dialog as a side effect. The Accessibility prompt should feel the same to the user — a system dialog that appears shortly after launch.
- The rename from "Hold to Transcribe" to "Keyboard Shortcuts" reflects the user's discovery during UAT that Control+V also requires Input Monitoring.
- Keep the icon `keyboard.fill` and the Settings URL `Privacy_ListenEvent` — those are still accurate.

</specifics>

<canonical_refs>
## Canonical References

### Prior permission model decisions
- `.planning/phases/20-permission-model-and-ui-wiring/20-CONTEXT.md` — Two-permission separation, feature-oriented wording, tile order, setup guide pattern

### Permission services
- `Speech2Text/Permissions/KeyboardPermissionService.swift` — Input Monitoring check/request APIs (`CGPreflightListenEventAccess`, `CGRequestListenEventAccess`)
- `Speech2Text/Permissions/PostEventPermissionService.swift` — Accessibility check/request APIs (`CGPreflightPostEventAccess`, `CGRequestPostEventAccess`)

### Startup flow
- `Speech2Text/App/AppDelegate.swift` — `applicationDidFinishLaunching` is the integration point for auto-prompts

### Permission model
- `Speech2Text/Readiness/ReadinessSnapshot.swift` — `PermissionKind` enum (rename target), status messages, `isRequired` flags
- `Speech2Text/Readiness/ReadinessStore.swift` — Permission refresh and request orchestration

### UI
- `Speech2Text/Shell/SetupWindowView.swift` — `HoldToTranscribeRow` (rename target), setup window wiring
- `Speech2Text/Shell/PermissionChecklistView.swift` — `InputMonitoringSetupGuide`, tile routing

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PostEventPermissionService.requestAccess()` — Already wraps `CGRequestPostEventAccess()`, just needs to be called at startup
- `ShellPreferences.hasRequestedPostEventPermission` — Already exists as a tracking flag, perfect for fire-and-forget semantics
- `ReadinessStore.refresh()` — Already refreshes all three permission statuses, just needs to be called after prompts

### Established Patterns
- Permission services follow a consistent protocol: `currentStatus(hasPrompted:)` + `requestAccess()` + mock support via launch args
- `HoldToTranscribeRow` in SetupWindowView is the UI component that needs renaming
- `PermissionKind` is `CaseIterable` — tile order is determined by case declaration order (Microphone → Keyboard → PostEvent)

### Integration Points
- `AppDelegate.applicationDidFinishLaunching` — Insert Accessibility auto-prompt after `hotkeyService.start()` with delay
- `ReadinessSnapshot.PermissionKind.holdToTranscribe` → `.keyboardShortcuts` — Enum rename propagates to all switch statements and references
- `SetupWindowView.HoldToTranscribeRow` → rename to reflect "Keyboard Shortcuts"

</code_context>

<deferred>
## Deferred Ideas

- Renaming "Auto Paste" to "Accessibility" in the UI — user considered this but it's a separate concern from the startup flow and hotkey gating
- Re-attempting failed permission prompts on subsequent launches — decided fire-and-forget is sufficient

</deferred>

---

*Phase: 22-permission-startup-flow-and-hotkey-gating*
*Context gathered: 2025-07-09*
