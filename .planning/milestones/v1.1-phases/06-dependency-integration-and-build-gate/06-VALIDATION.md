---
phase: 6
slug: dependency-integration-and-build-gate
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode-native) |
| **Config file** | Speech2Text.xcodeproj (no separate config file) |
| **Quick run command** | `xcodebuild -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' build` |
| **Full suite command** | `xcodebuild -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' test` |
| **Estimated runtime** | ~60 seconds (build) / ~90 seconds (test) |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' build`
- **After every plan wave:** Run full suite (`xcodebuild ... test`)
- **Before `$gsd-verify-work`:** Full suite must be green + manual smoke test complete
- **Max feedback latency:** ~90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | LLM-01 | build gate | `xcodebuild ... build` | ❌ W0 (build.sh) | ⬜ pending |
| 06-01-02 | 01 | 1 | LLM-01 | build gate | `xcodebuild -resolvePackageDependencies` | Manual step | ⬜ pending |
| 06-01-03 | 01 | 1 | LLM-01 | build gate | `xcodebuild ... build` | ❌ W0 (build.sh) | ⬜ pending |
| 06-01-04 | 01 | 1 | LLM-02 | manual-only | N/A — manual smoke test | Manual only | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `build.sh` — creates xcodebuild wrapper script with Metal shader constraint comment and clean-resolution procedure (created in Wave 1)

*No test framework installation needed — XCTest is Xcode-native. No new test files added in Phase 6.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Plain dictation copies raw transcript to clipboard unchanged | LLM-02 | Requires running the app and triggering audio input | Launch app, dictate without trigger phrase, confirm clipboard content matches raw transcript |
| Recording starts immediately with no perceptible added latency | LLM-02 | Subjective latency check | Press hotkey to start recording; confirm microphone icon appears within ~200ms |
| Clean package resolution on fresh checkout | LLM-01 | Requires deleting Package.resolved and re-resolving | `rm Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && xcodebuild -project Speech2Text.xcodeproj -resolvePackageDependencies` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
