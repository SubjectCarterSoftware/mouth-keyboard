---
phase: 01-foundation-and-permissions
plan: 01
status: complete
completed: 2026-03-05
---

# Plan 01-01 Summary: Native App Shell and Persistence Foundation

## What Was Built

A greenfield native macOS menu-bar utility shell with persistent first-launch preferences and test scaffolding.

## Delivered Artifacts

| File | Purpose |
|------|---------|
| `Speech2Test/App/Speech2TestApp.swift` | `@main` SwiftUI entry; wires `MenuBarExtra` with `.menu` style, injects `ShellPreferences` and `ReadinessStore` as shared `@StateObject` instances |
| `Speech2Test/App/AppDelegate.swift` | `NSApplicationDelegateAdaptor`; sets `.accessory` activation policy, presents/dismisses the setup window, calls `readinessStore.refresh()` on launch and app-become-active |
| `Speech2Test/Shell/StatusMenuView.swift` | Primary menu bar control surface (receives openSetup / quitApp callbacks) |
| `Speech2Test/Shell/SetupWindowView.swift` | First-launch 480×470 setup window scaffold, presented once via `AppDelegate.presentSetupWindow()` |
| `Speech2Test/Persistence/ShellPreferences.swift` | `UserDefaults`-backed `ObservableObject`; persists `hasCompletedInitialSetup`, `showsMenuHints`, `hasRequestedMicrophonePermission`, `hasRequestedKeyboardPermission`; test-friendly via suite isolation and launch-argument overrides |
| `Speech2TestUITests/MenuBarShellSmokeTests.swift` | Two UI smoke tests: first-launch shows setup window; completed-setup suppresses it on relaunch |
| `Speech2TestTests/ReadinessStateTests.swift` | Initial placeholder scaffolding (extended in plan 01-02) |

## Key Design Decisions

- **Accessory activation policy** — `NSApp.setActivationPolicy(.accessory)` keeps the app out of the Dock and Cmd-Tab switcher in steady state.
- **Setup window is a transient `NSWindow`** — presented imperatively by `AppDelegate`, not as a SwiftUI `WindowGroup`, so it can be cleanly dismissed without affecting the menu bar scene.
- **Shared singletons via dependency injection** — `ShellPreferences.shared` and `ReadinessStore.shared` are both injected into views rather than accessed ad-hoc, enabling test isolation.
- **Launch-argument overrides for testing** — `-ui-testing`, `-reset-shell-preferences`, `-complete-shell-setup`, `-open-setup-window`, `-mock-*-status` flags allow UI tests to exercise any shell state without live system permission changes.
- **Separate UserDefaults suite for UI tests** — `ShellPreferences.makeShared()` uses a `.ui-tests`-suffixed suite when `-ui-testing` is present to isolate test state from real preferences.

## Verification Status

**Code complete. Build verification blocked.**

- `xcodebuild` cannot run: `xcode-select` points at `/Library/Developer/CommandLineTools` instead of a full Xcode installation.
- Swift type-checking was also blocked by the SDK mismatch; no compiler output was produced.
- Human verification required: build the scheme in Xcode, confirm the app launches as a menu-bar-only utility, and run `Speech2TestUITests/MenuBarShellSmokeTests`.

## Dependencies Created for Phase 2

- `ShellPreferences.shared` — Phase 2 can read/write `hasRequestedMicrophonePermission` / `hasRequestedKeyboardPermission` and add new preference keys to the same suite.
- `ReadinessStore.shared` — Phase 2 permission and capture work feeds into the existing readiness model rather than adding a parallel state layer.
- Launch-argument override infrastructure — Phase 2 and later UI tests can add new `-mock-*` flags with no structural changes.
