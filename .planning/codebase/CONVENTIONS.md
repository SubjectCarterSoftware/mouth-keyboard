# Coding Conventions

**Analysis Date:** 2026-03-22

## Naming Patterns

**Files:**
- PascalCase matching the primary type: `ActivationStore.swift`, `HotkeyService.swift`, `LLMRewriteService.swift`
- View files include "View" suffix: `RecordingPillView.swift`, `StatusMenuView.swift`, `PermissionChecklistView.swift`
- Protocol-backed service files use "Service" suffix: `ClipboardService.swift`, `AudioCaptureService.swift`
- Test files mirror source file names with "Tests" suffix: `ActivationStoreTests.swift`, `HotkeyServiceTests.swift`

**Types:**
- Classes, structs, enums, protocols: PascalCase
- Enums used as namespaces: caseless `enum` with only `static` members (e.g., `enum IntentDetector`)
- Error enums: `SomethingError` pattern — `LLMRewriteError`, `AudioCaptureError`
- Protocol names are gerund or "-ing" forms: `WhisperTranscribing`, `LLMRewriting`, `AudioBufferReceiving`, `ReadinessProviding`

**Functions and Variables:**
- camelCase throughout
- Boolean properties use verb prefixes: `isListening`, `isPersistenceSuspended`, `hasInstalledTap`, `hasCompletedInitialSetup`
- Published properties use noun forms: `state`, `recoveryFeedback`, `lastTranscription`
- Factory functions use `make` prefix: `makeDefaultLoader()`, `makePersistentHub()`, `makeStore()` (in tests)
- Closures stored as properties named by what they do: `onArm`, `onStop`, `onCancel`, `hubFactory`, `streamFactory`

**Keys and Constants:**
- UserDefaults keys are gathered in a nested `enum Keys` with `static let` constants:
  ```swift
  enum Keys {
      static let suiteName = "com.elicarter.Speech2Text.shell"
      static let whisperModel = "whisperModel"
  }
  ```
- Nanosecond durations are written as integer literals with underscores: `1_500_000_000`, `5 * 60 * 1_000_000_000`

## Code Style

**Formatting:**
- No formatter config file detected (no `.swiftformat`, `.editorconfig`, or SwiftFormat integration found)
- 4-space indentation
- Opening braces on same line; closing braces on their own line
- One blank line between logical sections within a type
- Multi-line function calls use trailing comma style and align arguments

**Access Control:**
- Explicit `private` on all internal implementation details
- `private(set)` for `@Published` properties that should be externally observable but not mutatable
- Explicit `final` on all concrete classes that are not designed for subclassing
- Protocols used instead of concrete types for all injectable dependencies

**Concurrency:**
- `@MainActor` is applied to the entire class for UI-bound stores: `ActivationStore`, `ShellPreferences`, `HotkeyService`
- `actor` is used for thread-safe service types: `LLMRewriteService`, `RewriteExecutionGate`
- `[weak self]` used consistently in all Task captures and Combine sinks involving `self`
- `Task { @MainActor [weak self] in ... }` pattern used in closures that must hop to main actor
- `@Sendable` applied to closure parameters crossing actor boundaries

**Shared Singletons:**
- Every service has `static let shared = ...` for production use
- Shared instances are created via factory closures that inject real implementations
- Tests always create fresh instances with dependency injection — never use `.shared`

## Import Organization

**Order:**
1. System frameworks (Foundation, AVFoundation, AppKit, SwiftUI, Combine)
2. Third-party packages (Hub, MLXLLM, MLXLMCommon, KeyboardShortcuts)
3. No explicit `@testable import` in production code; test files use `@testable import Speech2Text`

**No path aliases used** — all imports are module-level.

## Error Handling

**Pattern — enum errors with `LocalizedError`:**
```swift
enum LLMRewriteError: LocalizedError, Equatable {
    case modelLoadFailed
    case modelTooLargeForDevice
    case generationFailed
    case cancelled
    var errorDescription: String? { ... }
}
```

**Pattern — `guard` for early exit:**
- Used extensively for state guards: `guard state == .recording else { return }`
- Used for permission checks and nil-unwrap: `guard !trimmedOriginal.isEmpty else { return ... }`

**Pattern — typed catch chains:**
```swift
} catch is CancellationError {
    throw LLMRewriteError.cancelled
} catch let rewriteError as LLMRewriteError {
    throw rewriteError
} catch {
    throw LLMRewriteError.modelLoadFailed
}
```

**Pattern — silent failure with `NSLog`:**
- Non-critical persistence failures are logged and swallowed rather than surfaced to the UI:
  ```swift
  } catch {
      NSLog("Speech2Text: failed to persist trigger preset: \(error.localizedDescription)")
  }
  ```
- Use `NSLog` (not `print` or `os_log`) for all diagnostic output
- All `NSLog` messages are prefixed with `"Speech2Text: "` or a subsystem name like `"HotkeyService: "`

**Pattern — guard on session ID to prevent stale async results:**
```swift
guard isCurrentSession(sessionID) else { return }
```
This guard appears repeatedly throughout async flows to cancel stale session results after interruption.

## Logging

**Framework:** `NSLog` only (no `os.Logger`, no `print`)

**Patterns:**
- All log messages include context prefix: `"HotkeyService: shortcut fired via KeyboardShortcuts"`
- Diagnostic logs use present-tense active voice: `"HotkeyService: listening via KeyboardShortcuts"`
- Error logs from ShellPreferences include `error.localizedDescription`

## Comments

**When to Comment:**
- `// MARK: -` used to divide every type into clearly named sections
- Inline comments explain non-obvious guard conditions and design decisions:
  ```swift
  // Require all permissions to be granted, but do NOT require setup to be
  // "finalized" (hasCompletedInitialSetup). The finalize step is an
  // onboarding UX gate, not a runtime safety requirement.
  ```
- Comments on enum cases document recent additions with brief labels: `// NEW`, `// EXTENDED`, `// NEW:`
- Protocol declarations include a doc comment on their intent

**MARK structure pattern used in most files:**
```swift
// MARK: - PublicTypeName

// MARK: - ProtocolName

// MARK: - Public API

// MARK: - Private implementation

// MARK: - Helpers
```

## Module Design

**Service pattern:**
- Each functional area is a separate type in its own file
- Shared instances via `static let shared`; test instances via DI through `init`
- All production dependencies are protocol-typed to allow test doubles

**ObservableObject pattern:**
- Stores conforming to `ObservableObject` use `@Published private(set) var` for state that views observe
- State mutation happens only via explicit public methods (never direct property assignment from outside)

**`@Published` persistence pattern (ShellPreferences):**
```swift
@Published var rewriteModelTier: RewriteModelTier {
    didSet {
        persistIfNeeded {
            defaults.set(rewriteModelTier.rawValue, forKey: Keys.rewriteModelTier)
        }
    }
}
```
- `persistIfNeeded` suppresses disk writes during a `reset()` batch to avoid partial state
- `withPersistenceSuspended` wraps multi-property resets

**Enum-as-namespace pattern:**
- Pure logic with no instance state uses a caseless enum: `enum IntentDetector { static func detect(...) }`
- This prevents instantiation and groups related pure functions

---

*Convention analysis: 2026-03-22*
