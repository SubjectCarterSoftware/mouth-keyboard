---
phase: 2
slug: activation-and-capture
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (no config file — standard Xcode test target) |
| **Config file** | None — Xcode test scheme |
| **Quick run command** | `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' -testPlan Speech2Test 2>&1 \| tail -20` |
| **Full suite command** | `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' 2>&1 \| tail -30` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run affected test class only (e.g., `ActivationStoreTests`, `ShellPreferencesTests`)
- **After every plan wave:** Run `xcodebuild test -scheme Speech2Test -destination 'platform=macOS'`
- **Before `$gsd-verify-work`:** Full suite must be green + manual smoke (hotkey fires, pill appears, mic records)
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | ACTV-01 | unit | `xcodebuild test ... -only-testing:Speech2TestTests/HotkeyServiceTests` | ❌ W0 | ⬜ pending |
| 2-01-02 | 01 | 1 | ACTV-02 | unit | `xcodebuild test ... -only-testing:Speech2TestTests/ActivationStoreTests` | ❌ W0 | ⬜ pending |
| 2-01-03 | 01 | 1 | ACTV-03 | unit | `xcodebuild test ... -only-testing:Speech2TestTests/ActivationStoreTests` | ❌ W0 | ⬜ pending |
| 2-01-04 | 01 | 1 | CONF-03 | unit | `xcodebuild test ... -only-testing:Speech2TestTests/ShellPreferencesPhase2Tests` | ❌ W0 | ⬜ pending |
| 2-02-01 | 02 | 2 | AUDI-01 | manual | manual smoke — mic records with no audio interruption | manual-only | ⬜ pending |
| 2-02-02 | 02 | 2 | AUDI-02 | unit | `xcodebuild test ... -only-testing:Speech2TestTests/AudioDeviceServiceTests` | ❌ W0 | ⬜ pending |
| 2-02-03 | 02 | 2 | AUDI-03 | unit | `xcodebuild test ... -only-testing:Speech2TestTests/AudioCaptureServiceTests` | ❌ W0 | ⬜ pending |
| 2-03-01 | 03 | 3 | ACTV-04 | unit | `xcodebuild test ... -only-testing:Speech2TestTests/ActivationStoreTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Speech2TestTests/ActivationStoreTests.swift` — stubs for ACTV-02, ACTV-03, ACTV-04
- [ ] `Speech2TestTests/HotkeyServiceTests.swift` — stubs for ACTV-01, double-tap timer logic (injectable clock)
- [ ] `Speech2TestTests/AudioDeviceServiceTests.swift` — stubs for AUDI-02 enumeration (mockable CoreAudio adapter)
- [ ] `Speech2TestTests/ShellPreferencesPhase2Tests.swift` — stubs for CONF-03, micDeviceUID, activationSoundEnabled persistence
- [ ] `Speech2TestTests/AudioCaptureServiceTests.swift` — stubs for AUDI-03 (engine graph inspection, no actual mic needed)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Microphone stream captures audio | AUDI-01 | Requires real hardware; cannot be exercised in headless CI without a physical mic | Activate recording, speak, verify audio buffers received (log output or waveform visible) |
| Named device selection applies to engine | AUDI-02 (selection) | Requires real CoreAudio devices to set properties on | Pick non-default mic in settings, activate, verify correct device is used |
| System audio playback uninterrupted | AUDI-03 | Real output device required | Play music, activate recording, confirm music continues |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
