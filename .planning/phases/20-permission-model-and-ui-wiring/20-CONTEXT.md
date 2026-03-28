# Phase 20 — Permission Model and UI Wiring: Context

## Phase Boundary

Wire the Hold to Transcribe UI to the correct macOS permission (Input Monitoring) so users are guided to grant the permission that CGEventTap actually requires.

**Requirements:** HTT-01, HTT-02, HTT-03, HTT-04, HTT-05, HTT-06, HTT-07, HTT-09

## Implementation Decisions

### Setup Guide Popover

- **Style:** Steps-only, matching existing Accessibility guide pattern — no "why" explanation
- **Headline:** "How to enable Hold to Transcribe"
- **Steps:** Same as Accessibility guide but step 1 mentions the Input Monitoring pane specifically (e.g., "Click the + button in the Input Monitoring pane")
- **Button:** "Open Settings & Quit App" — identical to existing Accessibility guide
- **Frame:** Match existing AccessibilitySetupGuide dimensions (270px width)

### Hold to Transcribe Row Labels (Feature-Oriented Wording)

| Permission State | Status Text | Action Button |
|------------------|-------------|---------------|
| Not Determined | "Needs keyboard access." | "Enable Hold to Transcribe" |
| Denied | "Keyboard access is blocked." | "Fix Hold to Transcribe" |
| Authorized | "Ready — hold to record." | *(none)* |

- **Tone:** Feature-oriented, not permission-name-oriented. User sees "keyboard access" and "Hold to Transcribe" — not "Input Monitoring"
- **Recovery flow:** "Fix Hold to Transcribe" opens the setup guide popover (same pattern as Accessibility recovery), which then offers "Open Settings & Quit App"

### .postEvent / Auto Paste Label Cleanup

- Update all `.postEvent` PermissionKind messages to reference **only** Auto Paste
- Remove all Hold to Transcribe mentions from `.postEvent` strings
- Current: "Allow Accessibility access so Auto Paste and Hold to Transcribe work across apps."
- New: Remove Hold to Transcribe from this string — Auto Paste owns Accessibility, Hold to Transcribe owns Input Monitoring

### Two-Permission Separation

- **Each row is self-contained** — no cross-references between Input Monitoring and Accessibility permissions
- Users don't need to understand the relationship between the two permissions
- Hold to Transcribe row handles its own permission story; Auto Paste row handles its own

### Permission Checklist Tile (Scope Extension)

> **Note:** REQUIREMENTS.md lists "Permission checklist Input Monitoring tile" as out of scope. User explicitly chose to include it.

- **New tile:** `holdToTranscribe` case in PermissionKind
- **Display title:** "Input Monitoring"
- **Icon:** "keyboard.fill"
- **Required:** Yes — treated as a required permission (denied state triggers "Setup Blocked")
- **Tile order:** Microphone → Input Monitoring → Auto Paste (left to right, in setup order)
- **Action buttons:** Follow existing pattern — "Allow" (not determined), "Open Settings" (denied)

### PermissionKind Model Changes

- Add `.keyboard` (or `.holdToTranscribe`) case with:
  - `settingsURL` pointing to Privacy → Input Monitoring pane
  - Status messages using feature-oriented wording (matching row labels above)
  - `systemImage`: "keyboard.fill"
  - `title`: "Input Monitoring"
- `.postEvent` messages updated to reference only Auto Paste

## Existing Code Insights

### Reusable Assets
- **KeyboardPermissionService** already exists with `CGPreflightListenEventAccess()` and `CGRequestListenEventAccess()` — ready to wire in
- **AccessibilitySetupGuide** view provides the exact template for the new Input Monitoring setup guide
- **PermissionKind** enum in ReadinessSnapshot.swift is the single point of change for permission model
- **PermissionChecklistView** tile pattern is established and repeatable

### Integration Points
- **SetupWindowView.swift** lines 142-215: Hold to Transcribe row — update status text, button labels, and popover target
- **ReadinessSnapshot.swift** lines 24-75: PermissionKind enum — add `.holdToTranscribe` case
- **PermissionChecklistView.swift**: Add new tile in checklist bar
- **ReadinessStore.swift**: Wire keyboard permission status into readiness checks

### Patterns to Follow
- Protocol + Service pattern (KeyboardPermissionService matches PostEventPermissionService)
- PermissionGrantState enum drives all status display (authorized/notDetermined/denied)
- Color coding: green (granted), orange (needs setup), red (blocked)
- Launch argument mocking: `-mock-keyboard-status` already supported

## Deferred Ideas

*(None captured during this discussion)*
