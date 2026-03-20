---
phase: 8
slug: llm-rewrite-service
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-19
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode 16, bundled) |
| **Config file** | Speech2Text.xcscheme — `Speech2TextTests` target already configured |
| **Quick run command** | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/LLMRewriteServiceTests` |
| **Full suite command** | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/LLMRewriteServiceTests`
- **After every plan wave:** Run `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'`
- **Before `$gsd-verify-work`:** Full suite must be green, with any real-model smoke verification explicitly recorded
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 8-01-01 | 01 | 1 | GUARD-02 | filesystem gate | `test -f Speech2Text/Conversion/LLMRewriteService.swift && rg -n "enum LLMRewriteError|protocol LLMRewriting|actor LLMRewriteService|ChatSession|streamDetails|HubApi|loadTask" Speech2Text/Conversion/LLMRewriteService.swift && rg -n "LLMRewriteService" Speech2Text.xcodeproj/project.pbxproj` | created in task | ⬜ pending |
| 8-01-02 | 01 | 1 | GUARD-02 | unit + serialization | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/LLMRewriteServiceTests && xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` | created in task | ⬜ pending |
| 8-02-01 | 02 | 2 | GUARD-02 | integration | `ENABLE_LLM_INTEGRATION_TESTS=1 xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/LLMRewriteServiceIntegrationTests` | created in task | ⬜ pending |
| 8-02-02 | 02 | 2 | performance gate | full suite | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` | existing | ⬜ pending |
| 8-02-03 | 02 | 2 | success criteria 3-4 | human checkpoint | `Manual Time Profiler + cache-reuse check recorded in plan checkpoint` | existing process | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

None. Phase 8 can add its service and test artifacts directly within plan tasks using the existing XCTest infrastructure.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Main thread remains effectively idle during model load and rewrite generation | GUARD-02 phase performance criterion | Requires Instruments / runtime observation, not a stable unit assertion | Start a real rewrite with the model available, profile with Time Profiler, and confirm model load/inference work is off `@MainActor` with near-zero main-thread CPU |
| First rewrite downloads or loads the model once, second rewrite reuses it without a repeat download | Phase 8 success criterion 4 | Depends on local cache state and runtime I/O rather than a deterministic fast test | Clear the rewrite-model cache, perform one rewrite and observe load/download, then perform a second rewrite and confirm there is no second download or cold-load path |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
