---
phase: 22-permission-startup-flow-and-hotkey-gating
verified: 2026-03-24T22:15:00Z
status: passed
score: 7/7 must-haves verified
re_verification:
  previous_status: passed
  previous_score: 7/7
  previous_note: "Previous VERIFICATION.md verified Phase 22-01 state (Keyboard Shortcuts labels + 0.75s delay), which UAT then rejected. This re-verification covers Phase 22-02 gap closure — the actual final state of the phase."
  gaps_closed:
    - "Setup window shows 'Hold to Transcribe:' as the Input Monitoring row label"
    - "Action buttons read 'Enable Hold to Transcribe' / 'Fix Hold to Transcribe'"
    - "Setup guide shows 'How to enable Hold to Transcribe'"
    - "Hold to Transcribe row renders as direct Form child with LabeledContent inside body"
    - "Accessibility prompt fires immediately on startup when Input Monitoring is already granted — no delay"
    - "Accessibility prompt is skipped on startup when Input Monitoring is not yet granted"
    - "Fire-once guard still prevents re-prompting on subsequent launches"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Open Setup window when Input Monitoring is not determined — verify 'Hold to Transcribe:' row label and 'Enable Hold to Transcribe' button appear"
    expected: "Row label reads 'Hold to Transcribe:', not 'Keyboard Shortcuts:'. Enable button reads 'Enable Hold to Transcribe'."
    why_human: "Visual verification of rendered SwiftUI form labels — cannot confirm rendering from source alone."
  - test: "Click 'Enable Hold to Transcribe' — verify setup guide popover title"
    expected: "Popover title reads 'How to enable Hold to Transcribe', not 'How to enable Keyboard Shortcuts'."
    why_human: "Visual verification of popover content."
  - test: "After granting Input Monitoring and relaunching — verify Accessibility dialog appears immediately (no delay)"
    expected: "Accessibility permission dialog appears immediately on relaunch after IM grant. On all subsequent launches, no Accessibility dialog appears."
    why_human: "Requires real macOS permission dialogs and quit-relaunch cycle — cannot simulate programmatically."
---

# Phase 22: Permission Startup Flow and Hotkey Gating — Verification Report

**Phase Goal:** Fix two UAT failures from Phase 22: (1) Revert all user-facing text from "Keyboard Shortcuts" to "Hold to Transcribe" while keeping internal enum as `.keyboardShortcuts`. Fix KeyboardShortcutsRow container to match Recorder row pattern. (2) Replace 0.75s delay approach with CGPreflightListenEventAccess()-gated prompt that fires only after Input Monitoring is already granted.
**Verified:** 2026-03-24T22:15:00Z
**Status:** passed
**Re-verification:** Yes — after Phase 22-02 gap closure. Previous VERIFICATION.md reflected Phase 22-01 state (which UAT rejected). This report verifies the final 22-02 implementation.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Setup window shows 'Hold to Transcribe:' as the Input Monitoring row label — not 'Keyboard Shortcuts:' | VERIFIED | `SetupWindowView.swift` line 184: `LabeledContent("Hold to Transcribe:") {`. Grep for `"Keyboard Shortcuts[":.]` in `SetupWindowView.swift` returns zero matches. |
| 2 | Hold to Transcribe row renders with the same container pattern as Start/Stop, Stop Only, Stop & Auto Paste rows | VERIFIED | `SetupWindowView.swift` lines 625-634: `KeyboardShortcuts.Recorder(...)` rows and `KeyboardShortcutsRow(...)` are all direct `Form` children at the same indentation level. Outer `LabeledContent { KeyboardShortcutsRow } label: { Text("Keyboard Shortcuts:") }` wrapper is gone. The label is now inside `KeyboardShortcutsRow.body` via `LabeledContent("Hold to Transcribe:")`, matching the Recorder pattern. |
| 3 | Setup guide shows 'How to enable Hold to Transcribe' — not 'How to enable Keyboard Shortcuts' | VERIFIED | `PermissionChecklistView.swift` line 156: `Text("How to enable Hold to Transcribe")`. Grep for "How to enable Keyboard Shortcuts" returns zero matches. |
| 4 | Action buttons read 'Enable Hold to Transcribe' / 'Fix Hold to Transcribe' — not 'Enable Keyboard Shortcuts' / 'Fix Keyboard Shortcuts' | VERIFIED | `SetupWindowView.swift` lines 177, 179: `return "Enable Hold to Transcribe"` and `return "Fix Hold to Transcribe"`. Grep for `"Enable Keyboard Shortcuts"` and `"Fix Keyboard Shortcuts"` returns zero matches. |
| 5 | Accessibility prompt fires immediately on startup when Input Monitoring is already granted — no delay | VERIFIED | `AppDelegate.swift` lines 36-41: synchronous `if !preferences.hasRequestedPostEventPermission, CGPreflightListenEventAccess()` block calls `postEventService.requestAccess()` and `readinessStore.refresh()` directly — no `DispatchQueue.main.asyncAfter`. Grep for `asyncAfter.*0.75` returns zero matches. |
| 6 | Accessibility prompt is skipped on startup when Input Monitoring is not yet granted | VERIFIED | `AppDelegate.swift` line 37: `CGPreflightListenEventAccess()` as second condition of the `if` statement. When IM is not granted this returns false, so the entire block is skipped. Logic is synchronous and short-circuits correctly. |
| 7 | Fire-once guard still prevents re-prompting on subsequent launches | VERIFIED | `AppDelegate.swift` line 36: `if !preferences.hasRequestedPostEventPermission,` is the first condition. Line 38: `preferences.recordPostEventPermissionPrompt()` sets the flag BEFORE `requestAccess()` (crash-safe). On all subsequent launches the guard condition is false, so neither `requestAccess()` nor `refresh()` fires. |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Speech2Text/Shell/SetupWindowView.swift` | Reverted user-facing labels; LabeledContent inside KeyboardShortcutsRow body; direct Form child | VERIFIED | Line 177: `"Enable Hold to Transcribe"`. Line 179: `"Fix Hold to Transcribe"`. Line 184: `LabeledContent("Hold to Transcribe:")`. Lines 629-634: `KeyboardShortcutsRow(...)` is a direct Form child. Outer LabeledContent wrapper with `Text("Keyboard Shortcuts:")` is absent. |
| `Speech2Text/Shell/PermissionChecklistView.swift` | Guide title reverted to 'How to enable Hold to Transcribe' | VERIFIED | Line 156: `Text("How to enable Hold to Transcribe")`. Zero matches for "How to enable Keyboard Shortcuts". |
| `Speech2Text/App/AppDelegate.swift` | IM-gated Accessibility auto-prompt; no delay; fire-once guard | VERIFIED | Line 12: `postEventService` property initialized. Lines 36-41: `if !preferences.hasRequestedPostEventPermission, CGPreflightListenEventAccess()` block with `recordPostEventPermissionPrompt()` before `requestAccess()` before `refresh()`. No `asyncAfter`. No `[weak self]` closure (not needed — synchronous calls). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `SetupWindowView.swift` | Form `.formStyle(.columns)` | `KeyboardShortcutsRow` body returns `LabeledContent("Hold to Transcribe:")` directly | WIRED | `LabeledContent("Hold to Transcribe:")` at line 184 is inside `KeyboardShortcutsRow.body`. `KeyboardShortcutsRow(...)` at line 629 is a direct Form child. Pattern matches `Recorder("Start / Stop:", ...)` rows at lines 625-627. |
| `AppDelegate.swift` | `CGPreflightListenEventAccess` | Conditional gate before `postEventService.requestAccess()` | WIRED | Line 37: `CGPreflightListenEventAccess()` appears as the second condition in the compound `if`. Line 39: `postEventService.requestAccess()` fires only when both conditions are true. Order is correct: guard flag set first (line 38), then access request (line 39), then UI refresh (line 40). |
| `AppDelegate.swift` | `ShellPreferences.hasRequestedPostEventPermission` | Fire-once guard | WIRED | Line 36 reads the flag. Line 38 sets it via `preferences.recordPostEventPermissionPrompt()`. `preferences` property initialized at line 9. |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| P22-RENAME | 22-01-PLAN, 22-02-PLAN | All user-facing text references "Hold to Transcribe" (not "Keyboard Shortcuts"); internal enum stays `.keyboardShortcuts` | SATISFIED | Three "Hold to Transcribe" matches in SetupWindowView (label, enable, fix). One match in PermissionChecklistView (guide title). Zero user-facing "Keyboard Shortcuts" matches in either file. Internal enum `.keyboardShortcuts` intact throughout Readiness layer. |
| P22-STARTUP | 22-01-PLAN, 22-02-PLAN | Accessibility auto-prompt at startup, gated to fire only after IM is granted, fire-once | SATISFIED | AppDelegate lines 36-41: `CGPreflightListenEventAccess()` gate, `recordPostEventPermissionPrompt()` guard, synchronous `requestAccess()` + `refresh()`. |

**Note:** P22-RENAME and P22-STARTUP are phase-local requirements. No HTT-* requirements from REQUIREMENTS.md are mapped to Phase 22. No orphaned requirements.

### Commit Verification

| Commit | Description | Verified |
|--------|-------------|---------|
| `fb43fc5` | feat(22-02): revert user-facing labels to Hold to Transcribe, match container style | VERIFIED — exists, touched `SetupWindowView.swift` and `PermissionChecklistView.swift` |
| `a20864d` | feat(22-02): replace delay-based Accessibility prompt with IM-gated approach | VERIFIED — exists, touched `AppDelegate.swift` |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | No TODO, FIXME, placeholder, stub, or empty implementation patterns found in any Phase 22-02 modified file. |

### Human Verification Required

### 1. Setup Window Label Rendering

**Test:** Open the app's Setup window and look at the Input Monitoring permission row in the keyboard shortcuts form section.
**Expected:** Row label reads "Hold to Transcribe:", not "Keyboard Shortcuts:". If Input Monitoring is not determined, the action button reads "Enable Hold to Transcribe". If denied, it reads "Fix Hold to Transcribe".
**Why human:** Visual verification of rendered SwiftUI form labels — source confirms the string values but not the final render.

### 2. Setup Guide Popover Title

**Test:** Click the "Enable Hold to Transcribe" or "Fix Hold to Transcribe" button in the setup form to open the popover.
**Expected:** Popover title reads "How to enable Hold to Transcribe", not "How to enable Keyboard Shortcuts".
**Why human:** Visual verification of popover content.

### 3. IM-Gated Accessibility Prompt on Relaunch

**Test:** On a fresh install (or after clearing `hasRequestedPostEventPermission` from UserDefaults), launch the app. Grant Input Monitoring when the IM dialog appears, then relaunch.
**Expected:** On relaunch after IM grant, the Accessibility permission dialog appears immediately (no delay). On all subsequent relaunches, no Accessibility dialog appears.
**Why human:** Requires real macOS permission dialogs and a quit-relaunch cycle — not simulatable programmatically.

### Gaps Summary

No gaps. All 7 observable truths are verified against the actual codebase at commit `a20864d`. The Phase 22-02 gap closure plan was executed completely:

- All user-facing "Keyboard Shortcuts" labels in `SetupWindowView.swift` and `PermissionChecklistView.swift` have been reverted to "Hold to Transcribe". Zero stale "Keyboard Shortcuts" user-facing strings remain.
- `KeyboardShortcutsRow` is now a direct Form child (matching `KeyboardShortcuts.Recorder` rows). Its `LabeledContent("Hold to Transcribe:")` label lives inside the view body — not as an external wrapper in the Form.
- `AppDelegate.swift` no longer uses `DispatchQueue.main.asyncAfter`. The Accessibility prompt is gated by `CGPreflightListenEventAccess()` and fires synchronously, ensuring it only runs when IM is already granted. The fire-once guard is preserved.

The previous VERIFICATION.md (status: passed, verified at 2026-03-24T20:10:00Z) was accurate for Phase 22-01 but was rendered stale by UAT findings and the subsequent 22-02 gap closure commits. This report reflects the final state of the phase.

---

_Verified: 2026-03-24T22:15:00Z_
_Verifier: Claude (gsd-verifier)_
