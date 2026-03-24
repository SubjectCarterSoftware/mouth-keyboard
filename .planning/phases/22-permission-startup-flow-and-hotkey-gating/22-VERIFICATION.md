---
phase: 22-permission-startup-flow-and-hotkey-gating
verified: 2026-03-24T20:10:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
---

# Phase 22: Permission Startup Flow and Hotkey Gating — Verification Report

**Phase Goal:** Auto-prompt Accessibility permission at startup (like Input Monitoring already does), and rename `.holdToTranscribe` → `.keyboardShortcuts` so the UI accurately reflects that Input Monitoring gates all keyboard shortcuts (Control+V, Control+B, Hold-to-Transcribe).
**Verified:** 2026-03-24T20:10:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | PermissionKind enum has .keyboardShortcuts case, no .holdToTranscribe case | ✓ VERIFIED | `ReadinessSnapshot.swift` line 27: `case keyboardShortcuts`. `grep -rn holdToTranscribe Speech2Text/Readiness/ Speech2Text/Shell/` returns zero matches. |
| 2 | Setup window Keyboard Shortcuts row shows 'Keyboard Shortcuts:' label, not 'Hold to Transcribe:' | ✓ VERIFIED | `SetupWindowView.swift` line 635: `Text("Keyboard Shortcuts:")`. Struct renamed to `KeyboardShortcutsRow` (line 142). No `HoldToTranscribeRow` or `"Hold to Transcribe:"` references remain. |
| 3 | Status messages read 'Ready — shortcuts enabled.' / 'Needs keyboard access.' / 'Keyboard access is blocked.' | ✓ VERIFIED | `ReadinessSnapshot.swift` lines 74-78: all three messages match exactly. `SetupWindowView.swift` line 164 also returns `"Ready — shortcuts enabled."`. |
| 4 | InputMonitoringSetupGuide title reads 'How to enable Keyboard Shortcuts' | ✓ VERIFIED | `PermissionChecklistView.swift` line 156: `Text("How to enable Keyboard Shortcuts")`. |
| 5 | Accessibility permission auto-prompts once at startup after a 0.75s delay | ✓ VERIFIED | `AppDelegate.swift` lines 34-41: `DispatchQueue.main.asyncAfter(deadline: .now() + 0.75)` containing `self.postEventService.requestAccess()`. Placed after `hotkeyService.start()` and `readinessStore.refresh()`, before `WhisperService.deleteLegacyUnsupportedModelFiles()`. |
| 6 | Auto-prompt is guarded by hasRequestedPostEventPermission flag — fires only on first install | ✓ VERIFIED | `AppDelegate.swift` line 34: `if !preferences.hasRequestedPostEventPermission {` guards the block. Line 35: `preferences.recordPostEventPermissionPrompt()` sets the flag BEFORE the delayed block (crash-safe). |
| 7 | readinessStore.refresh() is called after the delayed auto-prompt completes | ✓ VERIFIED | `AppDelegate.swift` line 39: `self.readinessStore.refresh()` inside the `asyncAfter` closure, after `self.postEventService.requestAccess()`. |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Speech2Text/Readiness/ReadinessSnapshot.swift` | `.keyboardShortcuts` enum case with updated title, messages | ✓ VERIFIED | Contains `case keyboardShortcuts`, title `"Keyboard Shortcuts"`, all three status messages correct. 6 switch cases reference `.keyboardShortcuts`. |
| `Speech2Text/Readiness/ReadinessStore.swift` | Updated switch case for `.keyboardShortcuts` | ✓ VERIFIED | Line 77: `case .keyboardShortcuts:` in `requestPermission(for:)`. |
| `Speech2Text/Shell/SetupWindowView.swift` | `KeyboardShortcutsRow` struct, updated accessibility IDs | ✓ VERIFIED | Struct `KeyboardShortcutsRow` (line 142), 4 accessibility IDs use `setupWindow.keyboardShortcuts.*`, button labels `"Enable Keyboard Shortcuts"` / `"Fix Keyboard Shortcuts"`, status message `"Ready — shortcuts enabled."`. |
| `Speech2Text/Shell/PermissionChecklistView.swift` | Updated tile routing and guide title | ✓ VERIFIED | Line 70: `item.kind == .keyboardShortcuts` (tile routing). Line 84: `item.kind == .keyboardShortcuts` (guide selection). Line 156: `"How to enable Keyboard Shortcuts"` (guide title). |
| `Speech2Text/App/AppDelegate.swift` | Delayed Accessibility auto-prompt at startup | ✓ VERIFIED | Line 13: `private let postEventService = PostEventPermissionService.live`. Lines 34-41: guarded delayed auto-prompt block with `[weak self]` capture, 0.75s delay, `requestAccess()` call, and `refresh()` call. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ReadinessSnapshot.swift` | All switch statements | CaseIterable exhaustive matching | ✓ WIRED | `case .keyboardShortcuts` found in 4 switch arms in ReadinessSnapshot (title, systemImage, settingsURL, message) + 1 in ReadinessStore (requestPermission). Compiler enforces exhaustiveness via `CaseIterable`. |
| `AppDelegate.swift` | PostEventPermissionService | `DispatchQueue.main.asyncAfter` delayed call | ✓ WIRED | Line 13: `postEventService` property initialized. Line 38: `self.postEventService.requestAccess()` called inside `asyncAfter` block. Response is fire-and-forget (by design — `@discardableResult`). |
| `AppDelegate.swift` | ShellPreferences | `hasRequestedPostEventPermission` guard | ✓ WIRED | Line 34: guard reads `preferences.hasRequestedPostEventPermission`. Line 35: `preferences.recordPostEventPermissionPrompt()` sets the flag. `preferences` property exists at line 10. |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| P22-RENAME | 22-01-PLAN | Rename `.holdToTranscribe` → `.keyboardShortcuts` throughout | ✓ SATISFIED | Zero `holdToTranscribe` references remain in `Readiness/` and `Shell/`. All user-facing strings updated. |
| P22-STARTUP | 22-01-PLAN | Auto-prompt Accessibility at startup with delay | ✓ SATISFIED | AppDelegate lines 34-41: guarded, delayed auto-prompt with refresh. |

**Note:** P22-RENAME and P22-STARTUP are phase-local requirements defined in the ROADMAP.md for Phase 22. They do not appear in the v1.4 HTT-* requirements in REQUIREMENTS.md. No HTT-* requirements are mapped to Phase 22 in the traceability table, so there are no orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | No TODO, FIXME, placeholder, stub, or empty implementation patterns found in any modified file. |

### Human Verification Required

### 1. Accessibility Permission Dialog Appears on First Launch

**Test:** Delete the app's preferences (`defaults delete` the app domain) and launch the app fresh. Wait ~1 second after the Input Monitoring dialog appears.
**Expected:** An Accessibility permission dialog should appear approximately 0.75 seconds after the Input Monitoring dialog. On subsequent launches, no Accessibility dialog should appear.
**Why human:** Requires real macOS permission dialogs — cannot be triggered programmatically in a test environment.

### 2. Setup Window Shows "Keyboard Shortcuts:" Label

**Test:** Open the Setup window and look at the Input Monitoring permission row.
**Expected:** Row label reads "Keyboard Shortcuts:", not "Hold to Transcribe:". Button reads "Enable Keyboard Shortcuts" (if not determined) or "Fix Keyboard Shortcuts" (if denied).
**Why human:** Visual verification of rendered UI text.

### 3. Setup Guide Popover Shows Updated Title

**Test:** Click the "Enable Keyboard Shortcuts" or "Fix Keyboard Shortcuts" button on the Keyboard Shortcuts tile.
**Expected:** Popover title reads "How to enable Keyboard Shortcuts", not "How to enable Hold to Transcribe".
**Why human:** Visual verification of popover content.

### Gaps Summary

No gaps found. All 7 observable truths verified against actual codebase. All 5 artifacts exist, are substantive, and are wired. All 3 key links are connected. Both commits (5478679, 52bb8f4) exist in the git history. No anti-patterns detected. Zero stale `holdToTranscribe` references remain in the `Readiness/` or `Shell/` directories.

---

_Verified: 2026-03-24T20:10:00Z_
_Verifier: Claude (gsd-verifier)_
