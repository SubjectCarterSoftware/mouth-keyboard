---
phase: 4
slug: recovery-controls
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-07
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (bundled with Xcode) |
| **Config file** | `Speech2Test.xcodeproj` |
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
| 04-01-01 | 01 | 1 | SESS-02 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | existing (expand) | pending |
| 04-01-02 | 01 | 1 | SESS-02 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/SpacebarInterceptorTests -destination 'platform=macOS'` | existing (generalize) | pending |
| 04-01-03 | 01 | 1 | SESS-03 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | existing (expand) | pending |
| 04-01-04 | 01 | 1 | SESS-04 | ui-smoke | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestUITests/MenuBarShellSmokeTests -destination 'platform=macOS'` | existing (expand) | pending |
| 04-02-01 | 02 | 2 | AUDI-04 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/AudioCaptureServiceTests -destination 'platform=macOS'` | existing (expand) | pending |
| 04-02-02 | 02 | 2 | CLIP-02 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | existing (expand) | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

- [ ] Expand `Speech2TestTests/ActivationStoreTests.swift` for cancel-during-processing, restart buffer reset, explicit recovery feedback, and stale async result suppression.
- [ ] Expand `Speech2TestTests/AudioCaptureServiceTests.swift` for typed start failures, selected-device disconnect handling, and removal of silent fallback behavior.
- [ ] Generalize `Speech2TestTests/SpacebarInterceptorTests.swift` into a session-key interceptor test if literal `Escape` cancel uses the same interception pattern.
- [ ] Expand `Speech2TestUITests/MenuBarShellSmokeTests.swift` for cancel/restart confirmation visibility and the indicator-hidden menu fallback.
- [ ] Add accessibility identifiers for any new recovery actions in the menu or pill before depending on UI automation for SESS-04.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `Escape` cancels while another app remains frontmost | SESS-02 | Requires live background keyboard interception and real app focus behavior | 1. Start recording from another app 2. Press `Escape` 3. Verify capture stops, clipboard stays unchanged, and focus does not shift |
| Restart keeps recording active from a clean point with clear confirmation | SESS-03, SESS-04 | Requires observing live pill or menu confirmation while speaking | 1. Start recording 2. Trigger restart affordance 3. Continue speaking 4. Verify old audio is discarded and confirmation appears without dropping out of recording |
| Selected microphone disconnect or unavailability is surfaced clearly | AUDI-04 | Requires real hardware/device-state changes or OS-level permission changes | 1. Choose a non-default microphone 2. Start recording 3. Disconnect or revoke access 4. Verify the session fails visibly and does not silently switch devices |
| Recovery and no-output paths never replace the clipboard | CLIP-02 | Clipboard preservation is easiest to verify end-to-end with known preloaded content | 1. Copy known text 2. Trigger cancel, restart, mic failure, and no-speech cases 3. Verify the clipboard content remains unchanged |

*If none: "All phase behaviors have automated verification."*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
