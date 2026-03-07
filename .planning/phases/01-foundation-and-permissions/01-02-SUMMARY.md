---
phase: 01-foundation-and-permissions
plan: 02
status: complete
completed: 2026-03-05
---

# Plan 01-02 Summary: Permission Services, Readiness Model, and Setup UX

## What Was Built

Capability-based permission services, a readiness state/store, status card and checklist UI, and automated tests for readiness derivation and setup/recovery flows.

## Delivered Artifacts

| File | Purpose |
|------|---------|
| `Speech2Test/Readiness/ReadinessSnapshot.swift` | Pure value-type readiness derivation: `PermissionGrantState`, `PermissionKind`, `ReadinessState`, `PermissionChecklistItem`, `ReadinessSnapshot.derive(...)`, `LaunchArgumentOverrides` |
| `Speech2Test/Readiness/ReadinessStore.swift` | `ObservableObject` that aggregates permission services and preferences into a published `ReadinessSnapshot`; handles `refresh()`, `requestPermission(for:)`, `openRecovery(for:)`, `finalizeSetup()`, ready-confirmation flash |
| `Speech2Test/Permissions/MicrophonePermissionService.swift` | Closure-based struct wrapping `AVCaptureDevice` authorization; supports `-mock-microphone-status` launch override |
| `Speech2Test/Permissions/KeyboardPermissionService.swift` | Adapter-based struct wrapping `CGPreflightListenEventAccess` / `CGRequestListenEventAccess`; models undetermined vs denied via `hasPrompted` flag to avoid misreading the binary CG return |
| `Speech2Test/Shell/StatusCardView.swift` | Compact top-of-menu status card rendering the current `ReadinessSnapshot` |
| `Speech2Test/Shell/PermissionChecklistView.swift` | Checklist-style setup/blocked UI listing each `PermissionChecklistItem` with Allow / Open Settings actions |
| `Speech2Test/Shell/RecoveryActions.swift` | `RecoveryActionPerformer` — opens the correct `x-apple.systempreferences` deep-link URL for each `PermissionKind` |
| `Speech2TestTests/PermissionServiceTests.swift` | Unit tests for microphone and keyboard permission service status mapping |
| `Speech2TestTests/ReadinessStateTests.swift` | Unit tests for needs-setup, blocked, ready state derivation, and ready-confirmation flash behavior |
| `Speech2TestUITests/PermissionRecoveryFlowTests.swift` | UI smoke tests for setup and recovery flows via launch-argument overrides |

## Key Design Decisions

- **Readiness derivation is a pure function** — `ReadinessSnapshot.derive(...)` takes three inputs (setup flag + two permission states) and returns a value type; it is trivially testable with no mocks.
- **Keyboard permission models undetermined vs denied** — Core Graphics only returns a boolean, so `KeyboardPermissionService.currentStatus(hasPrompted:)` uses the stored `hasRequestedKeyboardPermission` flag to distinguish "never asked" from "asked and denied".
- **Permission services are dependency-injected structs** — both services use closure/adapter patterns so `ReadinessStore` tests can supply any permission state without mocking the OS.
- **Ready-confirmation is a transient message** — `ReadinessStore.readyConfirmation` is set only when the state transitions from non-ready to ready, then cleared on the next non-ready refresh, avoiding persistent noise in the menu.
- **Recovery opens deep-link System Settings URLs** — `RecoveryActionPerformer` uses `x-apple.systempreferences` URLs specific to each permission kind, testable by injecting a no-op `openURL` closure.
- **All permission UI driven by the shared readiness model** — `StatusCardView` and `PermissionChecklistView` render from `ReadinessSnapshot`; no permission logic lives in view structs.

## Verification Status

**Code complete. Build and test verification blocked.**

- `xcodebuild` cannot run: `xcode-select` points at `/Library/Developer/CommandLineTools` instead of a full Xcode installation.
- Swift type-checking was also blocked by the SDK mismatch; no compiler output was produced.
- Human verification required: build the scheme in Xcode, run `Speech2TestTests` and `Speech2TestUITests/PermissionRecoveryFlowTests`, and manually confirm the menu reports ready / needs-setup / blocked before any recording code exists.

## Dependencies Created for Phase 2

- `ReadinessStore.requestPermission(for:)` — Phase 2 recording activation can trigger actual permission prompts through the existing store method rather than calling AVFoundation directly.
- `PermissionGrantState` / `PermissionKind` — Phase 2 audio capture and hotkey registration can reuse these types rather than defining parallel permission enums.
- Mock override infrastructure — Phase 2 UI tests can set `-mock-microphone-status authorized` and `-mock-keyboard-status authorized` to simulate a fully ready state without live permission changes.
