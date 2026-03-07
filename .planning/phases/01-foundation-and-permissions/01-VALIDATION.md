---
phase: 1
slug: foundation-and-permissions
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-05
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest + XCUITest |
| **Config file** | none — Wave 0 installs native app + test targets |
| **Quick run command** | `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' -only-testing:Speech2TestTests/ReadinessStateTests -only-testing:Speech2TestTests/PermissionServiceTests` |
| **Full suite command** | `xcodebuild test -scheme Speech2Test -destination 'platform=macOS'` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' -only-testing:Speech2TestTests/ReadinessStateTests -only-testing:Speech2TestTests/PermissionServiceTests`
- **After every plan wave:** Run `xcodebuild test -scheme Speech2Test -destination 'platform=macOS'`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | FEED-02 | build + smoke | `xcodebuild build -scheme Speech2Test -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | FEED-02 | UI | `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' -only-testing:Speech2TestUITests/MenuBarShellSmokeTests` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | CONF-01 | unit | `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' -only-testing:Speech2TestTests/PermissionServiceTests` | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 2 | CONF-02 | unit + UI | `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' -only-testing:Speech2TestTests/ReadinessStateTests -only-testing:Speech2TestUITests/PermissionRecoveryFlowTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Speech2Test.xcodeproj` or equivalent native app target scaffold — required before any build/test command works
- [ ] `Speech2TestTests/ReadinessStateTests.swift` — unit coverage for ready / needs-setup / blocked derivation
- [ ] `Speech2TestTests/PermissionServiceTests.swift` — unit coverage for permission status mapping and recovery-state decisions
- [ ] `Speech2TestUITests/MenuBarShellSmokeTests.swift` — shell launch and menu/surface smoke coverage
- [ ] `Speech2TestUITests/PermissionRecoveryFlowTests.swift` — first-launch checklist and blocked-state UX smoke coverage

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App stays menu-bar-first with no normal Dock presence during steady state | FEED-02 | UI shell/lifecycle behavior is difficult to prove reliably with unit tests alone | Launch app outside Xcode, verify menu bar presence, verify no persistent Dock app in steady state |
| First-launch setup appears once, then yields to a quiet utility shell | CONF-01 | Requires end-to-end shell behavior across launches | Start from fresh preferences, launch app, verify setup window appears once and subsequent launches stay menu-bar-first |
| Blocked state offers visible recovery path into System Settings | CONF-02 | Depends on live macOS permission surfaces | Deny the relevant permission, open menu, verify blocked status card and `Fix setup` action route the user correctly |

*If none: "All phase behaviors have automated verification."*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-03-05
