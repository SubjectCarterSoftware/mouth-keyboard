---
phase: 3
slug: recognition-and-clipboard-loop
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (bundled with Xcode) |
| **Config file** | Speech2Test.xcodeproj (Xcode-managed) |
| **Quick run command** | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -destination 'platform=macOS'` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests -destination 'platform=macOS'`
- **After every plan wave:** Run `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -destination 'platform=macOS'`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | TRNS-01 | unit | `xcodebuild test -only-testing Speech2TestTests/WhisperServiceTests` | W0 | pending |
| 03-01-02 | 01 | 1 | TRNS-02 | unit | `xcodebuild test -only-testing Speech2TestTests/WhisperServiceTests` | W0 | pending |
| 03-01-03 | 01 | 1 | TRNS-06 | unit | `xcodebuild test -only-testing Speech2TestTests/ActivationStoreTests` | existing (expand) | pending |
| 03-02-01 | 02 | 2 | SESS-01 | unit | `xcodebuild test -only-testing Speech2TestTests/ActivationStoreTests` | existing | pending |
| 03-02-02 | 02 | 2 | CLIP-01 | unit | `xcodebuild test -only-testing Speech2TestTests/ClipboardServiceTests` | W0 | pending |
| 03-03-01 | 03 | 2 | FEED-01 | unit | `xcodebuild test -only-testing Speech2TestTests/ActivationStoreTests` | existing (expand) | pending |
| 03-03-02 | 03 | 2 | FEED-03 | unit | `xcodebuild test -only-testing Speech2TestTests/ShellPreferencesPhase3Tests` | W0 | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

- [ ] `Speech2TestTests/WhisperServiceTests.swift` — stubs for TRNS-01, TRNS-02 (mock-based; real model tests require bundled model)
- [ ] `Speech2TestTests/ClipboardServiceTests.swift` — stubs for CLIP-01 (NSPasteboard write verification)
- [ ] `Speech2TestTests/ShellPreferencesPhase3Tests.swift` — stubs for FEED-03 (new preference keys)
- [ ] `Speech2TestTests/AudioBufferAccumulatorTests.swift` — buffer accumulation and format conversion logic
- [ ] Expand `Speech2TestTests/ActivationStoreTests.swift` — stubs for TRNS-06, FEED-01 (new state transitions: processing, success, failure)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Hotkey finish while remaining in the active app | SESS-01 | Requires a live foreground app and real hotkey interaction | 1. Start recording via hotkey 2. Press the same hotkey again 3. Verify recording stops and transcription begins without moving focus |
| Real whisper.cpp transcription with punctuation | TRNS-01, TRNS-02 | Requires ~466MB model file and Metal GPU | 1. Record spoken sentence with natural pauses 2. Verify transcription text includes periods/commas 3. Verify text is coherent |
| Clipboard write after successful transcription | CLIP-01 | Requires a live foreground app and manual paste confirmation | 1. Open TextEdit 2. Dictate via Speech2Test 3. Verify the text lands on the clipboard and manual paste inserts it |
| Pill pulsing animation during processing | FEED-01 | Visual animation verification | 1. Start and finish a recording 2. Verify pill shows pulsing animation during transcription |
| Menu bar icon reflects state when pill hidden | FEED-03 | Requires UI observation with preference toggled | 1. Toggle indicator visibility off 2. Start recording 3. Verify pill is hidden but menu bar icon changes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
