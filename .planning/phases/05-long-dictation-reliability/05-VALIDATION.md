---
phase: 5
slug: long-dictation-reliability
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-08
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Config file** | `Speech2Test.xcodeproj` |
| **Quick run command** | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -destination 'platform=macOS'` |
| **Estimated runtime** | ~20 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests -destination 'platform=macOS'`
- **After every plan wave:** Run `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -destination 'platform=macOS'`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 20 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | TRNS-03 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/AudioBufferAccumulatorTests -destination 'platform=macOS'` | existing (expand) | pending |
| 05-01-02 | 01 | 1 | TRNS-03 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | existing (expand) | pending |
| 05-01-03 | 01 | 1 | TRNS-03 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/LongDictationBoundaryTests -destination 'platform=macOS'` | new | pending |
| 05-02-01 | 02 | 2 | TRNS-04 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/TranscriptAssemblerTests -destination 'platform=macOS'` | new | pending |
| 05-02-02 | 02 | 2 | TRNS-05 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | existing (expand) | pending |
| 05-02-03 | 02 | 2 | TRNS-04, TRNS-05 | ui-smoke | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestUITests/MenuBarShellSmokeTests -destination 'platform=macOS'` | existing (expand) | pending |
| 05-03-01 | 03 | 3 | TRNS-03, TRNS-04, TRNS-05 | integration-ish unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/LongDictationFlowTests -destination 'platform=macOS'` | new | pending |
| 05-03-02 | 03 | 3 | TRNS-04 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/TranscriptAssemblerTests -destination 'platform=macOS'` | new | pending |
| 05-03-03 | 03 | 3 | TRNS-05 | ui-smoke | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestUITests/MenuBarShellSmokeTests -destination 'platform=macOS'` | existing (expand) | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

- [ ] Expand `Speech2TestTests/AudioBufferAccumulatorTests.swift` for segment sealing, live-buffer reset, and immutable queued-segment conversion.
- [ ] Expand `Speech2TestTests/ActivationStoreTests.swift` for long-session threshold activation, queued-segment settlement, best-effort final clipboard writes, and all-failure no-clipboard behavior.
- [ ] Add `Speech2TestTests/LongDictationBoundaryTests.swift` for pause-vs-soft-cap segment-boundary decisions using deterministic inputs.
- [ ] Add `Speech2TestTests/TranscriptAssemblerTests.swift` for ordered assembly, whitespace normalization, and partial-failure counting.
- [ ] Add `Speech2TestTests/LongDictationFlowTests.swift` for multi-segment orchestration with mocked transcriber results.
- [ ] Expand `Speech2TestUITests/MenuBarShellSmokeTests.swift` for indicator-hidden menu status and long-session warning identifiers before relying on UI automation.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Long dictation with multiple natural pauses produces one ordered clipboard result | TRNS-03, TRNS-04 | Requires real speech cadence and end-to-end overlap between capture and queued transcription | 1. Start recording 2. Dictate for more than 30 seconds with at least two clear pauses 3. Finish 4. Verify one final clipboard result contains all spoken content in order |
| Continuous speech past the threshold still seals via soft cap instead of losing early audio | TRNS-03 | Hard to reproduce faithfully with unit timing alone | 1. Start recording 2. Keep speaking without a clear pause past the long threshold 3. Finish 4. Verify the transcript still includes early content |
| One segment failure still yields a best-effort combined result with a count-based warning | TRNS-05 | Requires proving that clipboard text stays clean while UI carries incompleteness messaging | 1. Launch with the test-only failure flag added in Plan 05-03, for example `-ui-testing-long-session-fail-segment 2` 2. Finish the session 3. Verify clipboard text includes successful segments only and the menu/pill surfaces a warning count |
| Indicator-hidden mode still exposes long-session status through the menu | TRNS-05 | The product posture matters here, not just identifier existence | 1. Hide the indicator 2. Run a long session 3. Verify the menu remains the persistent status/warning surface |

*If none: "All phase behaviors have automated verification."*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 20s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
