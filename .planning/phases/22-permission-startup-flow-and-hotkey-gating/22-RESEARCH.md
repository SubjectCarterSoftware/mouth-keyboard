# Phase 22: Permission Startup Flow and Hotkey Gating - Research

**Researched:** 2025-07-09
**Domain:** macOS permission prompts (CGEvent APIs), SwiftUI enum rename, startup flow orchestration
**Confidence:** HIGH

## Summary

This phase has two orthogonal changes with a narrow blast radius: (1) auto-prompt Accessibility permission at startup with a delayed call to `CGRequestPostEventAccess()`, and (2) rename `.holdToTranscribe` → `.keyboardShortcuts` throughout the codebase to accurately reflect that Input Monitoring gates all keyboard shortcuts, not just Hold-to-Transcribe.

Both changes are well-constrained by existing code patterns. The Accessibility auto-prompt mirrors the existing Input Monitoring auto-prompt (which fires as a side effect of `CGEvent.tapCreate()` inside `holdMonitor.start()`). The rename propagates through a `CaseIterable` enum with exhaustive `switch` statements — the compiler enforces completeness.

**Primary recommendation:** Implement the delayed `CGRequestPostEventAccess()` call in `applicationDidFinishLaunching` using `DispatchQueue.main.asyncAfter`, then do a mechanical rename of `.holdToTranscribe` → `.keyboardShortcuts` with updated user-facing strings. Both changes are independent and can be ordered in either direction.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Call `CGRequestPostEventAccess()` explicitly in `applicationDidFinishLaunching`, after the existing `hotkeyService.start()` (which already triggers Input Monitoring via `CGEvent.tapCreate()`).
- **D-02:** Add a small delay (0.5–1s) between the Input Monitoring side-effect prompt and the Accessibility prompt so they don't stack.
- **D-03:** Always prompt for Accessibility regardless of Input Monitoring result — don't gate one on the other.
- **D-04:** Fire-and-forget — prompt once, respect the answer. Use the existing `hasRequestedPostEventPermission` flag in `ShellPreferences` to ensure we only auto-prompt once per install.
- **D-05:** Call `readinessStore.refresh()` after both prompts complete so the setup window reflects current status.
- **D-06:** The Input Monitoring permission row gates ALL hotkey functionality (Control+V, Control+B, Hold-to-Transcribe), not just Hold-to-Transcribe.
- **D-07:** Rename `PermissionKind.holdToTranscribe` → `.keyboardShortcuts` throughout the codebase (ReadinessSnapshot, ReadinessStore, SetupWindowView, and all references).
- **D-08:** Update row title from "Hold to Transcribe" → "Keyboard Shortcuts".
- **D-09:** Update status messages: "Ready — shortcuts enabled." / "Needs keyboard access." / "Keyboard access is blocked."
- **D-10:** Prompt order: Input Monitoring first (via existing `hotkeyService.start()` side-effect), then Accessibility (via explicit `CGRequestPostEventAccess()`).
- **D-11:** Small delay (0.5–1s) between prompts.
- **D-12:** Both prompts fire regardless of each other's outcome.

### Claude's Discretion
- Exact delay duration between prompts (anywhere in 0.5–1s range)
- Whether to log prompt results for debugging
- Internal naming of the delay mechanism (DispatchQueue.asyncAfter, Task.sleep, etc.)

### Deferred Ideas (OUT OF SCOPE)
- Renaming "Auto Paste" to "Accessibility" in the UI — user considered this but it's a separate concern from the startup flow and hotkey gating
- Re-attempting failed permission prompts on subsequent launches — decided fire-and-forget is sufficient
</user_constraints>

## Standard Stack

### Core (already in project)
| Library | Purpose | Why Standard |
|---------|---------|--------------|
| CoreGraphics (`CGRequestPostEventAccess`, `CGPreflightPostEventAccess`) | Accessibility permission prompt/check | Apple's sole API for post-event permission management |
| CoreGraphics (`CGEvent.tapCreate`) | Input Monitoring side-effect prompt | System API — tap creation triggers macOS permission dialog |
| SwiftUI | UI views (SetupWindowView, PermissionChecklistView) | Already the UI framework for this project |

### Supporting (already in project)
| Library | Purpose | When to Use |
|---------|---------|-------------|
| `KeyboardShortcuts` (SPM) | Global hotkey registration | Already used by HotkeyService for Control+V etc. |
| `ShellPreferences` (internal) | `hasRequestedPostEventPermission` persistence | Fire-and-forget flag tracking |
| `ReadinessStore` (internal) | Permission status refresh + UI propagation | Called after prompts to update setup window |

### Alternatives Considered
None — all decisions are locked. No new libraries needed.

**Installation:** No new dependencies required.

## Architecture Patterns

### Existing Permission Flow Pattern
The app already follows a consistent pattern for permission services:
1. Service struct with `Adapter` for testability (`isAuthorized`, `requestAccess` closures)
2. `currentStatus(hasPrompted:)` → returns `.authorized`, `.notDetermined`, or `.denied`
3. `requestAccess()` → calls system API, returns grant state
4. `ShellPreferences` tracks "has prompted" flag per permission type
5. Mock support via launch arguments (`-mock-keyboard-status`, `-mock-postevent-status`)

### Startup Auto-Prompt Pattern (NEW — follows existing precedent)
```
applicationDidFinishLaunching:
  1. hotkeyService.start()              // Triggers Input Monitoring prompt via CGEvent.tapCreate()
  2. DispatchQueue.main.asyncAfter(0.75s) {
       if !preferences.hasRequestedPostEventPermission {
         preferences.recordPostEventPermissionPrompt()
         postEventService.requestAccess()      // Triggers Accessibility prompt
         readinessStore.refresh()               // Update UI
       }
     }
```

**Why `DispatchQueue.main.asyncAfter` over `Task.sleep`:** The existing delay pattern in AppDelegate already uses `DispatchQueue.main.asyncAfter` (line 54-56 for postEventGuideRequested notification). Consistency with the same file trumps modern structured concurrency here. Both are acceptable per user's discretion.

### Enum Rename Propagation Pattern
`PermissionKind` is `CaseIterable` with exhaustive `switch` statements. Renaming a case causes compiler errors at every usage site, making it a safe mechanical refactor. The compiler enforces that all switch cases are updated.

### Anti-Patterns to Avoid
- **Gating Accessibility prompt on Input Monitoring result:** D-03/D-12 explicitly forbid this — both prompts fire independently.
- **Re-prompting on subsequent launches:** D-04 specifies fire-and-forget using the existing `hasRequestedPostEventPermission` flag.
- **Renaming accessibility identifiers in UI tests alongside the enum rename:** The `.holdToTranscribe` raw value appears in accessibility identifiers like `"permission.holdToTranscribe.status"`. These will need to update to `"permission.keyboardShortcuts.status"` to match the new enum raw value.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Permission prompt tracking | Custom boolean management | `ShellPreferences.hasRequestedPostEventPermission` + `recordPostEventPermissionPrompt()` | Already exists, already persisted via UserDefaults |
| Permission status refresh | Manual status polling | `ReadinessStore.refresh()` | Already refreshes all three permission statuses in one call |
| Delayed execution | Custom timer or run loop scheduling | `DispatchQueue.main.asyncAfter(deadline:)` | Already used in same file for similar purpose |

## Common Pitfalls

### Pitfall 1: Stacking System Permission Dialogs
**What goes wrong:** macOS can show multiple permission dialogs simultaneously, confusing users.
**Why it happens:** `CGEvent.tapCreate()` (Input Monitoring) and `CGRequestPostEventAccess()` (Accessibility) both trigger system-level modal dialogs. If called too close together, both appear at once.
**How to avoid:** D-02/D-11 require a 0.5–1s delay between prompts. Use 0.75s as a middle-ground default.
**Warning signs:** Both dialogs appearing simultaneously during testing.

### Pitfall 2: Forgetting to Guard with hasRequestedPostEventPermission
**What goes wrong:** The Accessibility prompt appears on every launch, annoying users who already granted or denied it.
**Why it happens:** `CGRequestPostEventAccess()` always shows the dialog if the app isn't already authorized — there's no built-in "already prompted" tracking.
**How to avoid:** Check `preferences.hasRequestedPostEventPermission` before calling `requestAccess()`. Call `preferences.recordPostEventPermissionPrompt()` before the request so the flag is set even if the app crashes during the prompt.
**Warning signs:** Repeated prompts on app relaunch during testing.

### Pitfall 3: Forgetting to Update Accessibility Identifiers After Enum Rename
**What goes wrong:** UI tests break because they reference old identifier strings like `"permission.holdToTranscribe.status"`.
**Why it happens:** `PermissionKind.rawValue` is used in accessibility identifiers (e.g., `"permission.\(item.kind.rawValue).status"`). Renaming `.holdToTranscribe` to `.keyboardShortcuts` changes the raw value from `"holdToTranscribe"` to `"keyboardShortcuts"`.
**How to avoid:** Search for all string references to `"holdToTranscribe"` including in UI test assertions and accessibility identifiers. The UI test file `PermissionRecoveryFlowTests.swift` doesn't currently reference `holdToTranscribe` in identifier strings directly, but the accessibility identifiers in `SetupWindowView.swift` (lines 71, 193, 199, 203) do use hardcoded `"setupWindow.holdToTranscribe.*"` strings that will need updating to `"setupWindow.keyboardShortcuts.*"`.
**Warning signs:** UI test compilation succeeds but tests fail at runtime due to element-not-found.

### Pitfall 4: Not Refreshing After Delayed Prompt
**What goes wrong:** Setup window shows stale permission status after the auto-prompt completes.
**Why it happens:** The prompt fires on a delayed dispatch. If the setup window is already visible, it shows the status from before the prompt.
**How to avoid:** D-05 requires calling `readinessStore.refresh()` inside the delayed block, after the prompt completes.
**Warning signs:** Setup window shows "Needs Setup" for Accessibility even after the user grants it via the auto-prompt.

### Pitfall 5: ReadinessStateTests Using Stale API
**What goes wrong:** Unit tests fail to compile because `ReadinessSnapshot.derive()` and `ReadinessStore.init()` signatures changed in Phase 20 but tests weren't updated.
**Why it happens:** `ReadinessStateTests.swift` still uses the old 2-parameter `derive()` (missing `keyboardStatus`) and old `ReadinessStore.init()` (missing `keyboardService`). This is a known pre-existing issue (noted in STATE.md blockers as part of HTT-08).
**How to avoid:** This phase's rename from `.holdToTranscribe` → `.keyboardShortcuts` will touch these same files. The planner should account for the fact that these tests already need API updates — the rename is an opportunity to fix them, or the plan should explicitly note that these tests are out of scope (per HTT-08 being mapped to Phase 21).
**Warning signs:** Build errors in test target before any changes are made.

## Code Examples

### Auto-Prompt Insertion Point in AppDelegate
```swift
// File: Speech2Text/App/AppDelegate.swift
// Insert after hotkeyService.start() (line 27) and readinessStore.refresh() (line 28)

func applicationDidFinishLaunching(_ notification: Notification) {
    // ... existing code ...
    hotkeyService.start()      // Triggers Input Monitoring prompt (side effect of CGEvent.tapCreate)

    // Auto-prompt Accessibility permission after a short delay
    // so the Input Monitoring dialog doesn't stack with the Accessibility dialog.
    if !preferences.hasRequestedPostEventPermission {
        preferences.recordPostEventPermissionPrompt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self else { return }
            self.postEventService.requestAccess()
            self.readinessStore.refresh()
        }
    }

    readinessStore.refresh()   // Refresh immediately for Input Monitoring status
    // ... rest of existing code ...
}
```

**Note:** `postEventService` is not currently a property of `AppDelegate`. Either:
- Add `private let postEventService = PostEventPermissionService.live` to AppDelegate, OR
- Call through `readinessStore.requestPermission(for: .postEvent)` (but this also records the prompt and does UI work)
- Or call `PostEventPermissionService.live.requestAccess()` directly

The simplest approach is adding the service as an AppDelegate property, consistent with how `readinessStore`, `hotkeyService`, etc. are already declared.

### Enum Rename — Complete Diff Map
```swift
// File: Speech2Text/Readiness/ReadinessSnapshot.swift
// BEFORE:
case holdToTranscribe
// AFTER:
case keyboardShortcuts

// Title change (same file):
// BEFORE:
case .holdToTranscribe: return "Input Monitoring"
// AFTER:
case .keyboardShortcuts: return "Keyboard Shortcuts"

// Message changes (same file):
// BEFORE:
case (.holdToTranscribe, .authorized): return "Ready — hold to record."
case (.holdToTranscribe, .notDetermined): return "Needs keyboard access."
case (.holdToTranscribe, .denied): return "Keyboard access is blocked."
// AFTER:
case (.keyboardShortcuts, .authorized): return "Ready — shortcuts enabled."
case (.keyboardShortcuts, .notDetermined): return "Needs keyboard access."
case (.keyboardShortcuts, .denied): return "Keyboard access is blocked."
```

### Complete File-by-File Rename Inventory

| File | References | What Changes |
|------|-----------|--------------|
| `ReadinessSnapshot.swift` | 10 occurrences | Enum case, title, systemImage, settingsURL, messages, derive() |
| `ReadinessStore.swift` | 1 occurrence | `case .holdToTranscribe:` in `requestPermission()` |
| `PermissionChecklistView.swift` | 2 occurrences | `.holdToTranscribe` comparisons in PermissionTile |
| `SetupWindowView.swift` | 9 occurrences | `HoldToTranscribeRow` struct name, accessibility IDs, status property, label text, openRecovery call |
| `PermissionRecoveryFlowTests.swift` (UI tests) | 0 direct `.holdToTranscribe` references, but tests reference UI strings like "Enable Accessibility" that won't change |

### Accessibility Identifier Updates
```swift
// SetupWindowView.swift — hardcoded identifiers that must update:
"setupWindow.holdToTranscribe.recorder"  → "setupWindow.keyboardShortcuts.recorder"
"setupWindow.holdToTranscribe.message"   → "setupWindow.keyboardShortcuts.message"
"setupWindow.holdToTranscribe.action"    → "setupWindow.keyboardShortcuts.action"
"setupWindow.holdToTranscribe.row"       → "setupWindow.keyboardShortcuts.row"

// PermissionChecklistView.swift — dynamic identifiers that auto-update:
"permission.\(item.kind.rawValue).status"  // Automatically becomes "permission.keyboardShortcuts.status"
"permission.\(item.kind.rawValue).action"  // Automatically becomes "permission.keyboardShortcuts.action"
"permission.\(item.kind.rawValue).row"     // Automatically becomes "permission.keyboardShortcuts.row"
```

### InputMonitoringSetupGuide Title Update
```swift
// File: Speech2Text/Shell/PermissionChecklistView.swift
// BEFORE:
Text("How to enable Hold to Transcribe")
// AFTER:
Text("How to enable Keyboard Shortcuts")
```

### SetupWindowView Label and Action Updates
```swift
// File: Speech2Text/Shell/SetupWindowView.swift
// Row label:
// BEFORE: Text("Hold to Transcribe:")
// AFTER:  Text("Keyboard Shortcuts:")

// Action titles in HoldToTranscribeRow (or renamed struct):
// BEFORE: return "Enable Hold to Transcribe"
// AFTER:  return "Enable Keyboard Shortcuts"
// BEFORE: return "Fix Hold to Transcribe"
// AFTER:  return "Fix Keyboard Shortcuts"

// Detail text:
// BEFORE: return "Ready — hold to record."
// AFTER:  return "Ready — shortcuts enabled."
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single `.holdToTranscribe` enum case | `.keyboardShortcuts` reflecting all hotkey gating | Phase 22 | UI accuracy — users understand all shortcuts require Input Monitoring |
| Accessibility prompted only via Setup UI tile | Auto-prompted at startup (fire-and-forget) | Phase 22 | First-run UX — permission dialog appears automatically |

**Deprecated/outdated:**
- `HoldToTranscribeRow` struct name — becomes `KeyboardShortcutsRow` (or similar)
- `holdToTranscribeStatus` computed property — becomes `keyboardShortcutsStatus`
- All `"holdToTranscribe"` accessibility identifier strings — become `"keyboardShortcuts"`

## Open Questions

1. **Should `HoldToTranscribeRow` struct be renamed to `KeyboardShortcutsRow`?**
   - What we know: D-07 says rename `.holdToTranscribe` → `.keyboardShortcuts` "throughout the codebase." The struct `HoldToTranscribeRow` in SetupWindowView.swift (line 142) is private and only referenced within that file.
   - What's unclear: Whether the user wants internal struct names renamed too, or just the public enum case and user-facing strings.
   - Recommendation: Rename it — it's private, cheap to rename, and keeps internal naming consistent with the new semantics. The user said "throughout the codebase."

2. **Should `requestHoldToTranscribeAccess()` method be renamed?**
   - What we know: This is a private method in SetupWindowView.swift (line 297). Same reasoning as above.
   - Recommendation: Rename to `requestKeyboardShortcutsAccess()` for consistency.

3. **How to access `PostEventPermissionService` from AppDelegate?**
   - What we know: AppDelegate currently doesn't hold a reference to `PostEventPermissionService`. It does hold `readinessStore` which has one internally.
   - Options: (a) Add `private let postEventService = PostEventPermissionService.live` to AppDelegate, (b) call `PostEventPermissionService.live.requestAccess()` inline.
   - Recommendation: Add as a property — consistent with existing `preferences`, `readinessStore`, etc. declarations at the top of AppDelegate.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode built-in) |
| Config file | Xcode project scheme |
| Quick run command | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -only-testing:Speech2TextTests` |
| Full suite command | `xcodebuild test -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| (no IDs) | Accessibility auto-prompt fires once at startup | manual-only | N/A — `CGRequestPostEventAccess()` requires system permission dialog | ❌ Manual verification |
| (no IDs) | Prompt delay prevents dialog stacking | manual-only | N/A — timing of system dialogs not testable | ❌ Manual verification |
| (no IDs) | `hasRequestedPostEventPermission` flag prevents re-prompts | unit | `xcodebuild test ... -only-testing:Speech2TextTests/ShellPreferencesModelTests` | ⚠️ Existing but may need update |
| (no IDs) | `.keyboardShortcuts` enum case replaces `.holdToTranscribe` | unit | Build succeeds — compiler enforces exhaustive switches | ✅ Compiler-verified |
| (no IDs) | `.keyboardShortcuts` title returns "Keyboard Shortcuts" | unit | `xcodebuild test ... -only-testing:Speech2TextTests/ReadinessStateTests` | ⚠️ Tests exist but use stale API |
| (no IDs) | `.keyboardShortcuts` messages match D-09 strings | unit | `xcodebuild test ... -only-testing:Speech2TextTests/ReadinessStateTests` | ⚠️ Tests exist but use stale API |
| (no IDs) | UI shows "Keyboard Shortcuts" in setup window | UI test | `xcodebuild test ... -only-testing:Speech2TextUITests/PermissionRecoveryFlowTests` | ⚠️ Tests exist but reference old strings |
| (no IDs) | `readinessStore.refresh()` called after prompt | unit | Existing `ReadinessStateTests` pattern | ⚠️ Tests exist but use stale API |

### Sampling Rate
- **Per task commit:** Build succeeds (`./build.sh`)
- **Per wave merge:** Full test suite (`xcodebuild test`)
- **Phase gate:** Full suite green + manual verification of dual-prompt UX

### Wave 0 Gaps
- [ ] `ReadinessStateTests.swift` — uses stale `ReadinessSnapshot.derive()` signature (missing `keyboardStatus` param). Must be updated to compile. This is a pre-existing issue (HTT-08, mapped to Phase 21) but this phase's changes will touch the same code. Planner should decide: fix here or leave broken.
- [ ] No unit test for the auto-prompt logic in AppDelegate — AppDelegate is not unit-tested (startup orchestration is integration-level). Manual verification is appropriate for the dual-prompt flow.

## Sources

### Primary (HIGH confidence)
- Direct codebase analysis of all canonical reference files listed in CONTEXT.md
- `PostEventPermissionService.swift` — verified `requestAccess()` wraps `CGRequestPostEventAccess()`
- `KeyboardPermissionService.swift` — verified `requestAccess()` wraps `CGRequestListenEventAccess()`
- `AppDelegate.swift` — verified current startup flow and existing `DispatchQueue.main.asyncAfter` pattern
- `ReadinessSnapshot.swift` — verified full `PermissionKind` enum structure and all switch cases
- `ReadinessStore.swift` — verified `refresh()` and `requestPermission()` implementations
- `SetupWindowView.swift` — verified `HoldToTranscribeRow` struct and all identifier strings
- `PermissionChecklistView.swift` — verified `InputMonitoringSetupGuide` and tile routing logic
- `ShellPreferences.swift` — verified `hasRequestedPostEventPermission` flag and `recordPostEventPermissionPrompt()`
- `PermissionRecoveryFlowTests.swift` — verified UI test structure and launch argument patterns

### Secondary (MEDIUM confidence)
- Apple Developer Documentation: `CGRequestPostEventAccess()` always shows the system dialog if not already authorized (no built-in "don't re-prompt" behavior)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs already in use, no new dependencies
- Architecture: HIGH — follows existing patterns exactly, all integration points verified in source
- Pitfalls: HIGH — identified from direct codebase analysis and understanding of macOS permission dialog behavior
- Rename scope: HIGH — exhaustive grep of all `.holdToTranscribe` references across all targets

**Research date:** 2025-07-09
**Valid until:** 2025-08-09 (stable — no external API changes expected)
