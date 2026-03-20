---
phase: 15-settings-ux-for-ai-assistant-name
plan: "02"
subsystem: testing
tags: [xctestui, xctest, trigger-profile, calibration, ai-assistant, settings]

# Dependency graph
requires:
  - phase: 15-01
    provides: AIAssistantSettingsView, AIAssistantTileView, AIAssistantSettingsViewModel, accessibility identifiers, calibration runner, TriggerProfileStore

provides:
  - Isolated UI-test trigger-profile seed path via -seed-trigger-preset and -seed-trigger-profile-calibrated launch args
  - AIAssistantSettingsFlowTests.swift covering tile visibility, sheet flow, preset rows, custom name field, alias summary
  - ActivationStoreTests coverage proving setTriggerPreset/setCustomTrigger/applyCalibrationAliases affect next finalize session without restart

affects: [future-phases-using-trigger-profile, ui-test-infrastructure]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - UI-test launch argument seed pattern for isolated trigger-profile state via temporary store URL
    - Deterministic alias seeding via -seed-trigger-profile-calibrated flag with canonical + variant aliases

key-files:
  created:
    - Speech2TextUITests/AIAssistantSettingsFlowTests.swift
  modified:
    - Speech2Text/Persistence/ShellPreferences.swift
    - Speech2TextTests/ActivationStoreTests.swift
    - Speech2Text/Shell/AIAssistantSettingsView.swift
    - Speech2Text.xcodeproj/project.pbxproj

key-decisions:
  - "UI tests use a temporary /tmp/Speech2Text.UITests/ directory for isolated trigger-profile store; file is deleted on each test launch to ensure clean state"
  - "-seed-trigger-preset <preset> and -seed-trigger-profile-calibrated launch args applied in ShellPreferences.makeShared() only when -ui-testing is present"
  - "Phase 15 no-restart regression tests use clean trailing-shortcut transcripts to exercise the built-in mode overload path unambiguously"

patterns-established:
  - "Pattern: UI-test trigger isolation — when -ui-testing present, use a fresh tmpdir store instead of TriggerProfileStore.shared"

requirements-completed:
  - SETT-01
  - SETT-02
  - SETT-03

# Metrics
duration: 12min
completed: 2026-03-20
---

# Phase 15 Plan 02: Settings UX for AI Assistant Name — Verification Harness Summary

**Isolated UI-test trigger-profile seeding and no-restart runtime regression tests for the AI Assistant settings surface**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-03-20T18:17:09Z
- **Completed:** 2026-03-20T18:29:00Z
- **Tasks:** 2 of 3 (Task 3 is a human-verify checkpoint — paused)
- **Files modified:** 5

## Accomplishments

- Added `-seed-trigger-preset` and `-seed-trigger-profile-calibrated` launch argument support to `ShellPreferences.makeShared()`, enabling UI tests to start with any trigger-profile state without touching the developer's real Application Support store
- Created `AIAssistantSettingsFlowTests.swift` with 14 UI test cases covering: tile visibility for all three presets, calibrated alias summary appearance, sheet open/close (not a second window), all three preset buttons present, custom name field and save button state, alias summary presence/absence in sheet, repeated open/close stability
- Added 4 `ActivationStoreTests` proving `setTriggerPreset`, `setCustomTrigger`, and `applyCalibrationAliases` all affect finalize-time trigger alias matching in the very next session without restarting the app
- Auto-fixed dead code in `AIAssistantTileView`: removed unused `viewModel` computed property that created a redundant ViewModel allocation alongside the `let vm` in body

## Task Commits

Each task was committed atomically:

1. **Task 1: Add RED end-to-end tests and isolated trigger-profile test hooks** - `96e8930` (feat)
2. **Task 2: Apply verification-driven UX polish and accessibility adjustments** - `e38dec5` (fix)
3. **Task 3: Manual verification** - *Paused at checkpoint*

## Files Created/Modified

- `Speech2TextUITests/AIAssistantSettingsFlowTests.swift` - 14 UI test cases for the Phase 15 settings flow
- `Speech2Text/Persistence/ShellPreferences.swift` - Added -seed-trigger-preset and -seed-trigger-profile-calibrated launch arg handling in makeShared()
- `Speech2TextTests/ActivationStoreTests.swift` - Added 4 Phase 15 no-restart regression tests
- `Speech2Text/Shell/AIAssistantSettingsView.swift` - Removed dead viewModel computed property from AIAssistantTileView
- `Speech2Text.xcodeproj/project.pbxproj` - Registered AIAssistantSettingsFlowTests.swift in Speech2TextUITests target

## Decisions Made

- Used a temporary directory under `/tmp/Speech2Text.UITests/` for UI-test trigger-profile isolation; the file is deleted on each test launch to ensure a clean state even if a prior test crashed
- The seed mechanism is gated on `-ui-testing` flag so it never activates in production builds
- Phase 15 no-restart tests deliberately use clean trailing-shortcut transcripts (e.g., `"... hey zeus convert to slack"`) to exercise the `modeOverload` path unambiguously — mixed instruction text routes correctly to `instructionsOverload` which also proves trigger recognition, but the assertion is cleaner

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed dead viewModel computed property from AIAssistantTileView**
- **Found during:** Task 2 (verification-driven UX polish)
- **Issue:** AIAssistantTileView had both `private var viewModel: AIAssistantSettingsViewModel` (computed, never used) and `let vm = AIAssistantSettingsViewModel(...)` in body — the computed property was dead code creating a redundant allocation
- **Fix:** Removed the unused computed property; the `let vm` in body is the only instance used
- **Files modified:** Speech2Text/Shell/AIAssistantSettingsView.swift
- **Verification:** Build succeeded, 59 tests pass
- **Committed in:** e38dec5 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - dead code bug)
**Impact on plan:** Cosmetic correctness fix, no behavior change.

## Issues Encountered

- First versions of the new ActivationStore tests used transcripts where the built-in command appeared as a leading shortcut (e.g., `"hey zeus convert to email please write this up"`) — this correctly routes to `instructionsOverload` not `modeOverload`. Fixed by using clean trailing-shortcut transcripts where no extra context follows the mode keyword.

## Next Phase Readiness

- Automated test gate is green: 45/45 ActivationStoreTests, 59/59 combined with AIAssistantSettingsViewModelTests
- App builds successfully
- Task 3 (manual verification) requires human to launch the app, exercise the settings flow, and approve
- Phase 15 is the final planned phase for milestone v1.2; completion pending Task 3 sign-off

## User Setup Required

None - no external service configuration required.

---
*Phase: 15-settings-ux-for-ai-assistant-name*
*Completed: 2026-03-20 (Tasks 1-2; Task 3 pending human verify)*
