---
status: diagnosed
phase: 22-permission-startup-flow-and-hotkey-gating
source: [22-01-SUMMARY.md]
started: 2026-03-24T20:13:38Z
updated: 2026-03-24T20:23:50Z
---

## Current Test

[testing complete]

## Tests

### 1. Keyboard Shortcuts Row Title
expected: Open the app. The Setup window's permission checklist shows "Keyboard Shortcuts" as the Input Monitoring row title — not "Hold to Transcribe".
result: issue
reported: "The label is keyboard shortcuts, that's stupid. The label is supposed to be Hold to Transcribe. And the UI container for that button is different from what we use for the start/stop and auto paste and stop only buttons — should use the same container."
severity: major

### 2. Keyboard Shortcuts Status Messages
expected: The Keyboard Shortcuts row shows the correct status message based on Input Monitoring permission state: "Ready — shortcuts enabled." when granted, "Needs keyboard access." when not yet prompted, or "Keyboard access is blocked." when denied.
result: pass

### 3. Accessibility Auto-Prompt at Startup
expected: On first launch after a fresh install (or after resetting preferences), a macOS Accessibility permission dialog appears shortly (~0.75s) after the Input Monitoring permission dialog. Both dialogs appear without user action — the app triggers them automatically.
result: issue
reported: "The input monitoring prompt works but the accessibility one does not pop at all at start. Should change it so that once input monitoring is granted, then directly request the accessibility prompt. Don't use a short delay — completely wait until input monitoring is granted, then request accessibility on next launch. User grants input monitoring, macOS quits and reopens the app, then the accessibility prompt appears on that relaunch."
severity: major

### 4. Fire-Once Prompt Behavior
expected: After the Accessibility prompt has been shown once (whether granted or denied), subsequent app launches do NOT show the Accessibility dialog again. Only the first launch triggers it.
result: blocked
blocked_by: prior-phase
reason: "Can't test — accessibility prompt never fires at all (Test 3 issue), so fire-once behavior is moot"

### 5. Setup Window Reflects Updated Permissions
expected: After both permission prompts complete (granted or denied), the Setup window tiles update to reflect the current Accessibility and Input Monitoring permission status without requiring a manual refresh or app restart.
result: pass

## Summary

total: 5
passed: 2
issues: 2
pending: 0
skipped: 0
blocked: 1

## Gaps

- truth: "Setup window shows 'Keyboard Shortcuts' as the Input Monitoring row title"
  status: failed
  reason: "User reported: Label should be 'Hold to Transcribe' not 'Keyboard Shortcuts'. Also the UI container for that button is different from the containers used for start/stop, auto paste, and stop only buttons — should use the same container style."
  severity: major
  test: 1
  root_cause: "Phase 22 renamed user-facing label to 'Keyboard Shortcuts' per D-07/D-08 but user wants 'Hold to Transcribe' kept. SetupWindowView line 635 has Text('Keyboard Shortcuts:'), PermissionChecklistView line 156 has 'How to enable Keyboard Shortcuts'. KeyboardShortcutsRow uses LabeledContent wrapper while Start/Stop/StopOnly buttons don't — container mismatch."
  artifacts:
    - path: "Speech2Text/Shell/SetupWindowView.swift"
      issue: "Line 635 label says 'Keyboard Shortcuts:', KeyboardShortcutsRow wrapped in LabeledContent unlike other shortcut rows"
    - path: "Speech2Text/Shell/PermissionChecklistView.swift"
      issue: "Line 156 guide header says 'How to enable Keyboard Shortcuts'"
  missing:
    - "Revert label to 'Hold to Transcribe:' on line 635"
    - "Revert guide title to 'How to enable Hold to Transcribe' on line 156"
    - "Remove LabeledContent wrapper or match container style to Start/Stop/StopOnly rows"
  debug_session: ""

- truth: "Accessibility permission dialog appears shortly after Input Monitoring dialog on first launch"
  status: failed
  reason: "User reported: Accessibility prompt does not pop at all at start. Should wait until Input Monitoring is granted (macOS quits/reopens app after granting), then request Accessibility on that relaunch — not use a timed delay."
  severity: major
  test: 3
  root_cause: "AppDelegate lines 34-41 use DispatchQueue.main.asyncAfter 0.75s delay which fires before IM is granted. CGRequestPostEventAccess() likely fails silently when called too early. Fix: check CGPreflightListenEventAccess() — if IM already authorized, request Accessibility immediately (no delay). If IM not granted, skip — will fire on next launch after IM grant-quit-relaunch cycle."
  artifacts:
    - path: "Speech2Text/App/AppDelegate.swift"
      issue: "Lines 34-41: delayed auto-prompt fires regardless of IM status, Accessibility prompt never appears"
  missing:
    - "Replace delay-based approach with conditional check on Input Monitoring status"
    - "Use KeyboardPermissionService.live.currentStatus() to gate Accessibility request"
    - "Remove DispatchQueue.main.asyncAfter — no delay needed when IM is already granted"
  debug_session: ""
