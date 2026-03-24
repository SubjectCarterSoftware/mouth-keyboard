---
plan: 22-02
phase: 22-permission-startup-flow-and-hotkey-gating
status: complete
completed: 2026-03-24
commits:
  - fb43fc5
  - a20864d
---

## Summary

Closed two UAT gaps from Phase 22 execution: reverted user-facing labels from "Keyboard Shortcuts" back to "Hold to Transcribe" and replaced the broken 0.75s delay Accessibility auto-prompt with an IM-gated approach.

## What Was Built

### Task 1: Label revert + container style fix
- `SetupWindowView.swift` — `actionTitle` now returns "Enable Hold to Transcribe" / "Fix Hold to Transcribe"
- `SetupWindowView.swift` — `KeyboardShortcutsRow.body` now wraps HStack in `LabeledContent("Hold to Transcribe:")`, moving the label inside the view to match the `KeyboardShortcuts.Recorder` container pattern. Outer `LabeledContent { KeyboardShortcutsRow } label: { Text("Keyboard Shortcuts:") }` wrapper removed from the Form.
- `PermissionChecklistView.swift` — Guide title reads "How to enable Hold to Transcribe"
- Internal enum `.keyboardShortcuts` and all accessibility identifiers (`setupWindow.keyboardShortcuts.*`) unchanged

### Task 2: IM-gated Accessibility auto-prompt
- `AppDelegate.swift` — Removed `DispatchQueue.main.asyncAfter(deadline: .now() + 0.75)` block entirely
- Replaced with synchronous check: `if !preferences.hasRequestedPostEventPermission, CGPreflightListenEventAccess()`
- First launch: IM not yet granted → prompt skipped. After IM grant/relaunch: IM authorized → Accessibility prompt fires immediately.
- Fire-once guard (`hasRequestedPostEventPermission`) preserved; set before `requestAccess()` call

## Key Files

- `Speech2Text/Shell/SetupWindowView.swift` — labels reverted, container matched
- `Speech2Text/Shell/PermissionChecklistView.swift` — guide title reverted
- `Speech2Text/App/AppDelegate.swift` — IM-gated Accessibility prompt

## Self-Check: PASSED

- Build succeeds with zero errors
- `grep "Hold to Transcribe" SetupWindowView.swift` — 3 matches (LabeledContent label, enable button, fix button)
- `grep '"Keyboard Shortcuts' SetupWindowView.swift` — 0 matches (no user-facing labels remain)
- `grep "How to enable Hold to Transcribe" PermissionChecklistView.swift` — 1 match
- `grep "CGPreflightListenEventAccess" AppDelegate.swift` — 1 match
- `grep "asyncAfter.*0.75" AppDelegate.swift` — 0 matches
