# Phase 20: Permission Model and UI Wiring - Research

**Researched:** 2026-03-24
**Domain:** macOS permission APIs (CoreGraphics Listen/Post event access), SwiftUI UI wiring
**Confidence:** HIGH

## Summary

This phase fixes a permission wiring bug where the Hold to Transcribe feature UI checks and requests the **wrong macOS permission** (Accessibility / `.postEvent`) instead of the correct one (Input Monitoring / Listen Event access). The core issue is that `CGEvent.tapCreate()` requires **Input Monitoring** permission (`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`), but the UI currently uses `PostEventPermissionService` to drive the Hold to Transcribe row status, labels, and recovery flow.

The fix is entirely UI/model wiring — no changes to `HotkeyService`, `HoldToTranscribeMonitor`, `ActivationStore`, or any underlying hold logic. The `KeyboardPermissionService` already exists and correctly wraps the Listen Event APIs. The primary work is: (1) add a `.holdToTranscribe` case to `PermissionKind`, (2) rewire `SetupWindowView`'s Hold to Transcribe row to use `KeyboardPermissionService`, (3) create an Input Monitoring setup guide, (4) add a new permission checklist tile, and (5) clean up `.postEvent` strings to reference only Auto Paste.

**Primary recommendation:** Add `.holdToTranscribe` to `PermissionKind` with `Privacy_ListenEvent` URL, rewire `HoldToTranscribeRow` to use `KeyboardPermissionService`, create `InputMonitoringSetupGuide` from the `AccessibilitySetupGuide` template, and update all Hold-related strings to feature-oriented wording.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Setup Guide Style:** Steps-only, matching existing Accessibility guide pattern — no "why" explanation
- **Setup Guide Headline:** "How to enable Hold to Transcribe"
- **Setup Guide Steps:** Same as Accessibility guide but step 1 mentions the Input Monitoring pane specifically
- **Setup Guide Button:** "Open Settings & Quit App" — identical to existing
- **Setup Guide Frame:** 270px width matching AccessibilitySetupGuide
- **Hold to Transcribe Row Labels (Feature-Oriented Wording):**
  - Not Determined: status "Needs keyboard access.", button "Enable Hold to Transcribe"
  - Denied: status "Keyboard access is blocked.", button "Fix Hold to Transcribe"
  - Authorized: status "Ready — hold to record.", button *(none)*
- **Recovery flow:** "Fix Hold to Transcribe" opens the setup guide popover (same pattern as Accessibility recovery), which then offers "Open Settings & Quit App"
- **`.postEvent` cleanup:** Remove Hold to Transcribe from all `.postEvent` PermissionKind messages — Auto Paste owns Accessibility
- **Two-Permission Separation:** Each row is self-contained, no cross-references between Input Monitoring and Accessibility
- **Permission Checklist Tile (Scope Extension):** New `.holdToTranscribe` case in PermissionKind. Display title "Input Monitoring", icon "keyboard.fill", required, tile order Microphone → Input Monitoring → Auto Paste
- **PermissionKind Model Changes:** Add `.holdToTranscribe` (or `.keyboard`) case with `settingsURL` → `Privacy_ListenEvent`, feature-oriented messages, `systemImage` "keyboard.fill", `title` "Input Monitoring"

### Claude's Discretion
*(No items were left to Claude's discretion in this phase — all decisions were locked)*

### Deferred Ideas (OUT OF SCOPE)
*(None captured during discussion)*
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| HTT-01 | Hold to Transcribe row checks Input Monitoring status (`CGPreflightListenEventAccess`), not Accessibility | `KeyboardPermissionService` already wraps `CGPreflightListenEventAccess()`. Rewire `HoldToTranscribeRow` to use it instead of `PostEventPermissionService`. |
| HTT-02 | Clicking "Enable" requests Input Monitoring permission (`CGRequestListenEventAccess`) | `KeyboardPermissionService.requestAccess()` already calls `CGRequestListenEventAccess()`. Wire `requestHoldToTranscribeAccess()` to use it. |
| HTT-03 | Recovery action opens Privacy > Input Monitoring, not Accessibility | New `.holdToTranscribe` case in `PermissionKind` with `settingsURL` = `Privacy_ListenEvent`. `RecoveryActionPerformer` needs no changes — it already uses `kind.settingsURL`. |
| HTT-04 | All labels/descriptions reference "Input Monitoring", not "Accessibility" | Update `HoldToTranscribeRow.detailText` and `actionTitle` to feature-oriented wording from CONTEXT.md. Create `InputMonitoringSetupGuide` with "Input Monitoring" references. |
| HTT-05 | Setup guide popover shows steps for Privacy > Input Monitoring | Clone `AccessibilitySetupGuide` → `InputMonitoringSetupGuide` with modified headline and step 1 text. |
| HTT-06 | `PermissionKind` includes `.holdToTranscribe` case with `Privacy_ListenEvent` URL | Add case with `settingsURL`, `title`, `systemImage`, and `message(for:)` entries. |
| HTT-07 | `.postEvent` messages reference only Auto Paste — no Hold to Transcribe mention | Update 3 `.postEvent` messages in `PermissionKind.message(for:)` to remove "Hold to Transcribe". |
| HTT-09 | Toggle/tap activation, Auto Paste flow, and unrelated features unchanged | Scope limited to UI wiring — no changes to HotkeyService, HoldToTranscribeMonitor, ActivationStore, or paste logic. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CoreGraphics | macOS 10.15+ | `CGPreflightListenEventAccess()`, `CGRequestListenEventAccess()` for Input Monitoring permission | Apple system framework — the only API for listen-event permission |
| SwiftUI | macOS 14+ | UI views, popovers, state management | App's existing UI framework |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| AppKit (NSWorkspace) | macOS 14+ | Open System Settings via URL scheme | Recovery action: open Privacy > Input Monitoring pane |
| XCTest | Xcode bundled | UI and unit testing | Verification in Phase 21 |

### Alternatives Considered
*None — this phase uses only existing frameworks already in the project.*

**No installation needed** — all dependencies are system frameworks already linked.

## Architecture Patterns

### Existing Architecture (Follow These Patterns)

```
Speech2Text/
├── Permissions/
│   ├── KeyboardPermissionService.swift    # ← Already exists, ready to wire
│   ├── PostEventPermissionService.swift   # ← Update messages only
│   └── MicrophonePermissionService.swift  # ← Unchanged
├── Readiness/
│   ├── ReadinessSnapshot.swift            # ← Add .holdToTranscribe to PermissionKind
│   └── ReadinessStore.swift               # ← Wire KeyboardPermissionService + add to derive()
├── Shell/
│   ├── SetupWindowView.swift              # ← Rewire HoldToTranscribeRow
│   ├── PermissionChecklistView.swift      # ← Add Input Monitoring tile
│   └── RecoveryActions.swift              # ← No changes needed (uses kind.settingsURL)
└── Persistence/
    └── ShellPreferences.swift             # ← hasRequestedKeyboardPermission already exists
```

### Pattern 1: Permission Service Adapter
**What:** Each permission domain wraps system APIs behind an Adapter struct, with `isAuthorized` and `requestAccess` closures. Mock support via `LaunchArgumentOverrides`.
**When to use:** Any new permission check.
**Example:**
```swift
// Existing KeyboardPermissionService (no changes needed to the service itself)
struct KeyboardPermissionService {
    struct Adapter {
        var isAuthorized: () -> Bool    // wraps CGPreflightListenEventAccess()
        var requestAccess: () -> Bool   // wraps CGRequestListenEventAccess()
    }
    
    func currentStatus(hasPrompted: Bool) -> PermissionGrantState {
        if adapter.isAuthorized() { return .authorized }
        return hasPrompted ? .denied : .notDetermined
    }
}
```

### Pattern 2: PermissionKind Enum (Centralized Permission Model)
**What:** Single enum in `ReadinessSnapshot.swift` defining all permission types with their title, icon, settings URL, and status messages.
**When to use:** Adding the `.holdToTranscribe` case follows this exact pattern.
**Example:**
```swift
enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case holdToTranscribe    // NEW
    case postEvent
    
    var settingsURL: URL? {
        switch self {
        case .holdToTranscribe:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        // ...
        }
    }
}
```

### Pattern 3: Setup Guide Popover
**What:** A SwiftUI view displayed as a `.popover()` showing numbered steps and an "Open Settings & Quit App" button.
**When to use:** Permissions requiring manual System Settings navigation (both Accessibility and Input Monitoring).
**Template:** `AccessibilitySetupGuide` → clone to `InputMonitoringSetupGuide`.

### Pattern 4: Permission Checklist Tile
**What:** `PermissionTile` in `PermissionChecklistView` renders each `PermissionChecklistItem` with icon, status label, title, and action button. Tile behavior branches on `item.kind` for popover routing.
**When to use:** The new `.holdToTranscribe` tile follows this pattern exactly.

### Anti-Patterns to Avoid
- **Cross-referencing permissions in UI:** Each permission row/tile must be self-contained. Don't mention Input Monitoring in the Accessibility row or vice versa.
- **Modifying HoldToTranscribeMonitor or HotkeyService:** The underlying hold logic is correct — only the UI wiring is broken.
- **Using `.keyboard` as the case name:** CONTEXT.md says `.holdToTranscribe` (or `.keyboard`), but the tile title is "Input Monitoring" — use `.holdToTranscribe` for consistency with the feature name.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Listen event permission check | Custom CGEvent-based detection | `KeyboardPermissionService` (already exists) | Already wraps `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()` with mock support |
| System Settings deep link | Manual process launch | `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` URL via `NSWorkspace.shared.open()` | Existing `RecoveryActionPerformer` pattern handles this automatically via `PermissionKind.settingsURL` |
| Permission prompt tracking | New storage mechanism | `ShellPreferences.hasRequestedKeyboardPermission` (already exists) | Already persisted, already reset in `reset()`, already supports `-mark-keyboard-requested` launch argument |

**Key insight:** Almost all infrastructure needed already exists. The `KeyboardPermissionService`, `hasRequestedKeyboardPermission`, and `-mock-keyboard-status` launch argument were built in v1.0 but never wired into the UI.

## Common Pitfalls

### Pitfall 1: CaseIterable Order Determines Tile Display Order
**What goes wrong:** `PermissionKind.allCases` order determines the iteration order in `PermissionChecklistView`. If `.holdToTranscribe` is added in the wrong position in the enum, tiles appear in wrong order.
**Why it happens:** Swift enums with `CaseIterable` iterate in declaration order.
**How to avoid:** Place `.holdToTranscribe` between `.microphone` and `.postEvent` in the enum declaration to get the desired Microphone → Input Monitoring → Auto Paste order.
**Warning signs:** Tile order in UI doesn't match expected left-to-right flow.

### Pitfall 2: ReadinessSnapshot.derive() Signature Change Breaks Tests
**What goes wrong:** Adding `keyboardStatus` parameter to `ReadinessSnapshot.derive()` breaks all existing callers (ReadinessStore, ReadinessStateTests).
**Why it happens:** The function gains a new required parameter.
**How to avoid:** Update all callers simultaneously. There are exactly 4 call sites: `ReadinessStore.init`, `ReadinessStore.refresh()`, and 3 calls in `ReadinessStateTests`.
**Warning signs:** Compile errors in `ReadinessStore.swift` and `ReadinessStateTests.swift`.

### Pitfall 3: PermissionChecklistView Popover Routing
**What goes wrong:** The `PermissionTile` currently has a hardcoded `if item.kind == .postEvent` check (line 70) that triggers `showsSetupGuide = true`. The new `.holdToTranscribe` tile also needs a setup guide popover, but the guide is different.
**Why it happens:** The popover currently shows `AccessibilitySetupGuide` unconditionally.
**How to avoid:** Make the tile's popover content vary by `item.kind` — `.postEvent` shows `AccessibilitySetupGuide`, `.holdToTranscribe` shows `InputMonitoringSetupGuide`. Consider a conditional `ViewBuilder` or two separate `@State` booleans.
**Warning signs:** Input Monitoring tile shows Accessibility instructions, or popover doesn't appear.

### Pitfall 4: Notification-Driven Popover on PostEvent Tile
**What goes wrong:** The `PermissionTile` listens for `.postEventGuideRequested` notification (line 100-104) to open its guide. This mechanism only triggers for `.postEvent`. If the Hold to Transcribe row's "Enable" button relies on a similar notification path, it needs its own.
**Why it happens:** The notification pattern was built specifically for the postEvent flow.
**How to avoid:** The `HoldToTranscribeRow` already manages its own `@State showsAccessibilityGuide` popover — it doesn't use the notification. Rename to `showsSetupGuide` and wire to the new guide. For the checklist tile, add `.holdToTranscribe` to the `if` check on line 70-71 or use a dedicated state.
**Warning signs:** Setup guide popover doesn't open from the checklist tile.

### Pitfall 5: `.postEvent` Message Strings Referenced Elsewhere
**What goes wrong:** Updating `.postEvent` messages in `PermissionKind.message(for:)` might break UI test assertions that match on exact string content.
**Why it happens:** UI tests assert on specific text content.
**How to avoid:** Check all UI test files for strings containing "Hold to Transcribe" or "Accessibility" in the context of `.postEvent`. The existing tests (`PermissionRecoveryFlowTests`) use accessibility identifier queries, not string matching for postEvent messages — so they should be safe. But verify.
**Warning signs:** UI tests fail after message text changes.

### Pitfall 6: `isRequired` Flag on New Permission
**What goes wrong:** Setting `.holdToTranscribe` as `isRequired: true` means a denied state triggers "Setup Blocked" and prevents `canFinishSetup`.
**Why it happens:** `canFinishSetup` checks `permissions.filter(\.isRequired).allSatisfy(\.isAuthorized)`.
**How to avoid:** This is the desired behavior per CONTEXT.md ("Required: Yes — treated as a required permission"). Ensure existing tests that check `.ready` state now also grant keyboard status.
**Warning signs:** Setup can't be finalized in tests because keyboard permission isn't granted in test fixtures.

## Code Examples

### Example 1: PermissionKind with `.holdToTranscribe`
```swift
// Source: ReadinessSnapshot.swift — extend existing enum
enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case holdToTranscribe    // NEW — between microphone and postEvent for tile order
    case postEvent

    var title: String {
        switch self {
        case .microphone:     return "Microphone Access"
        case .holdToTranscribe: return "Input Monitoring"
        case .postEvent:      return "Auto Paste"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone:     return "mic.fill"
        case .holdToTranscribe: return "keyboard.fill"
        case .postEvent:      return "doc.on.clipboard.fill"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .holdToTranscribe:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .postEvent:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    func message(for status: PermissionGrantState) -> String {
        switch (self, status) {
        // ... microphone cases unchanged ...
        case (.holdToTranscribe, .authorized):
            return "Ready — hold to record."
        case (.holdToTranscribe, .notDetermined):
            return "Needs keyboard access."
        case (.holdToTranscribe, .denied):
            return "Keyboard access is blocked."
        case (.postEvent, .authorized):
            return "Auto Paste can insert text into other apps."
        case (.postEvent, .notDetermined):
            return "Allow Accessibility access so Auto Paste works across apps."
        case (.postEvent, .denied):
            return "Accessibility access is blocked. Re-enable it in System Settings to use Auto Paste."
        }
    }
}
```

### Example 2: ReadinessSnapshot.derive() with Keyboard Status
```swift
// Source: ReadinessSnapshot.swift — update derive signature
static func derive(
    isSetupComplete: Bool,
    microphoneStatus: PermissionGrantState,
    keyboardStatus: PermissionGrantState,       // NEW parameter
    postEventStatus: PermissionGrantState
) -> Self {
    let permissions = [
        PermissionChecklistItem(
            kind: .microphone,
            status: microphoneStatus,
            message: PermissionKind.microphone.message(for: microphoneStatus),
            isRequired: true
        ),
        PermissionChecklistItem(
            kind: .holdToTranscribe,              // NEW tile
            status: keyboardStatus,
            message: PermissionKind.holdToTranscribe.message(for: keyboardStatus),
            isRequired: true                       // Required per CONTEXT.md
        ),
        PermissionChecklistItem(
            kind: .postEvent,
            status: postEventStatus,
            message: PermissionKind.postEvent.message(for: postEventStatus),
            isRequired: false
        ),
    ]
    // ... rest of derive logic unchanged
}
```

### Example 3: ReadinessStore Wiring
```swift
// Source: ReadinessStore.swift — add keyboardService
@MainActor
final class ReadinessStore: ObservableObject {
    private let keyboardService: KeyboardPermissionService  // NEW
    
    init(
        preferences: ShellPreferences,
        microphoneService: MicrophonePermissionService,
        keyboardService: KeyboardPermissionService,         // NEW parameter
        postEventService: PostEventPermissionService,
        recoveryActionPerformer: RecoveryActionPerformer = .live
    ) {
        self.keyboardService = keyboardService
        // ... use in derive:
        let initialSnapshot = ReadinessSnapshot.derive(
            isSetupComplete: preferences.hasCompletedInitialSetup,
            microphoneStatus: microphoneService.currentStatus(),
            keyboardStatus: keyboardService.currentStatus(hasPrompted: preferences.hasRequestedKeyboardPermission),
            postEventStatus: postEventService.currentStatus(hasPrompted: preferences.hasRequestedPostEventPermission)
        )
    }
    
    func requestPermission(for kind: PermissionKind) {
        switch kind {
        // ... existing cases ...
        case .holdToTranscribe:
            preferences.recordKeyboardPermissionPrompt()
            _ = keyboardService.requestAccess()
            refresh()
        }
    }
}
```

### Example 4: InputMonitoringSetupGuide (Cloned from AccessibilitySetupGuide)
```swift
// Source: PermissionChecklistView.swift — new view alongside existing
struct InputMonitoringSetupGuide: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to enable Hold to Transcribe")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                SetupStep(number: 1, text: "Click the + button in the Input Monitoring pane")
                SetupStep(number: 2, text: "Find Speech2Text in Applications and click Open")
                SetupStep(number: 3, text: "Relaunch Speech2Text from your menu bar or Applications")
            }

            Button("Open Settings & Quit App") {
                onOpenSettings()
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 270)
    }
}
```

### Example 5: HoldToTranscribeRow Rewired
```swift
// Source: SetupWindowView.swift — update the row
private struct HoldToTranscribeRow: View {
    @ObservedObject var preferences: ShellPreferences
    let status: PermissionGrantState
    let requestAccess: () -> Void
    let openRecovery: () -> Void

    @State private var showsSetupGuide = false    // Renamed from showsAccessibilityGuide

    private var detailText: String {
        switch status {
        case .authorized:    return "Ready — hold to record."
        case .notDetermined: return "Needs keyboard access."
        case .denied:        return "Keyboard access is blocked."
        }
    }

    private var actionTitle: String? {
        switch status {
        case .authorized:    return nil
        case .notDetermined: return "Enable Hold to Transcribe"
        case .denied:        return "Fix Hold to Transcribe"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // ... same layout ...
            if let actionTitle {
                Button(actionTitle) {
                    showsSetupGuide = true
                }
            }
        }
        .popover(isPresented: $showsSetupGuide, arrowEdge: .bottom) {
            InputMonitoringSetupGuide {        // Changed from AccessibilitySetupGuide
                showsSetupGuide = false
                if status == .denied {
                    openRecovery()
                } else {
                    requestAccess()
                }
            }
        }
    }
}
```

### Example 6: SetupWindowView Computed Properties Rewired
```swift
// Source: SetupWindowView.swift — change from PostEvent to Keyboard service
private let keyboardPermissionService = KeyboardPermissionService.live  // Changed

private var holdToTranscribeStatus: PermissionGrantState {
    keyboardPermissionService.currentStatus(hasPrompted: preferences.hasRequestedKeyboardPermission)
}

private func requestHoldToTranscribeAccess() {
    preferences.recordKeyboardPermissionPrompt()        // Changed
    _ = keyboardPermissionService.requestAccess()        // Changed
}

// And in the body, change openRecovery to use .holdToTranscribe:
// openRecovery: { readinessStore.openRecovery(for: .holdToTranscribe) }
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `AXIsProcessTrusted()` for all event access | Separate `CGPreflightListenEventAccess()` and `CGPreflightPostEventAccess()` | macOS 10.15 (Catalina, 2019) | Listen-only taps require Input Monitoring, not Accessibility |
| Single Privacy > Accessibility pane for all CGEvent access | Separate Privacy > Input Monitoring pane | macOS 10.15 (Catalina, 2019) | Users must grant permissions in the correct pane |

**Critical distinction (macOS 10.15+):**
- `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()` → **Input Monitoring** pane → for `CGEvent.tapCreate()` with `.listenOnly`
- `CGPreflightPostEventAccess()` / `CGRequestPostEventAccess()` → **Accessibility** pane → for `CGEvent.post()` / synthetic events
- These are **separate permissions** since macOS 10.15. The app currently conflates them.

## Open Questions

1. **Info.plist `NSAccessibilityUsageDescription` string**
   - What we know: The current string says "Speech2Text monitors the keyboard shortcut you configure so it can start recording when you activate it." This describes Input Monitoring behavior but is keyed under `NSAccessibilityUsageDescription`.
   - What's unclear: macOS does not have a dedicated `NSInputMonitoringUsageDescription` key — Input Monitoring permission doesn't use Info.plist strings. The `NSAccessibilityUsageDescription` still applies to the `.postEvent` (Accessibility) permission. The current wording describes keyboard monitoring, not Auto Paste.
   - Recommendation: Consider updating `NSAccessibilityUsageDescription` to describe Auto Paste instead (since Accessibility permission now only serves Auto Paste), but this is **out of scope** for Phase 20 per the separation principle. Flag for future cleanup.

2. **ReadinessSnapshot.derive() Signature — Future Requirement HTT-F01**
   - What we know: REQUIREMENTS.md lists `HTT-F01` ("ReadinessSnapshot.derive() gains a keyboardStatus parameter") as a **Future Requirement** and lists "ReadinessSnapshot keyboard status parameter" as **Out of Scope**.
   - What's unclear: CONTEXT.md explicitly includes the Permission Checklist Tile (scope extension overriding REQUIREMENTS.md's out-of-scope note). Adding the tile inherently requires adding `keyboardStatus` to `derive()`.
   - Recommendation: The user explicitly chose to include the checklist tile, which necessarily requires the `derive()` signature change. Implement it. This is a conscious scope extension, not scope creep.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode bundled) |
| Config file | Xcode project scheme (Speech2Text.xcodeproj) |
| Quick run command | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests/PermissionServiceTests -only-testing:Speech2TextTests/ReadinessStateTests` |
| Full suite command | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HTT-01 | Hold row checks Input Monitoring status | unit | `xcodebuild test ... -only-testing:Speech2TextTests/ReadinessStateTests` | ✅ Exists (needs update) |
| HTT-02 | Enable button requests Input Monitoring | unit | `xcodebuild test ... -only-testing:Speech2TextTests/PermissionServiceTests` | ✅ Exists (keyboard tests cover adapter invocation) |
| HTT-03 | Recovery opens Input Monitoring pane | unit | Assert `.holdToTranscribe.settingsURL` contains `Privacy_ListenEvent` | ❌ Wave 0 |
| HTT-04 | Labels reference Input Monitoring not Accessibility | UI test | `xcodebuild test ... -only-testing:Speech2TextUITests/PermissionRecoveryFlowTests` | ✅ Exists (Phase 21 updates) |
| HTT-05 | Setup guide shows Input Monitoring steps | UI test | `xcodebuild test ... -only-testing:Speech2TextUITests/PermissionRecoveryFlowTests` | ✅ Exists (Phase 21 updates) |
| HTT-06 | PermissionKind has .holdToTranscribe with correct URL | unit | Assert `PermissionKind.holdToTranscribe.settingsURL` | ❌ Wave 0 |
| HTT-07 | .postEvent messages reference only Auto Paste | unit | Assert `.postEvent` messages don't contain "Hold to Transcribe" | ❌ Wave 0 |
| HTT-09 | Unrelated features unchanged | unit + UI | Full test suite | ✅ Exists |

### Sampling Rate
- **Per task commit:** `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests`
- **Per wave merge:** Full suite including UI tests
- **Phase gate:** Full suite green before `$gsd-verify-work`

### Wave 0 Gaps
- [ ] Add unit test asserting `PermissionKind.holdToTranscribe.settingsURL` contains `Privacy_ListenEvent` — covers HTT-03, HTT-06
- [ ] Add unit test asserting `.postEvent` messages don't contain "Hold to Transcribe" — covers HTT-07
- [ ] Update `ReadinessStateTests` to pass `keyboardStatus` parameter — prevents compile failure

*(Note: UI test updates for HTT-04, HTT-05 are explicitly Phase 21 scope per REQUIREMENTS.md traceability)*

## Sources

### Primary (HIGH confidence)
- **Codebase inspection** — All 8 source files read directly: ReadinessSnapshot.swift, KeyboardPermissionService.swift, PostEventPermissionService.swift, MicrophonePermissionService.swift, SetupWindowView.swift, PermissionChecklistView.swift, ReadinessStore.swift, RecoveryActions.swift, ShellPreferences.swift
- **Apple Developer Documentation (JSON API)** — `CGPreflightListenEventAccess()` (macOS 10.15+), `CGRequestListenEventAccess()` (macOS 10.15+) confirmed as CoreGraphics functions returning Bool
- **Existing test files** — PermissionServiceTests.swift (4 tests), ReadinessStateTests.swift (4 tests), PermissionRecoveryFlowTests.swift (7 UI tests)

### Secondary (MEDIUM confidence)
- **macOS System Settings URL scheme** — `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` for Input Monitoring pane. This follows the established pattern used by `Privacy_Microphone` and `Privacy_Accessibility` in the existing codebase. Apple does not officially document these URL anchors, but they are stable across macOS 13-15.

### Tertiary (LOW confidence)
*None — all findings verified against codebase or official API docs.*

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs already used in the project, confirmed via codebase
- Architecture: HIGH — patterns established in prior phases, code read directly
- Pitfalls: HIGH — identified from actual code structure, not hypothetical
- URL scheme: MEDIUM — `Privacy_ListenEvent` follows established pattern but isn't officially documented by Apple

**Research date:** 2026-03-24
**Valid until:** Indefinite — macOS system APIs are stable; codebase patterns are established
