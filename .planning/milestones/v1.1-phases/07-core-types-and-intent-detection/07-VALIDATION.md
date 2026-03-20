---
phase: 7
slug: core-types-and-intent-detection
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-19
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode 16, bundled) |
| **Config file** | Speech2Text.xcscheme — `Speech2TextTests` target already configured |
| **Quick run command** | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/IntentDetectorTests` |
| **Full suite command** | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/IntentDetectorTests`
- **After every plan wave:** Run `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 1 | MODE-01–06 | filesystem gate | `test -f Speech2Text/Conversion/ConvertMode.swift && test -f Speech2Text/Conversion/ConvertIntent.swift && test -f Speech2Text/Conversion/IntentDetector.swift && rg -n "enum ConvertMode\|struct ConvertIntent\|static func detect" Speech2Text/Conversion` | created in task | ⬜ pending |
| 7-01-02 | 01 | 1 | MODE-01–06, INTENT-01, INTENT-02, INTENT-03 | build + RED test | `xcodebuild build -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' && ! xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/IntentDetectorTests >/tmp/phase07-red.log 2>&1 && rg -n "Test Suite 'IntentDetectorTests' failed\|[1-9][0-9]* test[s]? failed" /tmp/phase07-red.log` | created in task | ⬜ pending |
| 7-02-01 | 02 | 2 | INTENT-01, INTENT-02, INTENT-03 | unit | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/IntentDetectorTests` | existing | ⬜ pending |
| 7-02-02 | 02 | 2 | regression gate | full suite | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` | existing | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

None. Phase 7 creates and verifies its source, test, and project-file artifacts within plan tasks, so no separate Wave 0 bootstrap is required.

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
