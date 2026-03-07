---
phase: 02-activation-and-capture
plan: 01
subsystem: activation
tags:
  - keyboardshortcuts
  - cgeventtap
  - shellpreferences
  - swiftui
  - xctest
requires:
  - phase: 01-foundation-and-permissions
    provides: readiness state, setup window shell, and persisted shell preferences
provides:
  - readiness-gated recording state with activation store contracts for later audio wiring
  - configurable activation UI with hotkey recorder, tap mode picker, and activation sound toggle
  - CGEventTap-based hotkey service with single-tap and double-tap detection
affects:
  - 02-02
  - 02-03
  - setup-window
tech-stack:
  added:
    - KeyboardShortcuts 1.17.0
  patterns:
    - ReadinessProviding test seam for activation gating
    - CGEventTap callback dispatching to main-thread activation logic
    - ShellPreferences reset with persistence suspension for default restoration
key-files:
  created:
    - Speech2Test/Activation/ActivationStore.swift
    - Speech2Test/Activation/RecordingState.swift
    - Speech2Test/Activation/HotkeyService.swift
    - Speech2TestTests/ActivationStoreTests.swift
    - Speech2TestTests/ShellPreferencesPhase2Tests.swift
    - Speech2TestTests/HotkeyServiceTests.swift
  modified:
    - Speech2Test/App/AppDelegate.swift
    - Speech2Test/Persistence/ShellPreferences.swift
    - Speech2Test/Shell/SetupWindowView.swift
    - Speech2Test.xcodeproj/project.pbxproj
    - Speech2Test.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
key-decisions:
  - ActivationStore uses a lightweight ReadinessProviding seam so readiness gating stays testable without singleton coupling.
  - The Activation section is always visible in SetupWindowView so users can configure hotkeys before finishing setup.
  - Debug builds use ONLY_ACTIVE_ARCH to keep the KeyboardShortcuts package import stable in this minimal Xcode project layout.
patterns-established:
  - Preferences-backed activation mode toggles should persist through ShellPreferences rather than ad hoc UserDefaults access.
  - Global hotkey interception uses CGEventTap for event consumption while KeyboardShortcuts handles recorder UI and persistence.
  - Activation logic is verified with injectable clocks and callbacks instead of real event taps.
requirements-completed:
  - ACTV-01
  - ACTV-02
  - ACTV-03
  - ACTV-04
  - CONF-03
duration: 28min
completed: 2026-03-06
---

# Phase 02 Plan 01: Activation Settings and Hotkey Detection Summary

**KeyboardShortcuts-backed activation settings, readiness-gated recording state, and CGEventTap double-tap arming for Phase 2 activation.**

## Performance

- **Duration:** 28 min
- **Started:** 2026-03-06T01:51:37Z
- **Completed:** 2026-03-06T02:19:55Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- Extended `ShellPreferences` with persisted tap mode, activation sound, and microphone selection defaults plus reset-safe default restoration.
- Added `RecordingState`, `ActivationStore`, and `HotkeyService` so activation can arm recording only when readiness is green and can distinguish single-tap versus double-tap activation.
- Extended the setup window with an always-visible Activation section using `KeyboardShortcuts.Recorder`, a tap mode picker, and an activation sound toggle.
- Added Phase 2 unit tests covering preferences, activation gating, double-tap timing, and default hotkey registration.

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend ShellPreferences, define RecordingState and ActivationStore, scaffold tests**
   - `1fe7520` (`test`) RED phase for activation store and Phase 2 shell preferences
   - `feab882` (`feat`) activation state contracts and persisted Phase 2 preferences
2. **Task 2: Implement HotkeyService with CGEventTap and double-tap detection, extend SetupWindowView**
   - `e2cc4f3` (`test`) RED phase for hotkey timing and default shortcut behavior
   - `fb75495` (`feat`) hotkey service, KeyboardShortcuts integration, and setup window activation controls
   - `b4a1ff8` (`fix`) app lifecycle wiring to start and stop the shared hotkey service

## Files Created/Modified

- `Speech2Test/Activation/ActivationStore.swift` - readiness-gated recording state store with injectable readiness dependency
- `Speech2Test/Activation/RecordingState.swift` - `TapMode` and `RecordingState` enums used across Phase 2 activation code
- `Speech2Test/Activation/HotkeyService.swift` - KeyboardShortcuts name registration, CGEventTap lifecycle, and double-tap detection logic
- `Speech2Test/App/AppDelegate.swift` - starts and stops the shared hotkey service with app lifecycle events
- `Speech2Test/Persistence/ShellPreferences.swift` - persists tap mode, activation sound, microphone UID, and test launch overrides
- `Speech2Test/Shell/SetupWindowView.swift` - Activation settings section with recorder, segmented tap mode control, and sound toggle
- `Speech2TestTests/ActivationStoreTests.swift` - readiness gating and recording state transition coverage
- `Speech2TestTests/ShellPreferencesPhase2Tests.swift` - preference defaults, persistence, and reset behavior coverage
- `Speech2TestTests/HotkeyServiceTests.swift` - double-tap window behavior and default shortcut coverage
- `Speech2Test.xcodeproj/project.pbxproj` - adds activation sources, tests, KeyboardShortcuts package integration, and Debug arch settings
- `Speech2Test.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` - pins KeyboardShortcuts to 1.17.0

## Decisions Made

- Used a `ReadinessProviding` protocol so `ActivationStore` can be exercised without depending on `ReadinessStore.shared`.
- Kept the Activation section visible before setup completion so the hotkey can be configured during onboarding, matching the phase context.
- Matched the KeyboardShortcuts example project by enabling `ONLY_ACTIVE_ARCH = YES` in Debug, which stabilized package imports for the current Xcode project shape.
- Used `KeyboardShortcuts` only for recorder UI and persisted shortcut storage while keeping the actual global interception in `CGEventTap` for double-tap control.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added Debug active-architecture settings for package-backed builds**
- **Found during:** Task 2 (HotkeyService and KeyboardShortcuts integration)
- **Issue:** After resolving `KeyboardShortcuts`, the minimal project attempted multi-arch Debug compilation and the app target could not import the package module reliably.
- **Fix:** Added `ONLY_ACTIVE_ARCH = YES` to the project and target Debug configurations, matching the package example’s Xcode setup.
- **Files modified:** `Speech2Test.xcodeproj/project.pbxproj`
- **Verification:** `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' -derivedDataPath /tmp/Speech2Test-DerivedData -clonedSourcePackagesDirPath /tmp/Speech2Test-SourcePackages -only-testing:Speech2TestTests` succeeded with 21 passing unit tests.
- **Committed in:** `fb75495`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The deviation was limited to Xcode Debug build settings required to make the chosen package integration compile and test reliably. No product scope changed.

## Issues Encountered

- Initial `xcodebuild` runs inside the sandbox could not write DerivedData and SwiftPM cache files under the default home-directory locations. Verification succeeded after running the same commands outside the sandbox with DerivedData and cloned packages rooted in `/tmp`.
- The first Task 2 implementation passed the hotkey unit slice but had not yet started the shared hotkey service on app launch. A follow-up lifecycle fix in `AppDelegate` corrected that before final verification.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `ActivationStore`, `RecordingState`, and `HotkeyService` now give Plan 02 and Plan 03 a stable activation contract to build audio capture and recording UI on top of.
- `ShellPreferences.micDeviceUID` is in place for the upcoming microphone picker and device service work.
- The setup window already exposes activation configuration, so Phase 2 can add the microphone picker without reshaping the shell UI.

## Self-Check: PASSED

- Verified `.planning/phases/02-activation-and-capture/02-01-SUMMARY.md` exists on disk.
- Verified task and follow-up commit hashes `1fe7520`, `feab882`, `e2cc4f3`, `fb75495`, and `b4a1ff8` exist in git history.
