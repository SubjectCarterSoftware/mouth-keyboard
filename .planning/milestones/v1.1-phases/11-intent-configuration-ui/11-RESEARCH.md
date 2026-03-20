# Phase 11: Intent Configuration UI - Research

**Researched:** 2026-03-19
**Domain:** SwiftUI settings panel, JSON persistence (App Support), LLM-powered intent authoring
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Persistent `UserIntentStore` as JSON in App Support directory
- Stores per-mode overrides: system prompt, generated phrase patterns (50), mode name
- Stores custom modes: mode name, system prompt, 50 generated phrase patterns, derived keyword signal
- `IntentCatalog` and `ConvertMode` read from store first, fall back to hardcoded defaults
- No `ConvertMode` enum changes required — custom intents are represented as data, not Swift types
- One row per mode (built-in + custom): mode name + truncated system prompt preview
- "Add Mode" button opens create view; tap any existing row opens edit view
- Mode name field: editable, but auto-suggested as ghost text while user types system prompt (debounced ~1s, local LLM name-generation prompt)
- System prompt text area: freeform, primary user input. Placeholder: "Describe what this mode should do with your dictated text..."
- "Reset to default" button: built-in modes only — wipes overrides, restores hardcoded values
- "Delete" button: custom modes only
- Example input pre-filled with "had a call with the team today we covered the roadmap and need to follow up with Sarah by Friday". Fully editable. Never saved/persisted.
- Output panel: LLM output using current system prompt applied to example input. Updates automatically (debounced ~2s) or on manual trigger.
- Once system prompt settles (~2s after last keystroke), silently generate 50 phrase patterns — no spinner, no button, no UI mention
- Phrase trigger tester: collapsed by default under "Test trigger phrase" disclosure control; shows match result + confidence score
- No new `ConvertMode` enum cases
- No reordering or enabling/disabling individual modes
- No import/export of intent configs

### Claude's Discretion
- Exact SwiftUI layout approach (HStack split, NavigationSplitView, sheet, etc.)
- Debounce implementation mechanism
- LLM prompt templates for name generation and phrase pattern generation
- Persistence format details within JSON store
- Error handling for LLM generation failures in settings context
- Whether mode name suggestion uses streaming or waits for full completion

### Deferred Ideas (OUT OF SCOPE)
- Reordering modes
- Enabling/disabling individual modes
- Import/export of intent configs
- Sharing custom intents between users
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONFIG-01 | User can view all modes (built-in + custom) in a settings panel with name and system prompt preview | `SetupWindowView` is the existing shell; phase adds a new intent list section or tab |
| CONFIG-02 | User can create/edit a mode by writing a system prompt; phrase patterns are generated automatically and stored invisibly | `LLMRewriteService.streamFactory` signature already accepts a custom `instructions` string — new generation tasks reuse same actor |
| CONFIG-03 | Built-in modes are editable with a reset option; custom modes can be deleted | `UserIntentStore` is the override layer; `ConvertMode.defaultSystemPrompt` provides the reset target value |
</phase_requirements>

---

## Summary

Phase 11 adds a settings UI for managing conversion modes without touching the `ConvertMode` enum or `IntentDetector` matching logic. The architecture is an overlay pattern: a new `UserIntentStore` JSON file in App Support acts as a read-before-hardcoded-defaults store. `IntentCatalog` is upgraded to merge store entries with its static definitions, making custom modes first-class without any Swift type changes.

The settings panel lives alongside the existing `SetupWindowView`. The edit surface is a split pane: left side owns the definition (name + system prompt), right side provides a live preview loop. Phrase-pattern generation (50 patterns) runs silently in the background on the same `LLMRewriteService` actor, using a custom `instructions` string — no new LLM infrastructure required.

The critical data-flow insight: `LLMRewriteService.rewrite(body:mode:)` currently reads `mode.defaultSystemPrompt` inside the `streamFactory`. To support user-overridden prompts, `ActivationStore` must resolve the effective system prompt from `UserIntentStore` before calling the service, or `LLMRewriteService` needs a second entry point that accepts an explicit `instructions` string instead of a `ConvertMode`.

**Primary recommendation:** Add a `rewrite(body:instructions:)` overload to `LLMRewriteService` (or promote `instructions` to a first-class parameter on the existing protocol). `ActivationStore` resolves the effective prompt from `UserIntentStore` at call time. This requires zero changes to `ConvertMode`, `IntentDetector`, or `IntentCatalog` beyond the catalog also reading from the store.

---

## Standard Stack

### Core
| Library / API | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| SwiftUI | macOS 13+ | Settings panel UI | Already used throughout the shell |
| Foundation (FileManager, JSONEncoder/Decoder) | macOS 13+ | JSON persistence in App Support | Same pattern as `makePersistentHub()` in `LLMRewriteService` |
| Combine (debounce) | macOS 13+ | Debounced system-prompt-change publisher | Already used in `ShellPreferences` / Combine imports in `ActivationStore` |
| `LLMRewriteService` (existing actor) | project | Name generation + phrase pattern generation | Reuses loaded model; no new infrastructure |

### Supporting
| Library / API | Version | Purpose | When to Use |
|---------------|---------|---------|-------------|
| `DisclosureGroup` (SwiftUI) | macOS 13+ | Collapsible phrase trigger tester | Built-in, zero deps |
| `TextEditor` (SwiftUI) | macOS 13+ | Multi-line system prompt input area | Preferred over `TextField` for freeform long-form text |
| `List` / `NavigationSplitView` (SwiftUI) | macOS 13+ | Intent list + detail split | Standard macOS settings pattern; at planner's discretion |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSON in App Support | UserDefaults | UserDefaults is not designed for arbitrary structured collections; App Support JSON is more appropriate for growable intent arrays |
| Combine `debounce` | `Task.sleep` with cancellation | Both work; Combine debounce integrates cleanly with `@Published` pipeline already used in `ShellPreferences` |
| `NavigationSplitView` | `HSplitView` or sheet | NavigationSplitView gives sidebar + detail for free on macOS; sheet is simpler but loses the live-preview panel; planner's choice |

**Installation:** No new packages required.

---

## Architecture Patterns

### Recommended Project Structure (new files)

```
Speech2Text/Conversion/
├── UserIntentStore.swift        # JSON persistence actor: load/save/observe
├── UserIntentEntry.swift        # Codable struct: per-mode override or custom mode
Speech2Text/Shell/
├── IntentListView.swift         # List of all modes (built-in + custom)
├── IntentEditView.swift         # Split pane: definition (left) + live preview (right)
```

### Pattern 1: UserIntentStore — Actor with JSON Persistence

**What:** A Swift actor (not `@MainActor`) that owns the JSON file in App Support. Provides async load/save, plus a `@Published`-style mechanism (NotificationCenter or a shared `ObservableObject` wrapper on `@MainActor`) so SwiftUI can observe changes.

**When to use:** Any read of custom/overridden intent data; any write after user edits.

**Key decisions from codebase:**
- App Support path pattern already established in `LLMRewriteService.makePersistentHub()`:
  ```swift
  // Source: Speech2Text/Conversion/LLMRewriteService.swift
  let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
  let storeURL = appSupport
      .appendingPathComponent("Speech2Text", isDirectory: true)
      .appendingPathComponent("IntentStore.json")
  ```
- File does not need to exist on first launch — empty store is equivalent to all defaults.

**Codable model:**
```swift
// UserIntentEntry.swift
struct UserIntentEntry: Codable, Identifiable {
    var id: String                   // ConvertMode.rawValue for built-ins; UUID string for custom
    var modeName: String
    var systemPrompt: String
    var phrasePatterns: [String]     // 50 generated patterns; empty until generation completes
    var keywordSignal: String        // derived from LLM generation; empty until generated
    var isBuiltIn: Bool
}
```

### Pattern 2: IntentCatalog Merge (Read-from-Store First)

**What:** `IntentCatalog.all` is currently a static `[IntentDefinition]` array. Phase 11 promotes it to a computed property that merges store entries with hardcoded defaults.

**Current state:**
```swift
// Source: Speech2Text/Conversion/IntentCatalog.swift (line 7-14)
enum IntentCatalog {
    static let all: [IntentDefinition] = [
        emailDefinition, slackDefinition, teamsDefinition,
        actionItemsDefinition, aiPromptDefinition, cleanEnglishDefinition,
    ]
```

**After Phase 11:** `IntentCatalog.effective(store:)` returns overridden definitions for built-ins + custom definitions from the store, merged with the static fallback. `IntentDetector` is unchanged — it already accepts `modes: [ConvertMode]` but actually uses `IntentCatalog.all` internally. The catalog merge must include custom modes so the detector can match them.

**Critical note:** `IntentDetector.scoreZone` calls `IntentCatalog.all.filter { modes.contains($0.mode) }` (line 184). Custom modes use `.passthrough` or a new data-driven route. Since the decision is "no new ConvertMode enum cases", custom intents must map to a stable identifier. The recommended approach: custom intents get a synthetic `ConvertMode`-equivalent identity via a parallel `CustomIntentID` and the detector is extended to accept `[IntentDefinition]` directly rather than `[ConvertMode]`. This is the minimal change path.

**Alternative (simpler):** Make `IntentCatalog.all` a mutable var (or a global actor-isolated property) that `UserIntentStore` updates on save. `IntentDetector` needs no changes.

### Pattern 3: LLMRewriteService — Custom Instructions Overload

**Current signature:**
```swift
// Source: Speech2Text/Conversion/LLMRewriteService.swift (line 29-31)
protocol LLMRewriting: Sendable {
    func rewrite(body: String, mode: ConvertMode) async throws -> String
}
```

The `streamFactory` receives `mode.defaultSystemPrompt` as `instructions` (line 134-138). To support user-overridden prompts at rewrite time, `ActivationStore.finalizeSession()` needs to resolve the effective system prompt before calling `llmRewriteService.rewrite(...)`.

**Recommended change:** Add a second protocol method:
```swift
protocol LLMRewriting: Sendable {
    func rewrite(body: String, mode: ConvertMode) async throws -> String
    func rewrite(body: String, instructions: String) async throws -> String
}
```
`ActivationStore` calls the `instructions:` overload when `UserIntentStore` has an override for `intent.mode`. The existing `rewrite(body:mode:)` implementation delegates to the new overload using `mode.defaultSystemPrompt`.

**Background generation (phrase patterns + name suggestion):** Both also call `rewrite(body:instructions:)` with a specialized generation prompt. They run on the same actor, serialized by `RewriteExecutionGate`.

### Pattern 4: Debounce via Combine

**What:** A `PassthroughSubject<String, Never>` in the edit view model, debounced with `.debounce(for: .seconds(2), scheduler: RunLoop.main)`, drives both phrase-pattern generation and the live preview update.

**Name suggestion** uses a shorter debounce (~1s) on the same subject or a separate subject.

**Existing pattern in codebase:** `ShellPreferences` uses `@Published` + Combine. `ActivationStore` already imports Combine. This is idiomatic for the project.

### Pattern 5: Ghost Text (Name Suggestion)

**What:** A `@State var suggestedName: String = ""` in the edit view, shown as `.foregroundStyle(.secondary)` overlay or placeholder in the name field when the user-typed name is empty or identical to the suggestion.

**Implementation note:** SwiftUI `TextField` does not have a true ghost-text API. The standard pattern on macOS is:
- Show `suggestedName` as `.foregroundStyle(.tertiary)` text layered beneath the real text field using `ZStack`, or
- Set `TextField`'s `prompt` parameter (macOS 13+) to `Text(suggestedName).foregroundStyle(.secondary)`.

The `prompt:` approach is simpler and idiomatic — it appears only when the binding is empty.

### Anti-Patterns to Avoid
- **Blocking MainActor during LLM generation:** Phrase-pattern generation and live preview both call `LLMRewriteService` — these must be `async Task` off the main actor. The existing gate serializes them automatically.
- **Storing example input in persistence:** The live-preview example text is session-only; storing it would cause stale state between sessions.
- **Changing ConvertMode enum:** Decision is locked — custom intents are data, not Swift cases.
- **Calling IntentCatalog.all at detection time with a mutable global:** Use a snapshot approach — copy the effective catalog into `ActivationStore` (or read from `UserIntentStore`) at session-start to avoid race conditions.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Debounced text input | Custom timer invalidation | Combine `.debounce(for:scheduler:)` | Already in project; handles cancellation and threading correctly |
| JSON serialization | Manual string building | `JSONEncoder`/`JSONDecoder` with `Codable` | Already the project pattern (App Support JSON for RewriteModel hub) |
| Async task cancellation in SwiftUI | Manual flag tracking | `Task` stored as `@State` or in ViewModel, cancelled in `onDisappear` | Standard SwiftUI async task lifecycle |
| Disclosure group expand/collapse | Custom accordion view | `DisclosureGroup` | Built into SwiftUI; accessibility handled automatically |

**Key insight:** The project already has actor-based concurrency, Combine-based reactivity, and App Support JSON patterns. Phase 11 composes these — it adds almost no new infrastructure.

---

## Common Pitfalls

### Pitfall 1: RewriteExecutionGate Blocks Settings Preview
**What goes wrong:** The live preview LLM call sits behind `RewriteExecutionGate` alongside production rewrites. If the user has the settings panel open while simultaneously dictating, the gate serializes them — settings preview stalls until the production rewrite finishes.
**Why it happens:** `LLMRewriteService` has a single shared gate. Settings and production rewrites share the same actor instance.
**How to avoid:** Use `LLMRewriteService.shared` for production rewrites. Consider whether settings preview can use the same instance (acceptable stall) or needs a separate `LLMRewriteService()` instance for non-blocking behavior. Separate instance is cleaner but wastes model load. Shared instance with queue is simpler and safe.
**Warning signs:** Live preview never updates while a dictation is in progress.

### Pitfall 2: Phrase Pattern Generation Prompt Format
**What goes wrong:** The LLM generates patterns that include numbered lists, commentary, or Markdown — not clean lowercase strings suitable for `IntentDefinition.phrasePatterns`.
**Why it happens:** Qwen 2.5 1.5B is instruction-tuned and verbose without explicit output constraints.
**How to avoid:** Phrase generation system prompt must explicitly demand: one pattern per line, lowercase, no numbers, no punctuation other than spaces, no commentary. Parse output with `components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(50)`.
**Warning signs:** IntentDetector fails to match user-spoken phrases because stored patterns contain "1. " prefixes or mixed case.

### Pitfall 3: IntentCatalog.all Is a Static Let
**What goes wrong:** Custom modes stored in `UserIntentStore` are never seen by `IntentDetector` because `IntentCatalog.all` is a compile-time constant `static let` array.
**Why it happens:** The current catalog is fully static. `IntentDetector.scoreZone` filters against `IntentCatalog.all` directly (line 184).
**How to avoid:** Either (a) make `IntentCatalog.all` a mutable global-actor-isolated var updated on store save, or (b) add an overload to `IntentDetector.detect(transcript:definitions:)` that accepts `[IntentDefinition]` directly and have `ActivationStore` pass the merged set. Option (b) is safer — no global mutable state.
**Warning signs:** Custom modes never trigger during detection even when the user speaks the trigger phrase.

### Pitfall 4: ConvertMode for Custom Intents
**What goes wrong:** `ConvertIntent.mode` is typed as `ConvertMode` (a closed enum). Custom intents cannot be expressed as a `ConvertMode` value without adding new enum cases (locked out by decision).
**Why it happens:** The entire pipeline from `IntentDetector.detect` through `ActivationStore.finalizeSession` and `LLMRewriteService.rewrite` uses `ConvertMode` as the identity.
**How to avoid:** Two valid approaches:
  - **A (simpler):** Map custom intents to `ConvertMode.passthrough` in the detector result but carry the `instructions` string separately via an extended `ConvertIntent` struct. `ActivationStore` checks if `strippedBody` is non-empty + a custom instructions payload is present, then calls `rewrite(body:instructions:)`.
  - **B (cleaner):** Add `case custom(id: String)` to `ConvertMode` but this violates the locked decision.

  Approach A requires adding an `effectiveInstructions: String?` field to `ConvertIntent`. The planner should pick this approach.
**Warning signs:** Custom intents fall through to passthrough and raw text is copied instead of being rewritten.

### Pitfall 5: Keyword Signal Derivation for Custom Intents
**What goes wrong:** `IntentDefinition.keywordSignal` is used by `IntentDetector` to award a 0.15 score bonus. Custom intents have no hardcoded `keywordSignal` — generating a poor one reduces detection accuracy.
**Why it happens:** The signal is a project-specific concept, not a standard NLP construct.
**How to avoid:** The LLM phrase-pattern generation prompt can also output a single keyword signal on its last line. Alternatively, derive it heuristically from the mode name (lowercase, first significant word). Store the derived signal in `UserIntentEntry.keywordSignal`.

### Pitfall 6: App Support Directory Not Created
**What goes wrong:** `FileManager` write fails because `~/Library/Application Support/Speech2Text/` doesn't exist yet.
**Why it happens:** The directory is only created by `makePersistentHub()` when the model loads — a user who has never triggered a rewrite may not have it.
**How to avoid:** `UserIntentStore` must call `fileManager.createDirectory(at:withIntermediateDirectories:)` before writing, exactly as `makePersistentHub()` does.

---

## Code Examples

Verified patterns from existing codebase:

### App Support Directory Creation (existing pattern)
```swift
// Source: Speech2Text/Conversion/LLMRewriteService.swift (lines 263-276)
private static func makePersistentHub() throws -> HubApi {
    let fileManager = FileManager.default
    let appSupport = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let downloadBase = appSupport
        .appendingPathComponent("Speech2Text", isDirectory: true)
        .appendingPathComponent("RewriteModel", isDirectory: true)
    try fileManager.createDirectory(at: downloadBase, withIntermediateDirectories: true)
    return HubApi(downloadBase: downloadBase)
}
// UserIntentStore follows same pattern, targeting "IntentStore.json"
```

### LLMRewriteService Custom Instructions (existing StreamFactory signature)
```swift
// Source: Speech2Text/Conversion/LLMRewriteService.swift (lines 79-86)
// The streamFactory already accepts an explicit `instructions` string:
typealias StreamFactory =
    @Sendable (
        _ model: RewriteModel,
        _ body: String,
        _ instructions: String,       // <-- custom system prompt goes here
        _ parameters: GenerateParameters
    ) throws -> AsyncThrowingStream<RewriteEvent, Error>
// The existing rewrite(body:mode:) passes mode.defaultSystemPrompt as instructions (line 136).
// A new rewrite(body:instructions:) overload can pass the instructions directly.
```

### Combine Debounce Pattern (for system prompt changes)
```swift
// Pattern used in project (Combine already imported in ActivationStore, ShellPreferences)
import Combine

class IntentEditViewModel: ObservableObject {
    @Published var systemPrompt: String = ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        $systemPrompt
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] prompt in
                self?.triggerPhrasePatternGeneration(for: prompt)
            }
            .store(in: &cancellables)

        $systemPrompt
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] prompt in
                self?.suggestName(for: prompt)
            }
            .store(in: &cancellables)
    }
}
```

### ShellPreferences UserDefaults Pattern (for comparison)
```swift
// Source: Speech2Text/Persistence/ShellPreferences.swift (lines 5-19)
// Pattern: @Published var with didSet persistence. UserIntentStore uses JSON instead of
// UserDefaults because it stores a variable-length array of structured objects.
@Published var convertModes: [ConvertMode] {
    didSet {
        persistIfNeeded {
            let rawValues = self.convertModes.map(\.rawValue)
            self.defaults.set(rawValues, forKey: Keys.convertModes)
        }
    }
}
```

### IntentDetector Modes Parameter (shows where custom intents plug in)
```swift
// Source: Speech2Text/Conversion/IntentDetector.swift (line 8)
static func detect(transcript: String, modes: [ConvertMode]) -> ConvertIntent
// And internally (line 184):
let activeDefs = IntentCatalog.all.filter { modes.contains($0.mode) }
// Custom intents require IntentDetector to accept [IntentDefinition] directly,
// bypassing the IntentCatalog.all.filter step.
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Static `IntentCatalog.all` | Merged catalog (static + store) | Phase 11 | Enables custom intents without enum changes |
| `ConvertMode`-typed rewrite call | `instructions:` overload on `LLMRewriteService` | Phase 11 | Supports user-overridden system prompts |
| No intent management UI | Split-pane intent editor in SetupWindow | Phase 11 | First user-visible intent authoring surface |

**No deprecated approaches in this phase** — Phase 11 extends the existing system without removing anything.

---

## Open Questions

1. **How do custom intents flow through `ConvertMode`-typed APIs without enum changes?**
   - What we know: `ConvertIntent.mode` is `ConvertMode`; `IntentDetector.detect` returns a `ConvertMode`; `ActivationStore` uses `intent.mode` to call `llmRewriteService.rewrite(body:mode:)`.
   - What's unclear: The exact struct shape of `ConvertIntent` for custom modes — either extend `ConvertIntent` with an `effectiveInstructions` payload, or resolve instructions in `ActivationStore` by querying `UserIntentStore`.
   - Recommendation: Extend `ConvertIntent` with `effectiveSystemPrompt: String?`; set it when the detected intent is custom or overridden. `ActivationStore` uses it when non-nil. This requires no `ConvertMode` enum changes and is the minimal-touch path.

2. **Does `IntentDetector` need to understand custom modes by ID?**
   - What we know: `IntentDetector.scoreZone` filters `IntentCatalog.all` by `modes.contains($0.mode)`. Custom modes have no `ConvertMode` case.
   - What's unclear: Whether the detector should treat custom intents as a new `ConvertMode.custom(id:)` or as a data envelope that returns a stable `.passthrough`-adjacent result.
   - Recommendation: Add a `detect(transcript:definitions:)` overload to `IntentDetector` that accepts a pre-merged `[IntentDefinition]` directly. `ActivationStore` constructs the merged list from `UserIntentStore` at session-start. The `ConvertIntent` result carries enough information (mode + effectiveSystemPrompt) to route the rewrite.

3. **Phrase pattern generation prompt — output format contract**
   - What we know: Qwen 2.5 1.5B is a capable instruction-following model at 130 tokens/s.
   - What's unclear: Exact prompt wording needed to reliably get exactly 50 lowercase patterns, one per line, with no commentary.
   - Recommendation: Prototype this prompt during Wave 0 of planning. The phrase-pattern generation is a new LLM task that has not been exercised in this project before. The output format contract affects `UserIntentStore` parsing.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (existing) |
| Config file | Speech2Text.xcodeproj (scheme-based) |
| Quick run command | `xcodebuild test -scheme Speech2Text -destination 'platform=macOS' -testPlan Speech2TextTests 2>&1 \| grep -E "passed\|failed\|error"` |
| Full suite command | `xcodebuild test -scheme Speech2Text -destination 'platform=macOS' 2>&1 \| tail -20` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONFIG-01 | `UserIntentStore` loads/saves JSON in App Support; empty store returns empty overrides | unit | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/UserIntentStoreTests` | ❌ Wave 0 |
| CONFIG-01 | `IntentCatalog.effective(store:)` returns built-in definitions when store is empty | unit | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/IntentCatalogTests` | ❌ Wave 0 |
| CONFIG-01 | `IntentCatalog.effective(store:)` merges store overrides for built-in modes | unit | same file | ❌ Wave 0 |
| CONFIG-01 | `IntentCatalog.effective(store:)` appends custom mode entries from store | unit | same file | ❌ Wave 0 |
| CONFIG-02 | `LLMRewriteService.rewrite(body:instructions:)` passes custom instructions to streamFactory | unit (stub) | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/LLMRewriteServiceTests` | ✅ (extend existing) |
| CONFIG-02 | `ActivationStore.finalizeSession` uses effectiveSystemPrompt from ConvertIntent when non-nil | unit (stub) | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/ActivationStoreTests` | ✅ (extend existing) |
| CONFIG-03 | `UserIntentStore.resetBuiltIn(mode:)` deletes override and restores defaults | unit | `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/UserIntentStoreTests` | ❌ Wave 0 |
| CONFIG-03 | `UserIntentStore.deleteCustomMode(id:)` removes entry and persists | unit | same file | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme Speech2Text -only-testing:Speech2TextTests/UserIntentStoreTests -only-testing:Speech2TextTests/IntentCatalogTests 2>&1 | tail -5`
- **Per wave merge:** Full suite: `xcodebuild test -scheme Speech2Text -destination 'platform=macOS' 2>&1 | tail -20`
- **Phase gate:** Full suite green before `$gsd-verify-work`

### Wave 0 Gaps
- [ ] `Speech2TextTests/UserIntentStoreTests.swift` — covers CONFIG-01 (load/save/reset/delete) and CONFIG-03
- [ ] `Speech2TextTests/IntentCatalogTests.swift` — covers CONFIG-01 (merge logic: empty store, override, custom append)
- [ ] No new framework install required — XCTest already configured

---

## Sources

### Primary (HIGH confidence)
- Direct codebase read — `LLMRewriteService.swift`, `IntentCatalog.swift`, `IntentDefinition.swift`, `ConvertMode.swift`, `IntentDetector.swift`, `ActivationStore.swift`, `ShellPreferences.swift`, `SetupWindowView.swift`, `AppDelegate.swift`, `ConvertIntent.swift`
- All findings reflect actual file content as of 2026-03-19

### Secondary (MEDIUM confidence)
- SwiftUI `TextEditor`, `DisclosureGroup`, `NavigationSplitView` — standard SwiftUI components, behavior well-understood from Apple docs; no version-specific verification performed
- Combine `.debounce(for:scheduler:)` — standard operator, verified by project's existing Combine imports

### Tertiary (LOW confidence)
- Qwen 2.5 1.5B phrase-pattern output format reliability — untested in this project for generation tasks; prompt engineering required (see Open Questions #3)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already used in the project; no new dependencies
- Architecture: HIGH — all patterns derived from direct codebase reading, not assumptions
- Pitfalls: HIGH — pitfalls derived from actual code structure (e.g., static let catalog, ConvertMode enum closure, single gate)
- LLM generation prompt format: LOW — new use case for this project; needs prototyping

**Research date:** 2026-03-19
**Valid until:** 2026-04-18 (stable stack; Swift/SwiftUI APIs are not changing)
