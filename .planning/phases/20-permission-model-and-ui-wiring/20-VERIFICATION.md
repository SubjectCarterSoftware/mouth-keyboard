---
phase: 20-permission-model-and-ui-wiring
verified: 2026-03-24T18:30:45Z
status: passed
score: 11/11 must-haves verified
re_verification: false
---

# Phase 20: Permission Model and UI Wiring — Verification Report

**Phase Goal:** Wire the Hold to Transcribe UI to the correct macOS permission (Input Monitoring) so users are guided to grant the permission that `CGEventTap` actually requires.
**Verified:** 2026-03-24T18:30:45Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | PermissionKind.holdToTranscribe case exists with settingsURL containing Privacy_ListenEvent | ✓ VERIFIED | ReadinessSnapshot.swift:26 `case holdToTranscribe`, :60 `Privacy_ListenEvent` |
| 2 | .postEvent messages reference only Auto Paste — no Hold to Transcribe mentions | ✓ VERIFIED | `grep -c "Hold to Transcribe" ReadinessSnapshot.swift` returns 0 |
| 3 | ReadinessSnapshot.derive() accepts keyboardStatus parameter and creates .holdToTranscribe checklist item | ✓ VERIFIED | :133 `keyboardStatus: PermissionGrantState`, :144 `kind: .holdToTranscribe` with `isRequired: true` |
| 4 | ReadinessStore wires KeyboardPermissionService into snapshot derivation and permission requests | ✓ VERIFIED | :18 `keyboardService` stored property, :39 in derive call, :77-80 in requestPermission |
| 5 | CaseIterable order is microphone → holdToTranscribe → postEvent for correct tile ordering | ✓ VERIFIED | ReadinessSnapshot.swift:25-27 declaration order matches |
| 6 | Hold to Transcribe row in Settings reflects Input Monitoring status — not Accessibility | ✓ VERIFIED | SetupWindowView.swift:293-294 `keyboardPermissionService.currentStatus(hasPrompted:)` |
| 7 | Clicking Enable on the Hold to Transcribe row shows InputMonitoringSetupGuide popover | ✓ VERIFIED | SetupWindowView.swift:197 sets `showsSetupGuide = true`, :205 `InputMonitoringSetupGuide` |
| 8 | Setup guide popover button requests Input Monitoring permission (not Accessibility) | ✓ VERIFIED | SetupWindowView.swift:210 calls `requestAccess()` → :297-299 `keyboardPermissionService.requestAccess()` |
| 9 | Recovery from denied state opens Privacy > Input Monitoring pane via .holdToTranscribe kind | ✓ VERIFIED | SetupWindowView.swift:207-208 `openRecovery()`, :632 `readinessStore.openRecovery(for: .holdToTranscribe)`, settingsURL is `Privacy_ListenEvent` |
| 10 | All Hold-related labels use feature-oriented wording: "keyboard access", "Hold to Transcribe" | ✓ VERIFIED | SetupWindowView.swift:164 "Ready — hold to record.", :166 "Needs keyboard access.", :168 "Keyboard access is blocked." — zero "Accessibility" references |
| 11 | Permission checklist tile for .holdToTranscribe shows InputMonitoringSetupGuide (not AccessibilitySetupGuide) | ✓ VERIFIED | PermissionChecklistView.swift:84 `item.kind == .holdToTranscribe` → :85 `InputMonitoringSetupGuide` |

**Score:** 11/11 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Speech2Text/Readiness/ReadinessSnapshot.swift` | .holdToTranscribe case with title, systemImage, settingsURL, message(for:); updated derive() | ✓ VERIFIED | 207 lines, contains `case holdToTranscribe`, `Privacy_ListenEvent`, `keyboard.fill`, `keyboardStatus` parameter, 3 feature-oriented messages |
| `Speech2Text/Readiness/ReadinessStore.swift` | KeyboardPermissionService integration for init, refresh, requestPermission | ✓ VERIFIED | 109 lines, `keyboardService` property, `keyboardService: .live` in shared, `case .holdToTranscribe` in requestPermission |
| `Speech2Text/Shell/PermissionChecklistView.swift` | InputMonitoringSetupGuide view and PermissionTile popover routing | ✓ VERIFIED | 228 lines, `InputMonitoringSetupGuide` struct (lines 151-175), kind-based routing at line 84 |
| `Speech2Text/Shell/SetupWindowView.swift` | HoldToTranscribeRow rewired to KeyboardPermissionService with feature-oriented labels | ✓ VERIFIED | `keyboardPermissionService` property at :250, `holdToTranscribeStatus` at :293, `requestHoldToTranscribeAccess` at :297, `InputMonitoringSetupGuide` popover at :205 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| ReadinessSnapshot.derive() | PermissionKind.holdToTranscribe | keyboardStatus creates PermissionChecklistItem | ✓ WIRED | :144 `kind: .holdToTranscribe, status: keyboardStatus` |
| ReadinessStore.requestPermission(for:) | KeyboardPermissionService | .holdToTranscribe case calls requestAccess() | ✓ WIRED | :77-80 `case .holdToTranscribe → keyboardService.requestAccess()` |
| ReadinessStore.shared | KeyboardPermissionService.live | singleton wiring | ✓ WIRED | :9 `keyboardService: .live` |
| SetupWindowView.holdToTranscribeStatus | KeyboardPermissionService.currentStatus | computed property | ✓ WIRED | :294 `keyboardPermissionService.currentStatus(hasPrompted:)` |
| SetupWindowView.requestHoldToTranscribeAccess | KeyboardPermissionService.requestAccess | function call | ✓ WIRED | :299 `keyboardPermissionService.requestAccess()` |
| HoldToTranscribeRow popover | InputMonitoringSetupGuide | showsSetupGuide state | ✓ WIRED | :204-205 popover presents `InputMonitoringSetupGuide` |
| PermissionTile (holdToTranscribe) | InputMonitoringSetupGuide | kind-based routing | ✓ WIRED | :84 `item.kind == .holdToTranscribe` → :85 `InputMonitoringSetupGuide` |
| HoldToTranscribeRow instantiation | readinessStore.openRecovery(.holdToTranscribe) | openRecovery closure | ✓ WIRED | :632 `openRecovery: { readinessStore.openRecovery(for: .holdToTranscribe) }` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| HTT-01 | 20-02 | Hold to Transcribe row checks Input Monitoring status | ✓ SATISFIED | SetupWindowView.swift:293-294 uses `keyboardPermissionService.currentStatus` (not PostEvent) |
| HTT-02 | 20-02 | Enable button requests Input Monitoring permission | ✓ SATISFIED | SetupWindowView.swift:297-299 calls `keyboardPermissionService.requestAccess()` |
| HTT-03 | 20-01 | Recovery opens Privacy > Input Monitoring | ✓ SATISFIED | ReadinessSnapshot.swift:60 `Privacy_ListenEvent` URL; SetupWindowView.swift:632 routes recovery through `.holdToTranscribe` kind |
| HTT-04 | 20-02 | All labels reference "Input Monitoring", not "Accessibility" | ✓ SATISFIED | Zero `Accessibility` references in SetupWindowView.swift; labels use "keyboard access", "Hold to Transcribe" |
| HTT-05 | 20-02 | Setup guide shows Input Monitoring steps | ✓ SATISFIED | PermissionChecklistView.swift:151-175 `InputMonitoringSetupGuide` with "Input Monitoring pane" in step 1 |
| HTT-06 | 20-01 | PermissionKind includes case with Privacy_ListenEvent settingsURL | ✓ SATISFIED | ReadinessSnapshot.swift:26 `case holdToTranscribe`, :60 `Privacy_ListenEvent` (naming `.holdToTranscribe` approved in CONTEXT.md:56) |
| HTT-07 | 20-01 | .postEvent messages reference only Auto Paste | ✓ SATISFIED | `grep -c "Hold to Transcribe" ReadinessSnapshot.swift` returns 0; all three .postEvent messages reference only "Auto Paste" |
| HTT-09 | 20-01, 20-02 | Unrelated features remain unchanged | ✓ SATISFIED | `git diff --name-only` confirms no changes to HotkeyService, HoldToTranscribeMonitor, ActivationStore, or PasteService |

No orphaned requirements found — all 8 requirement IDs from PLAN frontmatter are accounted for.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | No anti-patterns found |

All `return nil` instances are legitimate Swift optional property patterns. No TODO/FIXME/HACK/placeholder comments. No stub implementations. No empty handlers.

### Human Verification Required

#### 1. InputMonitoringSetupGuide Visual Appearance

**Test:** Open Settings window → click the Input Monitoring tile's action button when status is "Needs Setup"
**Expected:** Popover appears with headline "How to enable Hold to Transcribe", 3 numbered steps mentioning "Input Monitoring pane", and an "Open Settings & Quit App" button. Frame matches AccessibilitySetupGuide width (270px).
**Why human:** Visual layout, spacing, and popover positioning cannot be verified programmatically.

#### 2. End-to-End Permission Grant Flow

**Test:** With Input Monitoring not yet granted → click "Enable Hold to Transcribe" → follow setup guide → grant permission in System Settings → relaunch app
**Expected:** Hold to Transcribe row shows "Ready — hold to record." in green. Permission checklist tile shows "Granted". Hold mode functions correctly.
**Why human:** Requires actual macOS system permission grant and app relaunch — cannot be automated without system-level access.

#### 3. Permission Checklist Tile Order

**Test:** Open setup window and observe permission tile row
**Expected:** Tiles appear left-to-right: Microphone → Input Monitoring → Auto Paste
**Why human:** Visual ordering depends on SwiftUI layout rendering; CaseIterable order is verified but visual confirmation is prudent.

### Commits Verified

| Hash | Message | Status |
|------|---------|--------|
| `aeeb32b` | feat(20-01): add .holdToTranscribe to PermissionKind and update derive() | ✓ EXISTS |
| `023c6ff` | feat(20-01): wire KeyboardPermissionService into ReadinessStore | ✓ EXISTS |
| `0818dbc` | feat(20-02): add InputMonitoringSetupGuide and update PermissionTile popover routing | ✓ EXISTS |
| `291ec0b` | feat(20-02): rewire HoldToTranscribeRow to KeyboardPermissionService with feature-oriented labels | ✓ EXISTS |

### Scope Containment

Only 4 Swift source files modified across the entire phase:
- `Speech2Text/Readiness/ReadinessSnapshot.swift`
- `Speech2Text/Readiness/ReadinessStore.swift`
- `Speech2Text/Shell/PermissionChecklistView.swift`
- `Speech2Text/Shell/SetupWindowView.swift`

No changes to HotkeyService, HoldToTranscribeMonitor, ActivationStore, PasteService, or any other unrelated files.

---

_Verified: 2026-03-24T18:30:45Z_
_Verifier: Claude (gsd-verifier)_
