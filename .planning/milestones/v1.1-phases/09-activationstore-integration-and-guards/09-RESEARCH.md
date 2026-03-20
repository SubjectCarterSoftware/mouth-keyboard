# Phase 9: ActivationStore Integration and Guards - Research

**Researched:** 2026-03-19
**Domain:** Swift/SwiftUI — ActivationStore wiring, RecordingState extension, pill UI, menu integration
**Confidence:** HIGH

## Summary

Phase 9 is a pure wiring phase. Every piece it needs already exists and is tested: `IntentDetector.detect()`, `LLMRewriting` protocol, `LLMRewriteService`, `ClipboardService`, `scheduleDismissToIdle()`, and the `arm()`/`finish()`/`finalizeSession()` flow. The work is adding two new `RecordingState` cases, inserting a branch inside `finalizeSession()`, extending `ActivationStore.init()` with an `llmRewriteService` parameter, adding `lastConvertedTranscription` storage, threading `convertModes` through `ShellPreferences`, extending `RecordingPillView` and `RecordingPillPanel` for `.converting`, and adding the new menu item to `StatusMenuView` and `Speech2TextApp`.

No new dependencies are introduced. All logic runs inside existing concurrency contexts. The only design decision left to Claude is the exact `RecordingState.success` shape extension for the `converted` flag (the CONTEXT.md locks `converted: Bool` as a flag, leaving the enum shape to Claude's discretion).

**Primary recommendation:** Extend `.success` by adding `converted: Bool` to the existing associated value tuple (`success(text: String, pasted: Bool, converted: Bool)`) — this touches the fewest switch statements because the existing `case .success(_, let pasted)` pattern in `RecordingPillView` and `AppDelegate` can be extended with `let converted` in-place with no structural refactor.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**RecordingState: new .converting case**
- Add `.converting` (no associated value) to `RecordingState` alongside `.idle`, `.recording`, `.processing`, `.success`, `.failure`
- `.converting` is treated as non-terminal, same as `.processing` — `arm()` blocks new recordings while `.converting` is active
- Pill renders a pulsing/animated indicator during `.converting` (visually distinct from the static `.processing` indicator)
- Pill stays the same physical size as `.processing` — no layout shift during transition

**RecordingState: success with conversion flag**
- Extend `.success` to carry a `converted: Bool` flag (Claude's discretion on exact shape)
- Pill copy: `converted && pasted` → "Converted & Pasted"; `converted && !pasted` → "Converted"; `!converted && pasted` → "Pasted" (existing); `!converted && !pasted` → "Copied" (existing)
- Sound: `playSuccess()` (Glass) — same as plain transcription success

**350-word limit alert**
- Add `.wordLimitExceeded` to `RecordingState.FailureReason` — reuses the `.failure()` path
- Pill copy: "Input exceeds AI limit", orange color treatment
- Auto-dismiss: 2 seconds (same as other failures)
- Sound: `playFailure()` (Basso)
- Raw transcript is still copied to clipboard before the alert state is set

**LLM failure fallback**
- Any `LLMRewriteService.rewrite()` throw silently falls back: raw transcript copied to clipboard, state transitions to `.success(converted: false)`
- No error copy visible to the user — the raw transcript delivery is the silent fallback

**lastTranscription / lastConvertedTranscription**
- `lastTranscription` (existing) continues to store the raw Whisper output — "Copy Last Transcription" is unchanged
- Add `lastConvertedTranscription: String?` to `ActivationStore` — stores the LLM output after a successful conversion
- New menu item: "Copy Last AI Converted Transcription" — calls `clipboardService.writeToClipboard(lastConvertedTranscription)` when non-nil

**IntentDetector call site**
- `IntentDetector.detect()` is called immediately after `trimmed` is produced, before any clipboard write
- Modes passed: `preferences.convertModes` (new `ShellPreferences` property, defaults to `ConvertMode.allBuiltIns` — all 6 non-passthrough cases)
- Phase 10 adds UI to modify `preferences.convertModes`; Phase 9 adds the storage with the default

**LLMRewriteService injection**
- Add `llmRewriteService: any LLMRewriting` parameter to `ActivationStore.init()`, defaulting to `LLMRewriteService.shared`
- Mirrors the existing `whisperService: any WhisperTranscribing` pattern exactly

**Unit test coverage**
- Happy path only: trigger detected → LLM call → `.converting` → `.converted` state; passthrough path unchanged
- Use injected mock `LLMRewriting` (same DI seam as production)
- Failure/guard paths (350-word gate, LLM throw fallback) verified manually, not in unit tests

### Claude's Discretion
- Exact `RecordingState.success` shape extension (`converted: Bool` flag vs new case) — whichever requires less switch-statement churn across the codebase
- Pill animation implementation details (pulse timing, opacity range)
- Orange color value for `.wordLimitExceeded` pill rendering
- `ConvertMode.allBuiltIns` computed property name/location

### Deferred Ideas (OUT OF SCOPE)
- Custom mode editing UI — Phase 10 (Settings Panel)
- Per-mode activation phrase customization — Phase 10
- "Copy Last AI Converted Transcription" persistence across app restarts — not requested, out of scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LLM-02 | The no-trigger dictation path is completely unchanged — plain transcriptions still copy raw text to clipboard | Passthrough branch: when `intent.mode == .passthrough`, existing clipboard write and `.success(converted: false)` path is followed with zero deviation from current behavior |
| GUARD-01 | When a conversion body exceeds 350 words, the pill flashes an orange alert ("Input exceeds AI limit") before copying the raw transcript to clipboard | Implement word-count check on `intent.strippedBody` before the LLM call; use `.failure(reason: .wordLimitExceeded)` with raw-transcript clipboard write first, then 2s auto-dismiss |
| UX-01 | User sees a loading indicator in the pill while LLM conversion is in progress (distinct from the normal transcription processing state) | `.converting` case added to `RecordingState`; `RecordingPillView` renders a distinct animation; `RecordingPillPanel.panelSize()` maps `.converting` to `defaultSize` (160×44) same as `.processing` |
</phase_requirements>

## Standard Stack

This phase introduces no new dependencies. All tools are already in the project.

### Core (Already Present)
| Type | File | Version/Status |
|------|------|----------------|
| `LLMRewriting` protocol | `Speech2Text/Conversion/LLMRewriteService.swift` | Production-ready |
| `LLMRewriteService.shared` | Same file | Default injection target |
| `IntentDetector.detect(transcript:modes:)` | `Speech2Text/Conversion/IntentDetector.swift` | Production-ready |
| `ConvertIntent` | `Speech2Text/Conversion/ConvertIntent.swift` | `mode`, `strippedBody`, `originalTranscript` |
| `ConvertMode` | `Speech2Text/Conversion/ConvertMode.swift` | 7 cases including `.passthrough` |
| `ClipboardService.writeToClipboard(_:)` | `Speech2Text/Clipboard/ClipboardService.swift` | Existing, reused |
| `scheduleDismissToIdle(afterNanoseconds:sessionID:)` | `ActivationStore` | Existing, reused for word-limit dismiss |

## Architecture Patterns

### Recommended Change Set (by file)

```
Speech2Text/
├── Activation/
│   ├── RecordingState.swift              — add .converting, .wordLimitExceeded, extend .success
│   └── ActivationStore.swift             — inject llmRewriteService, branch in finalizeSession()
├── Conversion/
│   └── ConvertMode.swift                 — add allBuiltIns computed property
├── Persistence/
│   └── ShellPreferences.swift            — add convertModes: [ConvertMode] with UserDefaults persistence
├── Shell/
│   ├── RecordingPillView.swift           — add .converting case, extend successContent, failureContent
│   ├── RecordingPillPanel.swift          — add .converting to panelSize() switch
│   └── StatusMenuView.swift              — add lastConvertedTranscription parameter + menu item
└── App/
    └── Speech2TextApp.swift              — thread lastConvertedTranscription + copyLastConvertedTranscription
```

### Pattern 1: RecordingState Extension

Add `.converting` as a non-terminal, non-interactive state alongside `.processing`. Extend `.success` with `converted: Bool` in the tuple. Add `.wordLimitExceeded` to `FailureReason`.

```swift
// RecordingState.swift
enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case converting                                      // NEW — non-terminal
    case success(text: String, pasted: Bool, converted: Bool)  // EXTENDED
    case failure(reason: FailureReason)

    enum FailureReason: Equatable {
        case noSpeechDetected
        case microphonePermissionDenied
        case microphoneUnavailable
        case selectedMicrophoneUnavailable
        case selectedMicrophoneDisconnected
        case modelError(String)
        case silenceTimeout
        case wordLimitExceeded                           // NEW
    }

    var isTerminal: Bool {
        switch self {
        case .success, .failure:
            return true
        case .idle, .recording, .processing, .converting: // EXTENDED
            return false
        }
    }
}
```

**Impact on existing switch sites:**

- `ActivationStore.arm()`: `guard state == .idle || state.isTerminal` — `.converting` is non-terminal so it already blocks new recordings (zero change needed in guard logic; `.converting` falls through the `isTerminal` check correctly).
- `ActivationStore.cancelCurrentSession()`: `guard state == .recording || state == .processing` — `.converting` is NOT added here by design; LLM inference in progress should not be cancellable by the user (the session is already audio-complete).
- `ActivationStore.scheduleDismissToIdle()`: `case .success, .failure` pattern already covers dismiss; `.converting` should not dismiss (correct, it's non-terminal).
- `AppDelegate.stateObservation` sink: add `case .converting:` → call `onConvertingStarted()` (same pattern as `onProcessingStarted()`).
- `AppDelegate.updateMenuBarIcon()`: add `.converting` case → use `"ellipsis.circle"` (same as processing) or a different symbol.
- `RecordingPillPanel.panelSize()`: add `.converting` → `RecordingPillPanel.defaultSize` (160×44).
- `StatusMenuView.canCancelSession`: `recordingState == .recording || recordingState == .processing` — decide whether `.converting` should show Cancel. Decision: No (audio is done; fallback will handle). Add `.converting` to `recoveryStatusText` switch.
- `RecordingPillView.body`: add `case .converting:` branch.
- `ActivationStoreTests.makeStore()` factory: no change needed (`.success` shape change requires updating all `.success(text:, pasted:)` patterns in tests to include `converted:`).

### Pattern 2: ActivationStore DI Extension

Mirror the `whisperService` injection pattern exactly:

```swift
// ActivationStore.swift
static let shared = ActivationStore(
    preferences: .shared,
    readinessProvider: ReadinessStore.shared,
    whisperService: WhisperService.shared,
    llmRewriteService: LLMRewriteService.shared,   // NEW
    clipboardService: ClipboardService(),
    pasteService: PasteService(),
    bufferAccumulator: AudioBufferAccumulator(),
    resetSessionMonitoring: {}
)

// stored property
private let llmRewriteService: any LLMRewriting   // NEW

// init parameter (after whisperService)
llmRewriteService: any LLMRewriting = LLMRewriteService.shared,
```

The `convenience init(preferences:readinessStore:)` does NOT need the new param (it calls the designated init which provides the default).

### Pattern 3: finalizeSession() Branch

The branch inserts after `trimmed` is produced and the empty-check passes. The full annotated sequence:

```swift
// After: guard !trimmed.isEmpty else { throw TranscriptionError.noSpeechDetected }
// Before: let didPaste = pasteOnCompletion

let intent = IntentDetector.detect(transcript: trimmed, modes: preferences.convertModes)

if intent.mode == .passthrough {
    // --- Passthrough path (LLM-02: completely unchanged behavior) ---
    let didPaste = pasteOnCompletion
    pasteOnCompletion = false
    lastTranscription = trimmed
    if didPaste {
        pasteService.paste(text: trimmed)
    } else {
        clipboardService.writeToClipboard(trimmed)
    }
    state = .success(text: trimmed, pasted: didPaste, converted: false)
    soundPlayer.playSuccess()
    scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
} else {
    // --- Conversion path ---
    let wordCount = intent.strippedBody
        .split(separator: " ", omittingEmptySubsequences: true).count

    // GUARD-01: 350-word gate
    guard wordCount <= 350 else {
        guard isCurrentSession(sessionID) else { return }
        clipboardService.writeToClipboard(trimmed)        // raw first
        lastTranscription = trimmed
        pasteOnCompletion = false
        let failureSessionID = activeSessionID
        state = .failure(reason: .wordLimitExceeded)
        soundPlayer.playFailure()
        scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: failureSessionID)
        return
    }

    // Transition to converting state
    guard isCurrentSession(sessionID) else { return }
    pasteOnCompletion = false                             // paste not supported for conversions
    state = .converting

    // LLM call
    let rewritten: String
    do {
        rewritten = try await llmRewriteService.rewrite(
            body: intent.strippedBody,
            mode: intent.mode
        )
    } catch {
        // Silent fallback (GUARD-02 contract, completed in Phase 8)
        guard isCurrentSession(sessionID) else { return }
        clipboardService.writeToClipboard(trimmed)
        lastTranscription = trimmed
        state = .success(text: trimmed, pasted: false, converted: false)
        soundPlayer.playSuccess()
        scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
        return
    }

    guard isCurrentSession(sessionID) else { return }
    clipboardService.writeToClipboard(rewritten)
    lastTranscription = trimmed                           // raw always stored
    lastConvertedTranscription = rewritten                // NEW
    state = .success(text: rewritten, pasted: false, converted: true)
    soundPlayer.playSuccess()
    scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
}
```

**Critical detail:** `pasteOnCompletion` is set to `false` before the conversion path because LLM output cannot use paste (paste was initiated before intent detection; the conversion result goes to clipboard only).

### Pattern 4: ShellPreferences — convertModes

`ShellPreferences` uses `UserDefaults` with manually-coded `@Published + didSet` persistence (NOT `@AppStorage` — the entire class uses a named suite). Follow the same pattern for `convertModes`:

```swift
// Keys
static let convertModes = "convertModes"

// Property
@Published var convertModes: [ConvertMode] {
    didSet {
        persistIfNeeded {
            let rawValues = convertModes.map(\.rawValue)
            defaults.set(rawValues, forKey: Keys.convertModes)
        }
    }
}

// In init:
if let stored = userDefaults.stringArray(forKey: Keys.convertModes) {
    let decoded = stored.compactMap(ConvertMode.init(rawValue:))
    convertModes = decoded.isEmpty ? ConvertMode.allBuiltIns : decoded
} else {
    convertModes = ConvertMode.allBuiltIns
}
```

`ConvertMode.allBuiltIns` is a static computed property on `ConvertMode`:

```swift
static var allBuiltIns: [ConvertMode] {
    [.cleanEnglish, .email, .slack, .teams, .actionItems, .aiPrompt]
    // excludes .passthrough
}
```

Also add `Keys.convertModes` removal in `ShellPreferences.reset()`.

### Pattern 5: RecordingPillView — .converting Case

The `.processing` state shows 3 white pulsing circles (easeInOut, 0.8s, staggered 0.2s delay). The `.converting` case must be **visually distinct**. Recommended: use a "shimmer" or different animation — e.g., a single wide pill indicator or differently colored dots (e.g., blue/purple tones to suggest AI activity), or a faster pulse rate.

The simplest distinct approach matching the spec's "slow pulse or shimmer": use the same dot structure but with a blue tint and a slower oscillation, or a horizontally sliding glow. Decision is Claude's, but the animation must differ perceptibly from `.processing`.

```swift
// In body switch:
case .converting:
    convertingContent

// convertingContent: same 160×44 frame as processingContent (no layout shift)
// Uses different animation timing or color from processingContent
```

For `.wordLimitExceeded` in `failureContent`:

```swift
// In failureContent, the background is currently .red.opacity(0.8) for all failures.
// For .wordLimitExceeded: use Color.orange.opacity(0.85) background
// Text: "Input exceeds AI limit"
// The existing failureContent already uses per-reason text; add the color variation there.
```

Implementation options for per-reason background color:
- Either pass the color from `failureMessage` (restructure to return `(String, Color)`)
- Or add a separate `failureBackground(for:) -> Color` helper

### Pattern 6: StatusMenuView Menu Item

`StatusMenuView` is a SwiftUI `View` that receives its data as let properties + closures. Add:

```swift
// New parameter
let lastConvertedTranscription: String?
let copyLastConvertedTranscription: () -> Void

// New menu item (after the existing "Copy Last Transcription" button):
Button("Copy Last AI Converted Transcription",
       action: copyLastConvertedTranscription)
    .disabled(lastConvertedTranscription == nil)
    .accessibilityIdentifier("statusMenu.copyLastConvertedTranscription")
```

Wire in `Speech2TextApp.body`:
```swift
StatusMenuView(
    ...
    lastConvertedTranscription: activationStore.lastConvertedTranscription,
    copyLastConvertedTranscription: { activationStore.copyLastConvertedTranscription() },
    ...
)
```

Add `copyLastConvertedTranscription()` method on `ActivationStore` mirroring `copyLastTranscription()`.

### Anti-Patterns to Avoid

- **Cancelling LLM mid-flight on session invalidation:** The `isCurrentSession(sessionID)` check after `await llmRewriteService.rewrite(...)` returns handles stale sessions without needing to cancel the LLM task. Do NOT add a separate cancellation hook into `LLMRewriteService` for this phase — the existing session staleness guard is sufficient.
- **Running LLM on @MainActor:** `ActivationStore.finalizeSession()` is an async method called from a `Task` — it already suspends off @MainActor correctly. `LLMRewriteService` is an actor; the `rewrite(body:mode:)` call will hop to the actor automatically. No explicit `Task.detached` is needed.
- **Checking `Task.isCancelled` instead of `isCurrentSession`:** The existing pattern in `finalizeSession()` uses `isCurrentSession(sessionID)` as the staleness gate. Continue using this pattern after the LLM `await` returns.
- **Setting `pasteOnCompletion = false` after intent detection but forgetting in the guard paths:** Every early-return path in the conversion branch must reset `pasteOnCompletion = false`.
- **Word count on `originalTranscript` instead of `strippedBody`:** The trigger phrase itself adds words. Count words in `intent.strippedBody`, not `trimmed`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| LLM inference | Custom model runner | `LLMRewriteService.rewrite()` | Already actor-isolated, serialized, cancellation-safe |
| Intent detection | Manual string prefix scan | `IntentDetector.detect()` | Already handles leading/trailing, multi-candidate, strip-back |
| Dismiss timer | Custom `DispatchQueue.asyncAfter` | `scheduleDismissToIdle(afterNanoseconds:sessionID:)` | Session-aware cancellation built in |
| Clipboard writes | NSPasteboard directly | `ClipboardService.writeToClipboard()` | Existing mock seam in tests |
| UserDefaults persistence | Manual `set`/`synchronize` | Existing `ShellPreferences` `persistIfNeeded` pattern | Handles suspension correctly |

## Common Pitfalls

### Pitfall 1: `.success` Pattern Exhaustiveness Breaks Compile
**What goes wrong:** Adding `converted: Bool` to `.success(text:pasted:)` changes the tuple shape; every `case .success(let text, let pasted)` pattern becomes a compile error.
**Why it happens:** Swift's pattern matching is structurally typed — adding a third tuple element requires all match sites to be updated.
**How to avoid:** Search all `.swift` files for `case .success` before writing a line of implementation. Update ALL sites atomically in one task.
**Files affected:** `ActivationStore.swift` (success path), `RecordingPillView.swift` (successContent), `AppDelegate.swift` (stateObservation sink + updateMenuBarIcon), `ActivationStoreTests.swift` (multiple test assertions).

### Pitfall 2: `.converting` Missing from Switch Exhaustiveness
**What goes wrong:** Every exhaustive switch on `RecordingState` must handle `.converting`. The compiler will catch this, but it's easy to miss `StatusMenuView.recoveryStatusText`, `StatusMenuView.canCancelSession`, `AppDelegate.updateMenuBarIcon()`, and `RecordingPillPanel.panelSize()`.
**How to avoid:** After adding `.converting`, compile immediately and fix all exhaustiveness errors before proceeding.

### Pitfall 3: Word Count Off-By-One (Trigger Phrase Included)
**What goes wrong:** Counting words in `trimmed` (the full transcript including the trigger phrase) instead of `intent.strippedBody` makes the word limit fire earlier than expected for trigger-initiated sessions.
**How to avoid:** Apply the 350-word count to `intent.strippedBody` only.

### Pitfall 4: `pasteOnCompletion` Leaked Into Conversion Path
**What goes wrong:** If a user activates with `armAndPaste()`, then dictates a trigger phrase, `pasteOnCompletion` is `true` when the conversion branch runs. The LLM output will not be pasted (paste service is not wired for conversion), but `pasteOnCompletion` must be explicitly reset to `false` before any return path.
**How to avoid:** Set `pasteOnCompletion = false` as the first line of the conversion branch, before any guard or return.

### Pitfall 5: `lastConvertedTranscription` Not Reset on Passthrough
**What goes wrong:** If the user does a plain dictation after a conversion session, `lastConvertedTranscription` still holds the previous session's LLM output. The menu item would remain enabled but give stale output.
**Decision:** Per CONTEXT.md, `lastConvertedTranscription` is only updated on a successful conversion. It is never explicitly cleared (nil'd) on passthrough sessions. This is intentional — "Copy Last AI Converted Transcription" gives the last conversion output regardless of intervening plain dictations. This matches the `lastTranscription` pattern exactly.

### Pitfall 6: `cancelCurrentSession()` Must Not Add `.converting`
**What goes wrong:** `cancelCurrentSession()` currently guards `state == .recording || state == .processing`. If `.converting` is added to this guard, clicking Cancel in the menu during an LLM call would drop the session without delivering any output.
**How to avoid:** Do NOT add `.converting` to the `cancelCurrentSession()` guard. LLM inference is best-effort; the fallback will handle any failure.

### Pitfall 7: AppDelegate State Switch Missing `.converting`
**What goes wrong:** The `stateObservation` sink in `AppDelegate` is a non-exhaustive `switch` that dispatches to handlers. Adding `.converting` without a handler causes it to fall into the default path (none currently exists — this is a `switch` with explicit cases only, no `default`).
**How to avoid:** Add `case .converting: self.onConvertingStarted()` and implement `onConvertingStarted()` to stop audio capture (same as `onProcessingStarted()`; audio is already stopped when `.processing` transitions to `.converting`). Actually: `.processing` already stopped capture; `.converting` follows `.processing`, so audio is already stopped. `onConvertingStarted()` only needs to update the menu bar icon.

## Code Examples

### Mock LLMRewriting for ActivationStoreTests

```swift
// Mirrors ActivationStoreMockTranscriber pattern
final class MockLLMRewriter: LLMRewriting, @unchecked Sendable {
    enum MockResult {
        case success(String)
        case failure(Error)
    }
    private let result: MockResult

    init(result: MockResult) { self.result = result }

    func rewrite(body: String, mode: ConvertMode) async throws -> String {
        switch result {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}
```

### makeStore() Extension for Phase 9 Tests

```swift
private func makeStore(
    permissionsAuthorized: Bool,
    transcriber: (any WhisperTranscribing)? = nil,
    llmRewriter: (any LLMRewriting)? = nil,    // NEW
    clipboard: ClipboardService? = nil,
    bufferAccumulator: AudioBufferAccumulator? = nil,
    resetSessionMonitoring: (@MainActor () -> Void)? = nil
) -> ActivationStore {
    let suiteName = "ActivationStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)

    return ActivationStore(
        preferences: ShellPreferences(userDefaults: defaults),
        readinessProvider: StubReadinessProvider(permissionsAuthorized: permissionsAuthorized),
        whisperService: transcriber ?? ActivationStoreMockTranscriber(result: .success("")),
        llmRewriteService: llmRewriter ?? MockLLMRewriter(result: .failure(LLMRewriteError.cancelled)),
        clipboardService: clipboard ?? ActivationStoreMockClipboard(),
        bufferAccumulator: bufferAccumulator ?? StubBufferAccumulator(),
        resetSessionMonitoring: resetSessionMonitoring ?? {}
    )
}
```

### Happy Path Test (Phase 9 Required Coverage)

```swift
func test_trigger_dictation_produces_converted_clipboard_output() async throws {
    // Transcriber returns "convert to email Please schedule a meeting for Friday"
    // LLM rewriter returns the formatted email
    let mockTranscriber = ActivationStoreMockTranscriber(
        result: .success("convert to email Please schedule a meeting for Friday")
    )
    let mockRewriter = MockLLMRewriter(result: .success("Subject: Meeting Request\n\nPlease schedule..."))
    let mockClipboard = ActivationStoreMockClipboard()
    let store = makeStore(
        permissionsAuthorized: true,
        transcriber: mockTranscriber,
        llmRewriter: mockRewriter,
        clipboard: mockClipboard
    )
    // ShellPreferences.convertModes must include .email (default does)
    store.arm()
    store.finish()

    try await Task.sleep(nanoseconds: 300_000_000)

    XCTAssertEqual(mockClipboard.lastWrittenText, "Subject: Meeting Request\n\nPlease schedule...")
    XCTAssertEqual(store.lastConvertedTranscription, "Subject: Meeting Request\n\nPlease schedule...")
    if case .success(_, _, let converted) = store.state {
        XCTAssertTrue(converted)
    } else {
        XCTFail("Expected .success state, got \(store.state)")
    }
}

func test_passthrough_dictation_is_completely_unchanged() async throws {
    let mockTranscriber = ActivationStoreMockTranscriber(result: .success("Hello world"))
    let mockClipboard = ActivationStoreMockClipboard()
    let store = makeStore(
        permissionsAuthorized: true,
        transcriber: mockTranscriber,
        clipboard: mockClipboard
    )
    store.arm()
    store.finish()

    try await Task.sleep(nanoseconds: 200_000_000)

    XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
    XCTAssertNil(store.lastConvertedTranscription)
    if case .success(_, _, let converted) = store.state {
        XCTAssertFalse(converted)
    } else {
        XCTFail("Expected .success state, got \(store.state)")
    }
}
```

### All Existing Tests: .success Pattern Fix

Every existing `ActivationStoreTests` assertion on `.success` must add the `converted` label:

```swift
// Before:
if case .success(let text, _) = store.state { ... }
// After:
if case .success(let text, _, _) = store.state { ... }

// Before:
XCTAssertEqual(store.state, .success(text: "...", pasted: false))
// After:
XCTAssertEqual(store.state, .success(text: "...", pasted: false, converted: false))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| N/A | LLM branch inserted in existing async finalizeSession() | Phase 9 | Zero new concurrency primitives needed |
| N/A | `.converting` as non-terminal state | Phase 9 | Blocks arm() naturally via isTerminal |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (native) |
| Config file | Speech2Text.xcodeproj (Xcode scheme) |
| Quick run command | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/ActivationStoreTests -destination "platform=macOS" 2>&1 | tail -20` |
| Full suite command | `xcodebuild test -scheme Speech2Text -destination "platform=macOS" 2>&1 | tail -40` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LLM-02 | Plain dictation copies raw text unchanged | unit | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/ActivationStoreTests/test_passthrough_dictation_is_completely_unchanged` | Wave 0 |
| UX-01 | Trigger dictation transitions through .converting | unit | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/ActivationStoreTests/test_trigger_dictation_produces_converted_clipboard_output` | Wave 0 |
| GUARD-01 | 350-word gate fires before LLM call | manual-only | N/A — per CONTEXT.md decision, guard paths verified manually | N/A |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/ActivationStoreTests -destination "platform=macOS" 2>&1 | tail -20`
- **Per wave merge:** Full suite: `xcodebuild test -scheme Speech2Text -destination "platform=macOS" 2>&1 | tail -40`
- **Phase gate:** Full suite green before `$gsd-verify-work`

### Wave 0 Gaps
- [ ] `Speech2TextTests/ActivationStoreTests.swift` — add Phase 9 test methods (happy path + passthrough). File exists; needs new test methods and mock type added.
- [ ] `MockLLMRewriter` stub — needs to be added to `ActivationStoreTests.swift` alongside existing mock types.
- [ ] All existing `.success(text:pasted:)` pattern matches in `ActivationStoreTests.swift` need `converted:` label added (compile gate).

## Open Questions

1. **`.converting` in `StatusMenuView.canCancelSession`**
   - What we know: cancel is currently shown for `.recording || .processing`. `.converting` is non-terminal but audio is already stopped.
   - What's unclear: Should Cancel be visible during `.converting`? (canceling would interrupt the LLM call, leaving the user with no output)
   - Recommendation: Do NOT show Cancel during `.converting`. The LLM failure fallback guarantees an output. Keeping Cancel away from `.converting` avoids UX confusion.

2. **Menu bar icon during `.converting`**
   - What we know: `AppDelegate.updateMenuBarIcon()` switches on state. `.converting` needs a case.
   - Recommendation: Use `"ellipsis.circle"` (same as processing) — the pill is the primary UX signal; the menu bar icon is secondary.

3. **`pasteOnCompletion` and conversion path**
   - What we know: `pasteService.paste(text:)` is only called on the passthrough path. If the user activated with `armAndPaste()` and said a trigger phrase, the paste service is NOT invoked on the conversion path.
   - Recommendation: Reset `pasteOnCompletion = false` at the start of the conversion branch; deliver LLM output to clipboard only (no paste for conversions in Phase 9).

## Sources

### Primary (HIGH confidence)
- Direct codebase read: `ActivationStore.swift`, `RecordingState.swift`, `LLMRewriteService.swift`, `IntentDetector.swift`, `ConvertMode.swift`, `ConvertIntent.swift`, `RecordingPillView.swift`, `RecordingPillPanel.swift`, `StatusMenuView.swift`, `Speech2TextApp.swift`, `AppDelegate.swift`, `ShellPreferences.swift`, `ActivationStoreTests.swift`, `LLMRewriteServiceTests.swift`
- No external library research required — this phase adds no new dependencies

### Secondary (MEDIUM confidence)
- N/A — all findings derived from direct source inspection

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies already present in codebase, directly read
- Architecture: HIGH — wiring patterns derived from existing code; extension points clearly identified
- Pitfalls: HIGH — derived from exhaustive switch analysis across all 14 source files
- Test patterns: HIGH — existing `ActivationStoreTests` mock infrastructure directly inspected

**Research date:** 2026-03-19
**Valid until:** Stable for duration of Phase 9 (no external dependencies, all findings from source code)
