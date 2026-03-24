---
status: complete
phase: 20-permission-model-and-ui-wiring
source: [20-01-SUMMARY.md, 20-02-SUMMARY.md]
started: 2026-03-24T19:02:49Z
updated: 2026-03-24T19:17:51Z
---

## Current Test

[testing complete]

## Tests

### 1. Permission Checklist Tile Order
expected: In the setup/settings window, the permission checklist bar shows three tiles in order from left to right: Microphone → Input Monitoring → Auto Paste.
result: pass

### 2. Hold to Transcribe Row Shows Input Monitoring Status
expected: The Hold to Transcribe row in Settings reflects Input Monitoring permission status — not Accessibility. If Input Monitoring is not yet granted, the status text reads "Needs keyboard access." with an "Enable Hold to Transcribe" button.
result: pass

### 3. Enable Prompts for Input Monitoring
expected: Clicking "Enable Hold to Transcribe" triggers the macOS Input Monitoring permission prompt (CGRequestListenEventAccess) — not the Accessibility permission prompt.
result: pass

### 4. Recovery Shows Setup Guide Popover
expected: When Input Monitoring is denied, the Hold to Transcribe row shows "Keyboard access is blocked." with a "Fix Hold to Transcribe" button. Clicking it opens a setup guide popover (not navigating directly to System Settings).
result: pass

### 5. Setup Guide Content
expected: The setup guide popover has the headline "How to enable Hold to Transcribe" and steps that reference the Input Monitoring pane specifically. The button reads "Open Settings & Quit App" and the guide frame is ~270px wide, matching the Accessibility guide style.
result: pass

### 6. No Accessibility References in Hold to Transcribe UI
expected: All labels, detail text, action buttons, and setup guide popover for Hold to Transcribe reference "Input Monitoring" or "keyboard access" — zero remaining "Accessibility" references in hold-related UI.
result: pass

### 7. Auto Paste Row References Only Auto Paste
expected: The Auto Paste / Accessibility row messages do NOT mention "Hold to Transcribe". The .postEvent permission messages reference only Auto Paste functionality.
result: pass

## Summary

total: 7
passed: 7
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
