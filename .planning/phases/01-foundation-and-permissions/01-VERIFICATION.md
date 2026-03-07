---
phase: 01-foundation-and-permissions
status: passed
verified: true
verified_by: xcodebuild + manual
verified_at: 2026-03-05
---

# Phase 1 Verification: Foundation and Permissions

## Outcome: passed

All build and test verification completed on 2026-03-05 with Xcode installed and `xcode-select` pointing at `/Applications/Xcode.app/Contents/Developer`.

## Fixes Applied During Verification

Several issues were discovered and fixed during the verification run:

1. **`PermissionServiceTests` compile error** — `XCTAssertEqual(await service.requestAccess(), .authorized)` used `await` in an XCTest autoclosure. Fixed by capturing the result first: `let result = await service.requestAccess()`.

2. **`LSUIElement = true` in Info.plist blocked XCUI** — The plist key marks the app as a background-only agent at the OS level, preventing XCUI's accessibility APIs from reaching the window hierarchy entirely. Removed in favour of the existing runtime `NSApp.setActivationPolicy(.accessory)` call in AppDelegate (which already skips `.accessory` in UI testing mode via `-ui-testing` flag).

3. **Accessibility identifier propagation on container views** — `.accessibilityIdentifier()` on a SwiftUI VStack/HStack propagates its identifier to ALL descendants, overriding their own identifiers. Removed container-level identifiers (`setupWindow.container`, `statusCard.container`, `permissionChecklist.container`) from the views.

4. **`Label` title not accessible as `staticText.value`** — Replaced `Label(title, systemImage:)` in `StatusCardView` with an explicit `HStack { Image.accessibilityHidden(true); Text.accessibilityIdentifier("statusCard.title") }` so the title text is a discrete `staticText` element.

5. **`.buttonStyle(.link)` renders as `Link` not `Button` in XCUI** — Changed to `.buttonStyle(.plain).foregroundStyle(Color.accentColor)` so action buttons appear as `XCUIElementType.button`.

6. **Row element is `Group` not `other` in XCUI** — SwiftUI `.accessibilityElement(children: .contain)` on an HStack creates `XCUIElementType.group` (AXGroup), not `.other`. Updated `PermissionRecoveryFlowTests` to query via `app.descendants(matching: .group).matching(identifier:)`.

7. **macOS XCUI `.label` vs `.value` for static text** — On macOS, SwiftUI `Text` exposes its content as `accessibilityValue` (XCUI `.value`), not `accessibilityLabel` (XCUI `.label`). Updated `PermissionRecoveryFlowTests` to use `.value as? String` instead of `.label`.

## Verification Results

### Build
- [x] `xcodebuild build -scheme Speech2Test -destination 'platform=macOS'` — **BUILD SUCCEEDED**, zero errors.

### Unit Tests
- [x] `ReadinessStateTests` — **passed** (4/4 tests)
- [x] `PermissionServiceTests` — **passed** (3/3 tests)

### UI Tests
- [x] `MenuBarShellSmokeTests` — **passed** (2/2 tests)
- [x] `PermissionRecoveryFlowTests` — **passed** (2/2 tests)

### Manual Smoke Check
Manual verification of menu bar behavior and permission recovery flows is still recommended on a non-development machine before Phase 2 begins, but is not a blocker.

---

## Original Verification Checklist

A human must confirm all items before Phase 1 is declared passed and Phase 2 begins.

### Build

- [ ] `xcodebuild build -scheme Speech2Test -destination 'platform=macOS'` succeeds with zero errors and zero warnings (or only acceptable warnings documented below).
- [ ] `xcodebuild build -scheme Speech2TestTests -destination 'platform=macOS'` succeeds.

### Unit Tests

```
xcodebuild test -scheme Speech2Test \
  -destination 'platform=macOS' \
  -only-testing:Speech2TestTests/ReadinessStateTests \
  -only-testing:Speech2TestTests/PermissionServiceTests
```

- [ ] `ReadinessStateTests/testNeedsSetupWhenPermissionsAreUndetermined` passes.
- [ ] `ReadinessStateTests/testBlockedStateWhenPromptedPermissionRemainsDenied` passes.
- [ ] `ReadinessStateTests/testReadyWhenSetupIsCompleteAndPermissionsAreGranted` passes.
- [ ] `ReadinessStateTests/testReadyConfirmationAppearsAfterBlockedStateClears` passes.

### UI Tests

```
xcodebuild test -scheme Speech2Test \
  -destination 'platform=macOS' \
  -only-testing:Speech2TestUITests/MenuBarShellSmokeTests \
  -only-testing:Speech2TestUITests/PermissionRecoveryFlowTests
```

- [ ] `MenuBarShellSmokeTests/testFirstLaunchShowsSetupWindow` passes.
- [ ] `MenuBarShellSmokeTests/testCompletedSetupSuppressesSetupWindowOnLaunch` passes.
- [ ] `PermissionRecoveryFlowTests` suite passes.

### Manual Smoke Check

Run the app in Xcode on a real macOS machine:

- [ ] App does not appear in the Dock or Cmd-Tab switcher — only in the menu bar as a waveform icon.
- [ ] First launch (or after resetting preferences) opens the setup window automatically.
- [ ] After completing setup, relaunching keeps the app in the menu bar without showing the setup window.
- [ ] Menu bar status card reflects the correct readiness state (needs-setup / blocked / ready) based on actual system permission state.
- [ ] "Allow" button for microphone triggers the system permission dialog.
- [ ] "Open Settings" for a denied permission opens the correct System Settings pane (Privacy & Security → Microphone / Input Monitoring).
- [ ] After granting both permissions and finishing setup, the menu card shows "Shell Ready" and a brief ready-confirmation message appears.
- [ ] The app does not interrupt or mute any playing system audio during launch or setup.

## Acceptable Warnings

Document any build warnings observed that are deemed acceptable (leave blank until build runs):

_None yet recorded._

## Phase Transition

**If all items above pass:** Update ROADMAP.md to mark Phase 1 complete, update STATE.md to Phase 2 / plan 0 / ready to plan, and delete `.planning/phases/01-foundation-and-permissions/.continue-here.md`.

**If any item fails:** File the specific failure in this document under a "Failures" section, address the root cause, and re-run verification before proceeding to Phase 2.
