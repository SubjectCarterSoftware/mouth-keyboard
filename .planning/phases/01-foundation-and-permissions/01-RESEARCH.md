# Phase 1: Foundation and Permissions - Research

**Researched:** 2026-03-05
**Domain:** Native macOS menu bar utility shell, first-run permissions, and readiness-state modeling
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Permission setup should begin on first launch rather than waiting for the first recording attempt.
- First-run setup should use a checklist-style flow that shows required items and clear next steps.
- If permission is denied, the app should keep a persistent blocked warning rather than quietly degrading.
- Recovery should both explain what is wrong and provide a direct path into the relevant System Settings area.
- The menu bar presence should stay subtle; detailed state belongs inside the app menu rather than the menu bar itself.
- Opening the menu should show a compact status card at the top with the current readiness state and the next action.
- When the app transitions from blocked to ready, it should give a brief confirmation rather than a loud persistent success state.
- When the app is blocked, the primary menu action should be a clear setup/recovery action such as "Fix setup."
- Speech2Test should behave as a menu bar utility first, not as a standard Dock-forward app.
- Regular day-to-day use should be menu-bar only, without a normal persistent Dock presence.
- On first launch, the app should open its setup/readiness UI once, then stay in the menu bar afterward.
- The app should keep a normal Quit action in the menu; Phase 1 does not need a special always-on quit model.

### Claude's Discretion
- Exact copywriting for checklist items, blocked warnings, and recovery messaging.
- Exact visual treatment of the menu bar icon as long as it stays subtle and the menu carries the detailed state.
- Exact structure of the Phase 1 settings/setup UI, provided it supports the chosen checklist-style first-run flow.
- Exact visual form of the brief "ready" confirmation after permissions are fixed.

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope.

</user_constraints>

<research_summary>
## Summary

Phase 1 should establish a native macOS utility shell, not just a placeholder app. Apple’s current menu bar patterns point to two viable paths: a SwiftUI-first `MenuBarExtra` shell for rapid greenfield development, or an AppKit `NSStatusBar`/`NSStatusItem` shell when finer lifecycle control is needed. Because Speech2Test is greenfield and the user wants a restrained utility, the primary recommendation is a SwiftUI-first menu bar app with `LSUIElement` enabled, plus an explicit setup/settings window that is shown once on first launch and reopened from the menu.

The permission story is more nuanced than the product copy suggests. Microphone permission is straightforward through `AVCaptureDevice.authorizationStatus(for:)` and `requestAccess(for:)`. Keyboard-related permission depends on the implementation path used later: Apple’s archived event-monitoring guide says global `NSEvent` key monitoring requires accessibility trust, while Apple DTS recommends a `CGEventTap` plus `CGPreflightListenEventAccess`/`CGRequestListenEventAccess` for sandboxed keyboard listening. The planner should therefore treat readiness as capability-based rather than hard-coding a single future input-capture mechanism.

**Primary recommendation:** Build Phase 1 around a `MenuBarExtra`-first Swift app, an explicit `ReadinessService` that snapshots permission states, and a first-launch checklist UI that can explain and deep-link recovery without yet committing Phase 2 to a specific keyboard-capture primitive.
</research_summary>

<standard_stack>
## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift + SwiftUI `MenuBarExtra` | Swift 6.x / modern Xcode | Primary menu bar utility shell | Apple documents `MenuBarExtra` as the native scene for persistent menu bar controls, and it supports menu-only utility apps cleanly in greenfield projects |
| AppKit `NSStatusBar` / `NSStatusItem` | System framework | Fallback or deeper-control status item implementation | Still the lowest-level standard when SwiftUI menu bar behavior is too constrained or when custom status-item behavior is required |
| AVFoundation `AVCaptureDevice` authorization APIs | System framework | Microphone permission preflight and request flow | Apple’s supported media-authorization path for microphone access on macOS |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `UserDefaults` / `@AppStorage` | Built-in | Persist first-launch completion, visibility flags, and shell preferences | Use first because Phase 1 only needs lightweight settings and onboarding persistence |
| Accessibility API `AXIsProcessTrustedWithOptions` | System API | Accessibility trust check / prompt when that privilege is actually needed | Use if the chosen keyboard-monitoring path truly needs Accessibility access |
| Core Graphics `CGPreflightListenEventAccess` / `CGRequestListenEventAccess` | System API | Input Monitoring preflight and request for event-tap based key listening | Use when later phases adopt `CGEventTap` rather than `NSEvent` global monitors |
| ServiceManagement `SMAppService` | System framework | Launch-at-login integration | Useful for later polish; not required to satisfy Phase 1 but should shape shell architecture |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftUI `MenuBarExtra` | Pure AppKit `NSStatusItem` shell | AppKit offers more control, but it increases setup cost in a repo with no app shell yet |
| Built-in `UserDefaults` / `@AppStorage` | `Defaults` package | `Defaults` is nicer for typed keys, but Phase 1 does not need extra dependency surface yet |
| Accessibility-global `NSEvent` monitoring | `CGEventTap` with Input Monitoring | Event taps are lower-level and more awkward, but Apple DTS explicitly recommends them for sandboxed keyboard listening |

**Installation:**
```bash
# No third-party runtime dependency is required for Phase 1
# Create native macOS app target and use built-in Apple frameworks first
```
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Project Structure
```text
Speech2Test/
├── App/                    # App entry, app delegate, scene setup
├── Shell/                  # Menu bar shell, settings/setup window, status menu
├── Permissions/            # Capability checks and request wrappers
├── Readiness/              # Readiness snapshot, status derivation, gating logic
├── Persistence/            # First-launch and shell preference storage
└── Tests/                  # Unit + UI test targets
```

### Pattern 1: Capability-Based Readiness Snapshot
**What:** Model readiness as a single snapshot derived from individual capabilities like microphone access, keyboard-monitoring readiness, and first-launch completion.
**When to use:** Immediately in Phase 1, because the shell must say "ready" or "blocked" before recording exists.
**Example:**
```swift
struct ReadinessSnapshot: Equatable {
    enum State { case ready, needsSetup, blocked }

    var microphone: PermissionState
    var keyboardMonitoring: PermissionState
    var firstLaunchCompleted: Bool

    var overallState: State {
        if microphone == .denied || keyboardMonitoring == .denied { return .blocked }
        if microphone != .granted || keyboardMonitoring != .granted || !firstLaunchCompleted {
            return .needsSetup
        }
        return .ready
    }
}
```

### Pattern 2: Menu Bar Shell + Dedicated Setup Window
**What:** Keep the day-to-day app as a menu bar utility, but use a real window for first-launch setup and later settings/recovery.
**When to use:** Use this because the user wants menu-bar-first behavior but also wants an explicit checklist flow.
**Example:**
```swift
@main
struct Speech2TestApp: App {
    @State private var showSetup = true

    var body: some Scene {
        MenuBarExtra("Speech2Test", systemImage: "waveform") {
            StatusMenuView()
        }

        Window("Setup", id: "setup") {
            SetupView()
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
```

### Pattern 3: Permission Services Behind One Readiness Facade
**What:** Keep microphone, accessibility, and input-monitoring checks in separate small services and aggregate them in one readiness layer.
**When to use:** Always; it prevents Phase 1 UI from embedding platform logic directly into views.
**Example:**
```swift
protocol PermissionService {
    func currentState() -> PermissionState
    func requestIfNeeded()
}
```

### Anti-Patterns to Avoid
- **Hard-coding "Accessibility required" everywhere:** Apple’s own guidance differs depending on whether later phases use `NSEvent` monitors or `CGEventTap`; Phase 1 should keep the shell capability-oriented.
- **Baking readiness logic into view code:** The menu and setup UI should render a derived state, not decide permission semantics themselves.
- **Starting with a normal Dock-window app and retrofitting menu bar behavior later:** That usually produces a shell the user never asked for and creates extra cleanup work.
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Menu bar shell | Custom floating palette pretending to be a status item | `MenuBarExtra` or `NSStatusBar` | Apple already provides the right utility-app primitives and lifecycle |
| Microphone permission flow | Custom low-level TCC detection hacks | `AVCaptureDevice.authorizationStatus(for:)` + `requestAccess(for:)` | The media authorization APIs are the documented path and are easier to test |
| Launch-at-login integration | Custom helper/launchd plumbing from scratch | `SMAppService` when Phase 1/2 is ready for it | Apple already exposes the supported registration surface |
| Global keyboard readiness assumptions | One boolean called `hasAccessibility` | Separate capability checks for Accessibility and/or Input Monitoring | The actual privilege required depends on the implementation path |

**Key insight:** The riskiest part of this phase is not UI polish; it is getting the shell and permission story aligned with Apple’s documented paths so later phases do not need a shell rewrite.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Phase 1 hard-codes the wrong keyboard permission
**What goes wrong:** The shell and copy assume Accessibility is the only path, but later implementation uses event taps and needs Input Monitoring instead.
**Why it happens:** Teams collapse all keyboard-related permissions into one concept too early.
**How to avoid:** Build a generic keyboard-monitoring readiness slot and keep the implementation-specific mapping configurable until Phase 2 locks the input strategy.
**Warning signs:** Permission copy names Accessibility everywhere while the code later checks `CGPreflightListenEventAccess()`.

### Pitfall 2: The menu bar shell is too invisible when blocked
**What goes wrong:** The user launches the app, sees a subtle icon, and still has no idea why the app cannot be used.
**Why it happens:** Utility apps over-optimize for staying out of the way.
**How to avoid:** Keep the icon subtle, but make the menu’s top status card and blocked CTA unambiguous.
**Warning signs:** The user must hunt through Settings to discover what prerequisite failed.

### Pitfall 3: First-launch setup is mixed directly into the steady-state menu
**What goes wrong:** The Phase 1 shell becomes cluttered because onboarding, recovery, and daily use all share the same surface.
**Why it happens:** It feels cheaper than adding a dedicated setup/settings window early.
**How to avoid:** Show setup once on first launch, then fall back to the quiet menu-bar shell with recovery entry points.
**Warning signs:** Menu content grows into a wizard and stops feeling like a utility.
</common_pitfalls>

<code_examples>
## Code Examples

Verified patterns from official sources:

### Menu Bar Utility Shell
```swift
// Source: Apple MenuBarExtra docs
@main
struct UtilityApp: App {
    var body: some Scene {
        MenuBarExtra("Speech2Test", systemImage: "waveform") {
            StatusMenuView()
        }
    }
}
```

### Microphone Permission Preflight
```swift
// Source: AVCaptureDevice authorization APIs
let status = AVCaptureDevice.authorizationStatus(for: .audio)
if status == .notDetermined {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
        // update readiness state on main actor
    }
}
```

### Accessibility / Input Monitoring Boundary
```swift
// Source: ApplicationServices / CoreGraphics permission APIs
let accessibilityReady = AXIsProcessTrustedWithOptions(nil)
let inputMonitoringReady = CGPreflightListenEventAccess()
```
</code_examples>

<sota_updates>
## State of the Art (2024-2026)

What's changed recently:

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Build menu bar utilities entirely in AppKit | SwiftUI `MenuBarExtra` is now a serious first choice for greenfield menu bar apps | Modern SwiftUI macOS releases | Faster shell delivery for a greenfield native app |
| Treat keyboard listening as an Accessibility-only concern | Apple DTS explicitly recommends `CGEventTap` + Input Monitoring for sandboxed keyboard listening | Current Apple guidance remains relevant in 2026 | Phase 1 should not overfit its permission model to a single future implementation path |
| Hand-roll login-item helpers | `SMAppService` provides the supported registration API | Modern ServiceManagement APIs | Later launch-at-login work can stay on the documented path |

**New tools/patterns to consider:**
- `MenuBarExtra` window style: useful if the compact status card later grows beyond a simple menu.
- `SMAppService.mainApp`: useful when launch-at-login becomes part of a later polish phase.

**Deprecated/outdated:**
- Using archived shared file list login-item APIs as the default plan — use ServiceManagement instead.
- Building a fake status-item UI with custom floating windows — use native menu bar scenes/items first.
</sota_updates>

## Validation Architecture

This phase should establish automated verification from the first Xcode target creation so later menu bar and readiness work does not accumulate untestable shell logic.

- **Framework:** XCTest for unit/state tests, XCUITest for shell-launch smoke checks
- **Primary quick check:** `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' -only-testing:Speech2TestTests/ReadinessStateTests -only-testing:Speech2TestTests/PermissionServiceTests`
- **Primary full check:** `xcodebuild test -scheme Speech2Test -destination 'platform=macOS'`
- **Manual verification still needed:** Confirm menu-bar-only presence, first-launch setup appearance, and blocked-to-ready transitions on a clean machine/profile
- **Wave 0 expectation:** Plan 01 should create the app target and test targets before later tasks rely on automated shell/readiness checks

<open_questions>
## Open Questions

1. **Should Phase 1 already expose a specific keyboard permission label to users?**
   - What we know: The roadmap and requirements want keyboard-related permission onboarding early.
   - What's unclear: Later implementation may use Accessibility or Input Monitoring depending on the actual hotkey/session-key strategy.
   - Recommendation: Keep UI copy capability-based ("Keyboard monitoring permission") and let Phase 2 refine the exact privilege language if necessary.

2. **Is `MenuBarExtra` sufficient, or will Phase 1 need direct `NSStatusItem` control immediately?**
   - What we know: `MenuBarExtra` is the fastest native path for a greenfield utility app.
   - What's unclear: If the first-launch/setup window orchestration or subtle status behavior becomes awkward, AppKit may provide better control.
   - Recommendation: Plan Phase 1 to start with SwiftUI-first shell scaffolding, but keep Plan 01 free to bridge to AppKit if specific friction appears during implementation.
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation, `MenuBarExtra` — https://developer.apple.com/documentation/swiftui/menubarextra
- Apple Developer Documentation, `NSStatusBar` — https://developer.apple.com/documentation/AppKit/NSStatusBar
- Apple Developer Documentation, `AVCaptureDevice` and authorization APIs — https://developer.apple.com/documentation/avfoundation/avcapturedevice and https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess%28for%3Acompletionhandler%3A%29
- Apple Developer Documentation, `AXIsProcessTrustedWithOptions` — https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- Apple Developer Documentation, `SMAppService` — https://developer.apple.com/documentation/servicemanagement/smappservice

### Secondary (MEDIUM confidence)
- Apple Documentation Archive, `Monitoring Events` — https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html
- Apple Developer Forums (DTS), sandboxed keyboard listening guidance — https://developer.apple.com/forums/thread/707680

### Tertiary (LOW confidence - needs validation)
- None for this phase; the critical shell and permission guidance came from Apple sources.
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: native macOS menu bar shell and readiness model
- Ecosystem: SwiftUI/AppKit utility-app options, permissions APIs, ServiceManagement
- Patterns: readiness snapshot, dedicated setup window, permission-service boundary
- Pitfalls: permission mis-modeling, blocked-state invisibility, onboarding/shell entanglement

**Confidence breakdown:**
- Standard stack: HIGH - Apple frameworks and primitives are well-defined for this phase
- Architecture: HIGH - the phase boundary is narrow and maps cleanly to known macOS utility-app patterns
- Pitfalls: HIGH - the primary risks are concrete and directly tied to Apple’s permission surfaces
- Code examples: HIGH - all examples are derived from official APIs or Apple guidance

**Research date:** 2026-03-05
**Valid until:** 2026-04-05
</metadata>

---
*Phase: 01-foundation-and-permissions*
*Research completed: 2026-03-05*
*Ready for planning: yes*
