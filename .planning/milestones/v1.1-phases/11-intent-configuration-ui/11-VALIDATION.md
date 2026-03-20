---
phase: 11
slug: intent-configuration-ui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift) |
| **Config file** | Speech2Text.xcodeproj |
| **Quick run command** | `xcodebuild test -scheme Speech2Text -destination 'platform=macOS' -only-testing:Speech2TextTests 2>&1 \| grep -E "passed\|failed\|error:"` |
| **Full suite command** | `xcodebuild test -scheme Speech2Text -destination 'platform=macOS' -only-testing:Speech2TextTests 2>&1 \| tail -5` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | CONFIG-01 | unit | quick run | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 1 | CONFIG-01 | unit | quick run | ❌ W0 | ⬜ pending |
| 11-02-01 | 02 | 2 | CONFIG-02 | unit | quick run | ❌ W0 | ⬜ pending |
| 11-02-02 | 02 | 2 | CONFIG-03 | unit | quick run | ❌ W0 | ⬜ pending |
| 11-03-01 | 03 | 3 | CONFIG-02 | manual | n/a | n/a | ⬜ pending |
| 11-03-02 | 03 | 3 | CONFIG-03 | manual | n/a | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Speech2TextTests/UserIntentStoreTests.swift` — stubs for CONFIG-01 (persistence round-trip, default fallback)
- [ ] `Speech2TextTests/IntentCatalogDynamicTests.swift` — stubs for CONFIG-02 (custom intents visible to detector)

*Existing XCTest infrastructure covers the framework; Wave 0 adds new test files only.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Mode name ghost text appears while typing system prompt | CONFIG-03 | Requires live SwiftUI interaction | Open Add Mode sheet, type system prompt, verify ghost text appears in name field after ~1s |
| Live preview updates after system prompt change | CONFIG-03 | Requires LLM inference in settings context | Edit system prompt, wait ~2s, verify output panel updates |
| 50 phrase patterns generated silently in background | CONFIG-02 | Background generation — no UI indicator | Create custom mode, save, use Debug menu or log to confirm patterns exist in UserIntentStore |
| Phrase trigger tester returns correct result | CONFIG-01 | Requires live fuzzy matching in UI context | Expand disclosure, type a natural phrase, verify triggered/not triggered matches expected |
| Reset to default restores hardcoded values | CONFIG-01 | Requires UserDefaults/JSON deletion verification | Edit built-in mode prompt, tap Reset, verify prompt reverts to ConvertMode.defaultSystemPrompt |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
