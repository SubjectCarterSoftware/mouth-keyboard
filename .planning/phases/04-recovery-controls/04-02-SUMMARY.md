---
phase: 04-recovery-controls
plan: 02
subsystem: audio-recovery
tags: [macos, avfoundation, microphone, clipboard, recovery, xctest, swiftui]
requires:
  - phase: 04-recovery-controls
    plan: 01
    provides: cancel/restart recovery orchestration, menu-first recovery posture, clipboard-safe recovery foundation
provides:
  - typed microphone denial, unavailable, and disconnect failures without silent fallback
  - ActivationStore-owned capture failure handling with a strict success-only clipboard barrier
  - approved live verification for microphone failure and empty-result clipboard integrity
affects: [phase-04-verification, phase-05-long-dictation-reliability, recovery-ui, clipboard-safety]
tech-stack:
  added: []
  patterns:
    - typed audio capture failures instead of silent fallback or generic idle collapse
    - selected microphone preservation across recoverable device failures
    - clipboard writes gated on current-session non-empty success only
key-files:
  created: []
  modified:
    - Speech2Test/Audio/AudioCaptureService.swift
    - Speech2Test/Activation/RecordingState.swift
    - Speech2Test/Activation/ActivationStore.swift
    - Speech2Test/App/AppDelegate.swift
    - Speech2Test/Shell/RecordingPillView.swift
    - Speech2Test/Shell/RecoveryActions.swift
    - Speech2Test/Shell/SetupWindowView.swift
    - Speech2Test/Shell/StatusMenuView.swift
    - Speech2TestTests/AudioCaptureServiceTests.swift
    - Speech2TestTests/ActivationStoreTests.swift
    - Speech2TestUITests/PermissionRecoveryFlowTests.swift
key-decisions:
  - "Selected microphone preference is preserved when input disappears; recovery is explicit instead of silently switching to the default device."
  - "ActivationStore owns capture-failure invalidation so stale transcription completions and clipboard writes stay behind the same session-token barrier."
  - "The approved human-verification checkpoint closes plan 04-02 without reopening setup or re-running the microphone scenarios."
patterns-established:
  - "AudioCaptureService throws microphone-specific errors that map directly to RecordingState failure reasons."
  - "Microphone failures and empty results surface through the pill/menu while leaving the clipboard untouched until a current-session non-empty success path completes."
requirements-completed: [AUDI-04, CLIP-02]
duration: ~5h across 2 sessions
completed: 2026-03-08
---

# Phase 4 Plan 02: Recovery Controls Summary

**Typed microphone failure recovery with preserved device selection, success-only clipboard writes, and approved live verification for denied, unavailable, disconnected, and empty-result paths**

## Performance

- **Duration:** ~5h across 2 sessions (implementation work landed in ~9 minutes; the remainder was checkpoint pause and closeout)
- **Started:** 2026-03-08T14:28:02Z
- **Completed:** 2026-03-08T19:07:49Z
- **Tasks:** 4
- **Files modified:** 11

## Accomplishments

- Added typed audio-layer failures for microphone denial, selected-device unavailability, no usable input, and mid-session disconnects without clearing the user's preferred microphone selection.
- Routed start-time and mid-session capture failures through `ActivationStore` so session invalidation, stale async completion suppression, and clipboard safety all follow one recovery path.
- Added pill/menu recovery messaging and smoke coverage, then closed the human-verification checkpoint as approved for start failure, disconnect, and empty-result clipboard preservation.

## Task Commits

Each task was committed atomically:

1. **Task 1: Surface typed microphone failures from the audio layer and remove silent fallback** - `e21d2b8` (fix)
2. **Task 2: Wire capture-failure handling through ActivationStore and finish the success-only clipboard barrier** - `da9c65e` (fix)
3. **Task 3: Surface microphone recovery messaging in the pill/menu and add focused smoke coverage** - `2999caf` (feat)
4. **Task 4: Human verification for microphone failure handling and clipboard integrity** - Approved at checkpoint continuation; no code changes required

## Files Created/Modified

- `Speech2Test/Audio/AudioCaptureService.swift` - Typed microphone failures, selected-device preservation, and disconnect propagation.
- `Speech2Test/Activation/ActivationStore.swift` - Centralized capture-failure invalidation and clipboard-safe failure handling.
- `Speech2Test/App/AppDelegate.swift` - Forwarded start-time and disconnect errors into the store-owned recovery path.
- `Speech2Test/Shell/StatusMenuView.swift` - Persistent microphone recovery messaging and actions.
- `Speech2Test/Shell/RecoveryActions.swift` - Reused settings routing for microphone recovery actions.
- `Speech2TestTests/AudioCaptureServiceTests.swift` - Regression coverage for denied/unavailable/disconnect failure typing and restartability.
- `Speech2TestTests/ActivationStoreTests.swift` - Clipboard-safety coverage for capture failures, empty transcripts, and stale completions.
- `Speech2TestUITests/PermissionRecoveryFlowTests.swift` - Smoke coverage for surfaced recovery copy and actions.

## Decisions Made

- Preserved `preferences.micDeviceUID` across missing/disconnected input so the recovery UI can explain what failed instead of silently rerouting to a default device.
- Kept clipboard integrity as a prevention problem, not a restoration problem: failed, canceled, disconnected, and empty-result paths never begin a pasteboard write.
- Treated the already-approved human-verification response as the completion signal for Task 4 and recorded it in the plan closeout instead of reopening the checkpoint.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The standard `gsd-tools` plan-closeout helpers would mark Phase 4 complete as soon as they saw `2/2` summaries, which would skip the separate phase-level verification step. This closeout was recorded manually to keep plan `04-02` complete while Phase 4 stays explicitly in progress.

## User Setup Required

None - the required live microphone and clipboard verification was already completed and approved.

## Next Phase Readiness

- Plan `04-02` is complete, summarized, and reflected in roadmap/requirements state.
- Phase 4 itself remains open only for phase-level verification and final phase-closeout bookkeeping; no implementation blocker remains.

## Self-Check: PASSED

- Verified `.planning/phases/04-recovery-controls/04-02-SUMMARY.md` exists on disk.
- Verified task commits `e21d2b8`, `da9c65e`, and `2999caf` exist in git history and match the completed task sequence.
- Verified the approved human-verification checkpoint was carried into this closeout from the continuation context.

---
*Phase: 04-recovery-controls*
*Completed: 2026-03-08*
