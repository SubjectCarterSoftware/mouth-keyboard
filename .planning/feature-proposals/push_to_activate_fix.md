# Push and Hold Activation — Bug Investigation & Fix Proposal

## Background

Speech2Text supports two activation modes:

- **Tap (Toggle):** Press the hotkey once to start recording, press again to stop. Uses Carbon's `RegisterEventHotKey` API via the `KeyboardShortcuts` library.
- **Push and Hold (Momentary):** Hold a key to record, release to transcribe. Uses a `CGEventTap` via `HoldToTranscribeMonitor`.

The hold mode was designed to feel like a walkie-talkie — press, speak, release, done. It was built alongside the toggle mode and has full backing infrastructure: the `HoldToTranscribeMonitor` class, `HotkeyService` press/release handling, `ActivationStore.beginHoldSession()` / `finishHoldSession()`, a custom shortcut recorder in the Settings UI, and persistent storage in `ShellPreferences`. On paper, it is complete.

In practice, it has never worked. The hold key does nothing. No error surfaces to the user because the failure happens silently at the system level, before any app logic is reached.

This document identifies the root cause, maps every broken connection, and proposes a complete fix.

---

## Why It Fails

### The macOS Permission Split

Carbon hot keys (used by toggle mode) require no special permissions. `CGEventTap`, which hold mode depends on, is a different story.

On macOS Catalina and later, Apple split global input interception into two separate permission buckets:

| Permission | System Settings Location | API | Used by |
|---|---|---|---|
| Accessibility | Privacy > Accessibility | `CGPreflightPostEventAccess` / `CGRequestPostEventAccess` | Auto Paste (synthetic key events) |
| Input Monitoring | Privacy > Input Monitoring | `CGPreflightListenEventAccess` / `CGRequestListenEventAccess` | `CGEventTap` for keyboard events |

The `HoldToTranscribeMonitor` creates a `CGEventTap` to listen for `keyDown`, `keyUp`, and `flagsChanged` events. That tap requires **Input Monitoring** permission. If Input Monitoring is not granted, `CGEvent.tapCreate` returns `nil`, the monitor logs one line, and hold activation is silently dead for the rest of the session.

### The Wiring Mismatch

The existing infrastructure checks and requests the *wrong* permission for hold mode throughout:

1. `SetupWindowView.holdToTranscribeStatus` reads `postEventPermissionService` (Accessibility) — not `KeyboardPermissionService` (Input Monitoring)
2. `requestHoldToTranscribeAccess()` calls `postEventPermissionService.requestAccess()` — prompts for Accessibility, not Input Monitoring
3. The recovery action calls `readinessStore.openRecovery(for: .postEvent)` — opens Accessibility settings, not Input Monitoring settings
4. `HoldToTranscribeRow` labels the action "Enable Accessibility" / "Open Accessibility Setup"
5. `HoldToTranscribeRow.detailText` says "Needs Accessibility access" / "Accessibility is blocked" — wrong permission named
6. `HoldToTranscribeRow` popover shows `AccessibilitySetupGuide` with steps for the Accessibility pane — wrong pane entirely
7. `PermissionKind` has no `.keyboard` case — `openRecovery(for:)` has no way to route to `Privacy_ListenEvent`
8. `PermissionKind.postEvent.message(for:)` conflates Accessibility with Hold to Transcribe — claims "Accessibility access … enables Hold to Transcribe" when Hold to Transcribe actually requires Input Monitoring

The result: a user can have Accessibility fully granted, see a green status indicator in Settings, click "Enable" and nothing changes, and still have hold mode silently fail. The permission they actually need is never mentioned.

### The Dead Code

`KeyboardPermissionService` — the struct that wraps `CGPreflightListenEventAccess` and `CGRequestListenEventAccess` — exists and is correct. `ShellPreferences.hasRequestedKeyboardPermission` exists and persists correctly. Neither is connected to anything in the UI or the permission tracking system.

---

## Root Cause Summary

`HoldToTranscribeMonitor` needs Input Monitoring. The UI checks, requests, and guides the user toward Accessibility. The infrastructure for the correct permission exists but is wired to nothing. The failure is structural and silent.

---

## Event Tracking (What Hold Mode Needs)

For completeness, here is what `HoldToTranscribeMonitor` tracks and why. No changes are needed here — the logic is correct.

### Modifier key target (default: Right Option, keyCode 61)

- `CGEventType.flagsChanged` — fires once when the key is pressed, once when released. No auto-repeat.
- Pressed: `event.flags` gains the modifier flag for that keycode
- Released: `event.flags` loses the modifier flag
- Any `keyDown` while the modifier is held fires `onInterferingKeyDown` (cancels session)

### Regular key target (user-configured)

- `CGEventType.keyDown` — filtered to ignore auto-repeat events (`kCGKeyboardEventAutorepeat`)
- `CGEventType.keyUp` — triggers release
- Required modifier combination checked at press time

### Session lifecycle

```
onHoldKeyPressed  → HotkeyService.handleHoldKeyStateChange(isPressed: true)
                  → ActivationStore.beginHoldSession() → state: .recording

onHoldKeyReleased → HotkeyService.handleHoldKeyStateChange(isPressed: false)
                  → ActivationStore.finishHoldSession() → state: .processing

onInterferingKeyDown → HotkeyService.handleInterferingKeyDown()
                     → ActivationStore.cancelCurrentSession() → state: .idle
```

---

## Bug Inventory

### Bug 1 — Wrong permission checked in Settings UI
**File:** `Speech2Text/Shell/SetupWindowView.swift:292-293`

```swift
// Current
private var holdToTranscribeStatus: PermissionGrantState {
    postEventPermissionService.currentStatus(hasPrompted: preferences.hasRequestedPostEventPermission)
}

// Should be
private var holdToTranscribeStatus: PermissionGrantState {
    keyboardPermissionService.currentStatus(hasPrompted: preferences.hasRequestedKeyboardPermission)
}
```

**Impact:** User can have Accessibility granted and see a green "Hold to Transcribe" row while Input Monitoring is denied and hold mode is dead.

---

### Bug 2 — Wrong permission requested when user clicks "Enable"
**File:** `Speech2Text/Shell/SetupWindowView.swift:296-298`

```swift
// Current
private func requestHoldToTranscribeAccess() {
    preferences.recordPostEventPermissionPrompt()
    _ = postEventPermissionService.requestAccess()
}

// Should be
private func requestHoldToTranscribeAccess() {
    preferences.recordKeyboardPermissionPrompt()
    _ = keyboardPermissionService.requestAccess()
}
```

**Impact:** Clicking "Enable" prompts the user for Accessibility. The tap still fails.

---

### Bug 3 — Wrong Settings pane opened on recovery
**File:** `Speech2Text/Shell/SetupWindowView.swift:631`

```swift
// Current
openRecovery: { readinessStore.openRecovery(for: .postEvent) }

// Needs to open Input Monitoring settings (requires PermissionKind.keyboard)
openRecovery: { readinessStore.openRecovery(for: .keyboard) }
```

`PermissionKind.postEvent.settingsURL` resolves to `Privacy_Accessibility`. Input Monitoring lives at `Privacy_ListenEvent`. The user is sent to the wrong pane. This fix is blocked on adding a `.keyboard` case to `PermissionKind`.

---

### Bug 4 — Wrong action labels in `HoldToTranscribeRow`
**File:** `Speech2Text/Shell/SetupWindowView.swift:172-180`

```swift
// Current
case .notDetermined: return "Enable Accessibility"
case .denied:        return "Open Accessibility Setup"

// Should be
case .notDetermined: return "Enable Input Monitoring"
case .denied:        return "Open Input Monitoring Settings"
```

---

### Bug 5 — Wrong detail text in `HoldToTranscribeRow`
**File:** `Speech2Text/Shell/SetupWindowView.swift:161-169`

```swift
// Current
case .notDetermined: return "Needs Accessibility access."
case .denied:        return "Accessibility is blocked."

// Should be
case .notDetermined: return "Needs Input Monitoring access."
case .denied:        return "Input Monitoring is blocked."
```

**Impact:** Even the passive description text points the user toward the wrong permission.

---

### Bug 6 — Wrong setup guide shown in the row popover
**File:** `Speech2Text/Shell/SetupWindowView.swift:204-212`

`HoldToTranscribeRow` uses `AccessibilitySetupGuide`, which walks through adding the app to Privacy > Accessibility. Input Monitoring requires adding the app to Privacy > Input Monitoring — a different pane with different steps. The guide needs to be replaced with an `InputMonitoringSetupGuide` that references the correct Settings pane.

---

### Bug 7 — `KeyboardPermissionService` not injected into `SetupWindowView`
**File:** `Speech2Text/Shell/SetupWindowView.swift:249`

```swift
// Current — only postEvent is present
private let postEventPermissionService = PostEventPermissionService.live

// Needs to be added alongside existing property
private let keyboardPermissionService = KeyboardPermissionService.live
```

---

### Bug 8 — `PermissionKind` has no `.keyboard` case
**File:** `Speech2Text/Readiness/ReadinessSnapshot.swift:24-57`

The `PermissionKind` enum only defines `.microphone` and `.postEvent`. There is no `.keyboard` (or `.inputMonitoring`) case. This means:
- `openRecovery(for:)` has no way to route to `Privacy_ListenEvent`
- The recovery action falls through to `.postEvent`, opening the wrong pane
- No `title`, `systemImage`, or `message(for:)` exist for the Input Monitoring permission

A `.keyboard` case must be added with:
- `title`: "Input Monitoring" (or "Hold to Transcribe")
- `systemImage`: "keyboard" (or another appropriate SF Symbol)
- `settingsURL`: `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`
- `message(for:)` entries for all three `PermissionGrantState` values

This is **not optional** — it is required for the recovery path (Bug 3) to function.

---

### Bug 9 — `.postEvent` messages conflate Accessibility with Hold to Transcribe
**File:** `Speech2Text/Readiness/ReadinessSnapshot.swift:59-74`

```swift
// Current
case (.postEvent, .authorized):
    return "Accessibility access can Auto Paste into other apps and enables Hold to Transcribe."
case (.postEvent, .notDetermined):
    return "Allow Accessibility access so Auto Paste and Hold to Transcribe work across apps."
case (.postEvent, .denied):
    return "Accessibility access is blocked. Re-enable it in System Settings to use Auto Paste and Hold to Transcribe."
```

These messages incorrectly claim Accessibility (postEvent) "enables Hold to Transcribe." Hold to Transcribe requires Input Monitoring (keyboard), not Accessibility. The `.postEvent` messages should reference only Auto Paste. Hold to Transcribe messaging belongs on the new `.keyboard` case.

---

### Bug 10 — UI tests assert the buggy behavior as correct
**File:** `Speech2TextUITests/PermissionRecoveryFlowTests.swift`

Three existing UI tests validate the *wrong* strings and will need updating:

- `testHoldToTranscribeRowShowsEnableActionWhenAccessibilityIsUndetermined` (line 80): asserts `"Enable Accessibility"` exists
- `testHoldToTranscribeRowShowsRecoveryActionWhenAccessibilityIsBlocked` (line 120): asserts `"Open Accessibility Setup"` exists
- `testHoldToTranscribeActionShowsAccessibilityGuide` (lines 136-141): asserts `"Enable Accessibility"` button and `"How to enable Accessibility access"` guide text

After the fix, these must assert the Input Monitoring equivalents instead.

---

## Requirements

| REQ-ID | Requirement |
|--------|-------------|
| HTT-01 | Hold to Transcribe row in Settings checks Input Monitoring permission status (`CGPreflightListenEventAccess`), not Accessibility |
| HTT-02 | Clicking "Enable" on the Hold to Transcribe row requests Input Monitoring permission (`CGRequestListenEventAccess`) |
| HTT-03 | Recovery action from a denied Hold to Transcribe row opens Privacy > Input Monitoring, not Privacy > Accessibility |
| HTT-04 | All user-facing labels and descriptions in the Hold to Transcribe row reference "Input Monitoring", not "Accessibility" |
| HTT-05 | Setup guide popover shows steps for adding the app to Privacy > Input Monitoring |
| HTT-06 | `PermissionKind` includes a `.keyboard` case with the correct `settingsURL` for `Privacy_ListenEvent` |
| HTT-07 | `.postEvent` permission messages reference only Auto Paste — no mention of Hold to Transcribe |
| HTT-08 | Existing UI tests are updated to assert the corrected Input Monitoring strings |
| HTT-09 | Toggle/tap activation, Auto Paste permission flow, and all unrelated features remain unchanged |
| HTT-10 | Hold mode functions end-to-end when Input Monitoring is granted (manual verification — requires system permission) |

---

## Proposed Fix

### Scope

**5 production files, 1 test file.** No logic changes to `HotkeyService`, `HoldToTranscribeMonitor`, `ActivationStore`, or `ShellPreferences` — the underlying implementation is correct.

### Changes

**`ReadinessSnapshot.swift`** — Foundation for recovery routing

1. Add `PermissionKind.keyboard` case with:
   - `title`: "Input Monitoring"
   - `systemImage`: "keyboard"
   - `settingsURL`: `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`
   - `message(for:)` entries for `.authorized`, `.notDetermined`, `.denied` referencing Input Monitoring
2. Remove "Hold to Transcribe" from `.postEvent` messages — `.postEvent` should only reference Auto Paste

**`SetupWindowView.swift`** — Primary wiring fix

3. Add `private let keyboardPermissionService = KeyboardPermissionService.live`
4. Replace `holdToTranscribeStatus` to use `keyboardPermissionService` + `preferences.hasRequestedKeyboardPermission`
5. Replace `requestHoldToTranscribeAccess()` to use `keyboardPermissionService` + `preferences.recordKeyboardPermissionPrompt()`
6. Replace `openRecovery` closure to use `.keyboard` instead of `.postEvent`

**`HoldToTranscribeRow` (in `SetupWindowView.swift`)** — User-facing text

7. Update `actionTitle` from "Enable Accessibility" / "Open Accessibility Setup" to "Enable Input Monitoring" / "Open Input Monitoring Settings"
8. Update `detailText` from "Needs Accessibility access" / "Accessibility is blocked" to "Needs Input Monitoring access" / "Input Monitoring is blocked"
9. Replace `AccessibilitySetupGuide` with an `InputMonitoringSetupGuide` that references the correct Settings pane and steps
10. Rename `showsAccessibilityGuide` state to `showsInputMonitoringGuide` for clarity

**`PermissionChecklistView.swift`** — Setup guide

11. Create `InputMonitoringSetupGuide` view (parallel to existing `AccessibilitySetupGuide`) with Input Monitoring-specific setup steps, OR parameterize the existing guide to accept a title and steps

**`ReadinessStore.swift`** — Permission request routing *(only if `.keyboard` is added to `requestPermission(for:)` switch)*

12. Add a `.keyboard` case to `requestPermission(for:)` that calls `keyboardPermissionService.requestAccess()` and records the prompt — this is needed if the permission checklist ever shows a keyboard tile, but not strictly required if the hold row remains the only surface

**`PermissionRecoveryFlowTests.swift`** — Test corrections

13. Update `testHoldToTranscribeRowShowsEnableActionWhenAccessibilityIsUndetermined`: assert `"Enable Input Monitoring"` instead of `"Enable Accessibility"`
14. Update `testHoldToTranscribeRowShowsRecoveryActionWhenAccessibilityIsBlocked`: assert `"Open Input Monitoring Settings"` instead of `"Open Accessibility Setup"`
15. Update `testHoldToTranscribeActionShowsAccessibilityGuide`: assert `"How to enable Input Monitoring access"` and correct guide text

### What Does Not Change

- `HotkeyService` — event handling and hold monitor lifecycle are correct
- `HoldToTranscribeMonitor` — event tracking logic is correct
- `ActivationStore` — hold session origin tracking is correct
- `ShellPreferences` — `holdShortcutKeyCode`, `holdShortcutModifiers`, `hasRequestedKeyboardPermission` all exist and work
- Toggle/tap activation — untouched
- Auto Paste permission flow — untouched (still uses `PostEventPermissionService` / Accessibility)
- `RecoveryActions.swift` — generic `openSettings(for:)` already routes via `PermissionKind.settingsURL`, no changes needed

---

## Phase Breakdown (GSD)

This fix is small enough for a single phase with two plans.

### Phase: Hold-to-Transcribe Permission Fix

**Goal:** Wire the Hold to Transcribe UI to the correct macOS permission (Input Monitoring) so users are guided to grant the permission that `CGEventTap` actually requires.

**Requirements:** HTT-01 through HTT-10

#### Plan 1: Permission Model and UI Wiring

**Tasks:**
1. Add `PermissionKind.keyboard` to `ReadinessSnapshot.swift` with correct `settingsURL`, `title`, `systemImage`, and `message(for:)`
2. Remove "Hold to Transcribe" from `.postEvent` messages
3. Add `keyboardPermissionService` to `SetupWindowView`
4. Rewire `holdToTranscribeStatus` and `requestHoldToTranscribeAccess()` to use keyboard service
5. Replace `openRecovery` closure to use `.keyboard`
6. Update `HoldToTranscribeRow` labels, detail text, and action titles
7. Create `InputMonitoringSetupGuide` (or parameterize existing guide) and wire into `HoldToTranscribeRow` popover

**Success criteria:**
- Hold row shows "Needs Input Monitoring access" when undetermined
- Hold row shows "Input Monitoring is blocked" when denied
- "Enable Input Monitoring" button appears when undetermined
- "Open Input Monitoring Settings" button appears when denied
- Guide popover references Input Monitoring pane
- Recovery opens `Privacy_ListenEvent` pane
- Accessibility/Auto Paste tile is unaffected

#### Plan 2: Test Updates and Verification

**Tasks:**
1. Update `PermissionRecoveryFlowTests` assertions for corrected strings
2. Verify all existing unit tests still pass (HotkeyServiceTests, ActivationStoreTests, ShellPreferencesModelTests, PermissionServiceTests, ReadinessStateTests)
3. Build and run full test suite

**Success criteria:**
- All 3 updated UI tests pass with corrected assertions
- All existing unit tests pass without modification
- Build succeeds with zero warnings related to the changed files

---

## Test Coverage

### Existing tests that validate underlying hold logic (no changes needed):

- `HotkeyServiceTests`: hold press/release/cancel/reject cases
- `ActivationStoreTests`: `beginHoldSession`, `finishHoldSession`, origin isolation
- `ShellPreferencesModelTests`: `holdShortcut` defaults, round-trip, reset
- `PermissionServiceTests`: `KeyboardPermissionService` prompt history differentiation, adapter invocation, authorized preflight

### Existing tests that need updating:

- `PermissionRecoveryFlowTests.testHoldToTranscribeRowShowsEnableActionWhenAccessibilityIsUndetermined` → assert "Enable Input Monitoring"
- `PermissionRecoveryFlowTests.testHoldToTranscribeRowShowsRecoveryActionWhenAccessibilityIsBlocked` → assert "Open Input Monitoring Settings"
- `PermissionRecoveryFlowTests.testHoldToTranscribeActionShowsAccessibilityGuide` → assert "How to enable Input Monitoring access" + correct button text

### Tests that may need new cases:

- `ReadinessStateTests`: if `ReadinessSnapshot.derive()` gains a `keyboardStatus` parameter, existing tests would need updating and a new test should verify `.keyboard` tile status derivation

### Manual verification (requires system permission grant):

- HTT-10: Grant Input Monitoring in System Settings → hold key starts recording → release transcribes → clipboard receives result

---

## Traceability

| REQ-ID | Bugs Addressed | Plan |
|--------|---------------|------|
| HTT-01 | Bug 1, Bug 7 | P01 |
| HTT-02 | Bug 2, Bug 7 | P01 |
| HTT-03 | Bug 3, Bug 8 | P01 |
| HTT-04 | Bug 4, Bug 5 | P01 |
| HTT-05 | Bug 6 | P01 |
| HTT-06 | Bug 8 | P01 |
| HTT-07 | Bug 9 | P01 |
| HTT-08 | Bug 10 | P02 |
| HTT-09 | — | P01, P02 |
| HTT-10 | All | Manual |

---

## Comparison: Before and After

| | Before fix | After fix |
|---|---|---|
| Permission displayed for hold row | Accessibility | Input Monitoring |
| Permission requested on "Enable" | Accessibility | Input Monitoring |
| Settings link on deny | Privacy > Accessibility | Privacy > Input Monitoring |
| Setup guide | "Enable Accessibility access" | "Enable Input Monitoring access" |
| Detail text (undetermined) | "Needs Accessibility access" | "Needs Input Monitoring access" |
| Detail text (denied) | "Accessibility is blocked" | "Input Monitoring is blocked" |
| `.postEvent` messages mention Hold to Transcribe | Yes (incorrect) | No — only Auto Paste |
| `PermissionKind` has `.keyboard` case | No | Yes |
| Recovery opens correct pane | No (`Privacy_Accessibility`) | Yes (`Privacy_ListenEvent`) |
| Hold mode works when only Accessibility granted | No | No (correct — different permission) |
| Hold mode works when Input Monitoring granted | No (UI misleads user away from it) | Yes |
| UI tests assert correct strings | No (validate buggy labels) | Yes |
| Toggle mode | Unchanged | Unchanged |
| Auto Paste flow | Unchanged | Unchanged |

---

## Open Questions

1. **Should `ReadinessSnapshot.derive()` gain a `keyboardStatus` parameter?** Currently it only takes `microphoneStatus` and `postEventStatus`. Adding `keyboardStatus` would let the permission checklist tiles show Input Monitoring alongside Microphone and Accessibility. This is the *correct* long-term architecture but increases scope (ReadinessStore needs to inject KeyboardPermissionService, ReadinessStateTests need updating). Recommendation: defer to a follow-up unless the phase planner decides to include it.

2. **Should the permission checklist (setup landing page) show an Input Monitoring tile?** Currently it shows Microphone and Auto Paste tiles. Adding a third tile for Input Monitoring would give full permission visibility on the setup page. This couples to question 1 and can be deferred.

3. **Should `HoldToTranscribeMonitor.start()` retry after permission grant?** Currently, if the tap fails on first `start()` call, the monitor logs and returns `false`. If the user grants Input Monitoring mid-session, the monitor won't self-recover until the next app launch or `HotkeyService.startListening()` call. A retry-on-foreground mechanism could improve UX but adds complexity beyond the wiring fix.
