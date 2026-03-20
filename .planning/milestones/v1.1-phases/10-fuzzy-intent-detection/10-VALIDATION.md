---
phase: 10
slug: fuzzy-intent-detection
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Config file** | Speech2Text.xcodeproj |
| **Quick run command** | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/IntentDetectorTests` |
| **Full suite command** | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command (IntentDetectorTests + StringSimilarityTests)
- **After every plan wave:** Run full suite command
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| TBD | 01 | 1 | INTENT-01 | unit | quick run | TBD | pending |
| TBD | 01 | 1 | INTENT-02 | unit | quick run | TBD | pending |
| TBD | 01 | 1 | INTENT-03 | unit | quick run | TBD | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

- [ ] `Speech2TextTests/StringSimilarityTests.swift` — stubs for Jaro-Winkler reference pairs
- `IntentDetectorTests.swift` exists — rewritten in-place, not a new file

*Existing XCTest infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Natural speech variation with real Whisper output | All | Whisper output variation can only be validated with real recordings | Record 5-10 test dictations with natural phrasing, verify detection |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
