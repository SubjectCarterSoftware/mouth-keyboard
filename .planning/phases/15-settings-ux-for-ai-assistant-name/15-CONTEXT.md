# Phase 15: Settings UX for AI Assistant Name - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Ship an AI Assistant settings tile in the existing setup window plus a dedicated change flow where users can switch between preset or custom assistant names, optionally calibrate the active name, and verify that changes affect trigger parsing for subsequent sessions without restarting the app. This phase exposes the already-built trigger profile and calibration behavior through settings UX; it does not change parsing or routing rules from phases 12-14.

</domain>

<decisions>
## Implementation Decisions

### Settings Surface
- Add a distinct `AI Assistant` tile/section inside the existing setup window.
- The tile should show the active assistant name as the primary value.
- The tile should include a quiet secondary status line rather than becoming a dense info panel.
- The tile should subtly indicate whether the active name is `default`, another preset, or `custom`.
- Calibration state may appear on the tile, but only as subdued status, not a warning-heavy banner.
- The tile exposes one explicit button: `Change Assistant Name`.

### Assistant Change Flow
- Clicking `Change Assistant Name` opens a sheet, not inline expansion or a separate new window.
- The sheet uses a single-page layout that shows preset options and custom-name entry in one place.
- Selecting `Zeus`, `Atlas`, or `Gaia` applies immediately without an extra save/confirm step.
- Entering a custom name makes that name active when the user saves it; calibration remains an optional follow-up step.
- The flow should stay lightweight and avoid extra confirmation dialogs unless data would be lost.

### Calibration Experience
- After a name change, calibration is presented as the recommended next step but is explicitly skippable.
- Later recalibration stays inside the same assistant configuration sheet rather than adding a second persistent action on the main tile.
- Calibration uses a guided three-step sample flow with retry handling for invalid or noisy captures.
- After calibration completes, show a concise alias summary so users can see what runtime trigger variants were stored.

### Carry-Forward Contracts
- Preset switching remains immediate; calibration is not a prerequisite to activate `Zeus`, `Atlas`, or `Gaia`.
- Custom and preset trigger updates take effect for subsequent sessions without app restart.
- Re-running calibration replaces aliases for the active profile instead of merging with old calibration data.

### Claude's Discretion
- Exact sheet copy, button labels, and helper text as long as the flow stays explicit and low-distraction.
- Exact visual treatment of the tile within the current SwiftUI settings layout.
- Exact phrasing of the secondary status line and alias summary.
- Whether the sheet auto-focuses the custom-name field when `Custom` is selected.

</decisions>

<specifics>
## Specific Ideas

- Keep the AI Assistant surface distinct and easy to scan in settings rather than hiding it under Conversion Modes.
- Existing architecture notes already point toward placing the AI Assistant tile directly under the permissions block in settings.
- Use the app's restrained utility tone: name and status should be visible, but avoid noisy warnings by default.
- The main tile should answer three quick questions at a glance: what name is active, whether it is default/preset/custom, and whether calibration has updated aliases.
- Calibration should feel like a guided follow-up, not a mandatory onboarding gate.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Speech2Text/Shell/SetupWindowView.swift`: fixed-width settings window that already hosts inline sections and button-driven entry points; Phase 15 should extend this surface instead of introducing a new preferences shell.
- `Speech2Text/Shell/IntentListView.swift` and `Speech2Text/Shell/IntentEditView.swift`: existing sheet-based settings subflow pattern for deeper configuration screens.
- `Speech2Text/Persistence/ShellPreferences.swift`: published `activeTriggerProfile` plus `setTriggerPreset`, `setCustomTrigger`, and `applyCalibrationAliases` provide the UI-facing mutation points.
- `Speech2Text/Activation/TriggerProfile.swift`: existing preset/custom profile model and displayable active-name data.
- `Speech2Text/Activation/TriggerCalibrationSession.swift`: already encodes the locked 3-valid-sample calibration contract with retry semantics.

### Established Patterns
- Settings changes live inside the existing setup window, not a separate preferences app flow.
- Deeper editing flows open sheets from settings instead of replacing the root setup window or spawning extra navigation layers.
- UI-facing state is driven by `@MainActor` `ObservableObject` models, with runtime changes published through `ShellPreferences`.
- The product favors restrained, low-distraction utility UI over dense control panels.

### Integration Points
- `SetupWindowView` is the natural host for the new `AI Assistant` tile and the related sheet presentation state.
- The assistant configuration sheet should bind directly to `ShellPreferences.activeTriggerProfile` and its existing mutation APIs.
- `ActivationStore` already reads `preferences.activeTriggerProfile.activeAliases` during finalize-time parsing, so Phase 15 verification can check runtime behavior without adding a restart step.
- Existing settings UI tests and launch-argument override patterns can be extended for end-to-end trigger-name configuration coverage.

</code_context>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>

---
*Phase: 15-settings-ux-for-ai-assistant-name*
*Context gathered: 2026-03-20*
