# Phase 1: Foundation and Permissions - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the native macOS background utility shell for Speech2Test so it can live in the menu bar, show whether it is ready or blocked, and onboard the required permissions clearly. This phase establishes the app presence, first-run setup behavior, and readiness model only. Recording, hotkey execution, microphone capture flow, and transcription behavior are separate later phases.

</domain>

<decisions>
## Implementation Decisions

### Permission Flow
- Permission setup should begin on first launch rather than waiting for the first recording attempt.
- First-run setup should use a checklist-style flow that shows required items and clear next steps.
- If permission is denied, the app should keep a persistent blocked warning rather than quietly degrading.
- Recovery should both explain what is wrong and provide a direct path into the relevant System Settings area.

### Readiness and Blocked States
- The menu bar presence should stay subtle; detailed state belongs inside the app menu rather than the menu bar itself.
- Opening the menu should show a compact status card at the top with the current readiness state and the next action.
- When the app transitions from blocked to ready, it should give a brief confirmation rather than a loud persistent success state.
- When the app is blocked, the primary menu action should be a clear setup/recovery action such as "Fix setup."

### App Presence
- Speech2Test should behave as a menu bar utility first, not as a standard Dock-forward app.
- Regular day-to-day use should be menu-bar only, without a normal persistent Dock presence.
- On first launch, the app should open its setup/readiness UI once, then stay in the menu bar afterward.
- The app should keep a normal Quit action in the menu; Phase 1 does not need a special always-on quit model.

### Claude's Discretion
- Exact copywriting for checklist items, blocked warnings, and recovery messaging.
- Exact visual treatment of the menu bar icon as long as it stays subtle and the menu carries the detailed state.
- Exact structure of the Phase 1 settings/setup UI, provided it supports the chosen checklist-style first-run flow.
- Exact visual form of the brief "ready" confirmation after permissions are fixed.

</decisions>

<specifics>
## Specific Ideas

- The app should feel like a restrained utility, not a full desktop application competing for attention.
- The shell should be explicit when something is blocked, but otherwise stay quiet and low-distraction.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- None yet — this repo is greenfield and does not contain an existing app shell or shared UI/components.

### Established Patterns
- None yet — Phase 1 will establish the baseline patterns for app lifecycle, readiness state, and settings persistence.

### Integration Points
- The menu bar shell created in this phase will become the control surface that later phases extend with activation, recording, and processing states.
- The readiness/blocked state created in this phase should become the shared foundation for later hotkey, microphone, and transcription availability checks.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---
*Phase: 01-foundation-and-permissions*
*Context gathered: 2026-03-05*
