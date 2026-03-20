---
phase: 9
slug: activationstore-integration-and-guards
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (native) |
| **Config file** | Speech2Text.xcodeproj (Xcode scheme) |
| **Quick run command** | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/ActivationStoreTests -destination "platform=macOS" 2>&1 \| tail -20` |
| **Full suite command** | `xcodebuild test -scheme Speech2Text -destination "platform=macOS" 2>&1 \| tail -40` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command (ActivationStoreTests only)
- **After every plan wave:** Run full suite command
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-W0 | 01 | 0 | LLM-02, UX-01 | unit | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/ActivationStoreTests -destination "platform=macOS" 2>&1 \| tail -20` | ❌ W0 | ⬜ pending |
| 09-xx-LLM02 | TBD | 1+ | LLM-02 | unit | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/ActivationStoreTests/test_passthrough_dictation_is_completely_unchanged -destination "platform=macOS" 2>&1 \| tail -20` | ❌ W0 | ⬜ pending |
| 09-xx-UX01 | TBD | 1+ | UX-01 | unit | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/ActivationStoreTests/test_trigger_dictation_produces_converted_clipboard_output -destination "platform=macOS" 2>&1 \| tail -20` | ❌ W0 | ⬜ pending |
| 09-xx-GUARD01 | TBD | 1+ | GUARD-01 | manual | N/A | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Speech2TextTests/ActivationStoreTests.swift` — add `MockLLMRewriter` stub alongside existing mock types
- [ ] `Speech2TextTests/ActivationStoreTests.swift` — add `test_trigger_dictation_produces_converted_clipboard_output` test method (LLM-02, UX-01 happy path)
- [ ] `Speech2TextTests/ActivationStoreTests.swift` — add `test_passthrough_dictation_is_completely_unchanged` test method (LLM-02)
- [ ] `Speech2TextTests/ActivationStoreTests.swift` — update all existing `.success(text:pasted:)` patterns to include `converted:` label (compile gate — catches all missed switch sites)

*Note: Test file already exists; Wave 0 adds new test methods and updates existing patterns.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 350-word gate fires before LLM call with orange pill alert | GUARD-01 | Per CONTEXT.md decision: guard/failure paths verified manually, not in unit tests | Dictate a trigger phrase followed by 351+ words; verify pill flashes orange with "Input exceeds AI limit" and raw transcript lands in clipboard |
| LLM failure silent fallback | GUARD-01 | Per CONTEXT.md decision | Force LLM failure (disconnect network or mock); verify raw transcript silently copies with no error visible |
| `.converting` pill animation is visually distinct from `.processing` | UX-01 | Visual distinction cannot be automated | Run app, trigger a conversion, observe pill animation differs from Whisper processing animation |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
