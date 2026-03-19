# Architecture Research

**Domain:** Local LLM rewriting integration into existing macOS dictation pipeline
**Researched:** 2026-03-18
**Confidence:** HIGH (existing code read directly; MLX Swift API confirmed via official GitHub README and package source)

---

## Standard Architecture

### System Overview — v1.1 Target State

```
┌─────────────────────────────────────────────────────────────────┐
│                     System Integration Layer                    │
│  Menu Bar UI   Global Hotkey   Pill Panel   Permissions         │
└────────┬────────────────────────────────────────────────────────┘
         │ arm() / finish()
┌────────▼────────────────────────────────────────────────────────┐
│                  ActivationStore (@MainActor)                   │
│  State machine: idle → recording → processing → success/failure │
│                                                                 │
│  finalizeSession()                                              │
│    ├── prepareWhisperModel()                                    │
│    ├── whisperService.transcribe(samples:)  ──────────────────┐ │
│    │                                                           │ │
│    │   [NEW] intentDetector.detect(transcript:)               │ │
│    │         ↓ .rewrite(mode:body:) or .passthrough           │ │
│    │                                                           │ │
│    │   [NEW] if .rewrite AND wordCount ≤ 350:                  │ │
│    │         llmService.rewrite(body:mode:)  ─────────────────┘ │
│    │   [NEW] if .rewrite AND wordCount > 350:                   │
│    │         → failure(.conversionTooLong)                      │
│    │   if .passthrough:                                         │
│    │         → existing clipboard path (unchanged)             │
│    │                                                           │
│    └── clipboardService.writeToClipboard(finalText)            │
└─────────────────────────────────────────────────────────────────┘
         │                         │
┌────────▼──────────┐   ┌──────────▼──────────────────────────────┐
│  WhisperService   │   │  LLMRewriteService  (actor, NEW)        │
│  (actor, exists)  │   │  Holds: ModelContainer?                 │
│  WhisperKit pipe  │   │  prepare() async throws                 │
│  transcribe()     │   │  rewrite(body:mode:) async throws       │
└───────────────────┘   └─────────────────────────────────────────┘
         │                         │
┌────────▼───────────────────────────────────────────────────────┐
│  ClipboardService  (class, exists)                             │
│  writeToClipboard(_ text: String)                              │
└────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Status | Responsibility |
|-----------|--------|----------------|
| `ActivationStore` | Existing — modified | Owns recording state machine; after Whisper returns a transcript, calls `IntentDetector`, branches on result, calls `LLMRewriteService` or passes through, then writes clipboard |
| `WhisperService` | Existing — unchanged | Serialized ASR actor; produces raw transcript string |
| `IntentDetector` | New — value type | Pure function: scans transcript for "convert to X" prefix/suffix, returns `ConvertIntent` enum |
| `LLMRewriteService` | New — actor | Owns model load lifecycle; exposes `prepare()` and `rewrite(body:mode:) async throws -> String`; serializes all MLX calls |
| `ConvertMode` | New — enum | Five modes: `.cleanEnglish`, `.email`, `.slack`, `.actionItems`, `.prompt`; owns system prompt and user message templates |
| `ConvertIntent` | New — enum | `.rewrite(mode: ConvertMode, body: String)` or `.passthrough`; output of `IntentDetector` |
| `ClipboardService` | Existing — unchanged | Writes final output string; receives either raw transcript or LLM-rewritten text |
| `RecordingState` | Existing — modified | Add `.failure(reason: .conversionTooLong)` case to `FailureReason` |

---

## Intent Detection Placement

**Intent detection happens after Whisper, not before.**

Whisper produces the raw transcript. Intent detection is a pure string scan over that transcript. There is no audio-level signal to detect "convert to X" before transcription completes. The decision point is inside `finalizeSession()`, immediately after the `trimmed` transcript is produced and before the clipboard write.

```
whisperService.transcribe(samples:) → trimmedTranscript
    ↓
IntentDetector.detect(trimmedTranscript) → ConvertIntent
    ↓
switch ConvertIntent:
  .passthrough   → clipboardService.writeToClipboard(trimmedTranscript)   [unchanged path]
  .rewrite(mode, body):
    wordCount(body) > 350 → failure(.conversionTooLong)                   [new failure]
    wordCount(body) ≤ 350 → llmService.rewrite(body, mode) → finalText    [new path]
                          → clipboardService.writeToClipboard(finalText)
```

`IntentDetector` is a pure function (no state, no actor). It does not need to be injected into `ActivationStore` as a dependency — it can be called directly. It is worth testing in isolation.

---

## LLMRewriteService Actor Design

**Use an actor — same pattern as `WhisperService`.**

MLX Swift runs on Apple Silicon's unified GPU/CPU memory. The MLX framework is not documented as thread-safe; serializing all calls through an actor is the correct Swift concurrency approach and mirrors how `WhisperService` (a `WhisperKit` actor) is already structured.

```swift
actor LLMRewriteService {
    static let shared = LLMRewriteService()

    private var session: ChatSession?  // or equivalent ModelContainer
    private var isLoading = false

    func prepare() async throws {
        guard session == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let model = try await loadModel(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
        session = ChatSession(model)
    }

    func rewrite(body: String, mode: ConvertMode) async throws -> String {
        guard let session else { throw LLMRewriteError.modelNotReady }
        // Build messages from ConvertMode system/user prompt templates
        // Call session.respond(to:) or equivalent single-turn API
        // Return stripped output string
    }
}
```

The `ChatSession` API maintains conversation history. For single-turn rewrites, either use a fresh session per call or the lower-level `generate` API to avoid context bleed between unrelated dictations.

---

## Model Loading Lifecycle — Lazy, Not Eager

**Load lazily on first use, not at app launch.**

Reasoning:
- The Qwen2.5-1.5B-Instruct-4bit model is 869 MB on disk and requires approximately 1–2 GB of unified memory during inference on Apple Silicon.
- `WhisperService` uses a `tiny.en` model (~75 MB) and loads eagerly at launch because it is used on every session. The LLM is only used when the user triggers a convert mode — potentially never in a session.
- Eager LLM load at startup would add 1–2 GB RSS to a background menu bar utility, which is visible in Activity Monitor and inconsistent with the product's "lightweight background utility" identity.
- The first rewrite request carries a one-time load cost (~0.5–1 s on M-series hardware). This is acceptable: the user has already dictated and Whisper has already processed; they are waiting for clipboard output anyway.

**Do not preload during recording for the LLM.** WhisperService preloads during recording because its latency profile dominates post-recording time. LLM rewriting is rare and its load+inference total (~1.4 s) is a smaller fraction of the total perceived wait than a speculative 1–2 GB allocation at boot.

**Model is never unloaded during the session.** Once loaded, `LLMRewriteService` holds the `ChatSession` for the app's lifetime. macOS will page it under memory pressure.

---

## 350-Word Guard Placement

The word count check lives inside `ActivationStore.finalizeSession()`, after intent detection returns `.rewrite(mode:body:)` and before the `LLMRewriteService.rewrite()` call.

```swift
case .rewrite(let mode, let body):
    let wordCount = body.split(separator: " ").count
    if wordCount > 350 {
        state = .failure(reason: .conversionTooLong)
        soundPlayer.playFailure()
        scheduleDismissToIdle(...)
        return
    }
    let rewritten = try await llmService.rewrite(body: body, mode: mode)
    clipboardService.writeToClipboard(rewritten)
    state = .success(text: rewritten, pasted: didPaste)
```

The check happens on `body`, not on the full raw transcript. The intent detector strips the "convert to X" phrase from the body before returning `.rewrite`. This avoids triggering the limit on dictations where the trigger phrase itself pushes the count over 350.

---

## Data Flow — Complete v1.1 Path

### Convert Mode (new path)

```
User dictates: "convert to email [dictated content]"
    ↓
[Recording] AudioBufferAccumulator accumulates PCM
    ↓
[Processing] WhisperService.transcribe() → "convert to email [content]"
    ↓
IntentDetector.detect("convert to email [content]")
    → .rewrite(mode: .email, body: "[content]")
    ↓
wordCount("[content]") ≤ 350?
    YES → LLMRewriteService.rewrite(body: "[content]", mode: .email)
         → ConvertMode.email.systemPrompt + userMessage("[content]")
         → ChatSession.respond(to:) / generate()
         → "Subject: ...\n\n[professional email body]..."
         → ClipboardService.writeToClipboard(rewrittenText)
         → state = .success(text: rewrittenText, pasted: false)
    NO  → state = .failure(reason: .conversionTooLong)
         → pill shows "Recording too long for conversion"
```

### Passthrough (existing path — unchanged)

```
User dictates: "remind me to call John tomorrow"
    ↓
WhisperService.transcribe() → "remind me to call John tomorrow"
    ↓
IntentDetector.detect() → .passthrough
    ↓
ClipboardService.writeToClipboard(trimmedTranscript)   [exactly as v1.0]
    ↓
state = .success(text: trimmedTranscript, pasted: false)
```

---

## Recommended Project Structure (additions only)

```
Speech2Text/
├── Activation/
│   ├── ActivationStore.swift          [MODIFY: add llmService injection,
│   │                                   intent branch in finalizeSession()]
│   └── RecordingState.swift           [MODIFY: add .conversionTooLong
│                                       to FailureReason]
├── Transcription/
│   ├── WhisperService.swift           [UNCHANGED]
│   ├── WhisperModelChoice.swift       [UNCHANGED]
│   └── TranscriptionResult.swift      [UNCHANGED]
├── Rewrite/                           [NEW folder]
│   ├── ConvertMode.swift              [NEW: enum + prompt templates]
│   ├── ConvertIntent.swift            [NEW: enum .rewrite / .passthrough]
│   ├── IntentDetector.swift           [NEW: pure function, no actor]
│   └── LLMRewriteService.swift        [NEW: actor, model lifecycle]
├── Clipboard/
│   ├── ClipboardService.swift         [UNCHANGED]
│   └── PasteService.swift             [UNCHANGED]
└── Shell/
    └── RecordingPillView.swift        [MODIFY: add conversionTooLong
                                        failure message string]
```

Tests to add:

```
Speech2TextTests/
├── IntentDetectorTests.swift          [NEW: pure function, easy to unit test]
├── LLMRewriteServiceTests.swift       [NEW: mock session, test error paths]
└── ActivationStoreTests.swift         [EXTEND: inject mock LLMRewriteService]
```

---

## Architectural Patterns

### Pattern 1: Actor Wrapping for MLX State

**What:** Wrap `LLMRewriteService` as a Swift actor so all MLX calls are serialized. The model container is stored as a private actor-isolated property.
**When to use:** Always for any stateful ML model that is not proven re-entrant. MLX is not documented as Swift-concurrency-safe.
**Trade-offs:** Serialized inference means one rewrite at a time — correct for this use case where there is only ever one active session. No additional cost.

### Pattern 2: Protocol-Backed Injection Matching WhisperService

**What:** Define `LLMRewriting: Sendable` protocol with `func rewrite(body: String, mode: ConvertMode) async throws -> String`. Inject into `ActivationStore` alongside `whisperService`.
**When to use:** Use from the start. `ActivationStore` already follows this pattern with `WhisperTranscribing`. It makes the rewrite path testable with a mock and keeps `ActivationStore` decoupled from the concrete MLX implementation.
**Trade-offs:** One additional protocol type. The payoff is identical to what `WhisperTranscribing` already provides.

```swift
protocol LLMRewriting: Sendable {
    func rewrite(body: String, mode: ConvertMode) async throws -> String
}

actor LLMRewriteService: LLMRewriting { ... }
```

### Pattern 3: Pure Value Type for Intent Detection

**What:** `IntentDetector` is a free function or namespace enum, not an actor or class. It takes a `String` and returns `ConvertIntent`. No state, no injection, no async.
**When to use:** Always. Intent detection is a regex/prefix/suffix scan — it has no side effects and no shared state. Making it an actor would add noise without benefit.
**Trade-offs:** Cannot be mocked by injection, but it is pure and fully unit testable directly.

---

## Integration Points — New vs. Modified

### Modified Files

| File | What Changes |
|------|-------------|
| `Activation/ActivationStore.swift` | Add `llmService: any LLMRewriting` to init; add intent detection branch and 350-word guard inside `finalizeSession()`; add `LLMRewriteService.shared` to `.shared` singleton |
| `Activation/RecordingState.swift` | Add `conversionTooLong` to `FailureReason` enum |
| `Shell/RecordingPillView.swift` | Add `"conversionTooLong"` case to `failureMessage(for:)` with copy: `"Recording too long for conversion"` |
| `Shell/StatusMenuView.swift` | Add `"conversionTooLong"` case to `failureMessage(for:)` with full copy |
| `App/AppDelegate.swift` | No change required; LLM load is lazy and happens inside the actor on first use |

### New Files

| File | Description |
|------|-------------|
| `Rewrite/ConvertMode.swift` | Five-case enum; each case owns `systemPrompt: String` and `userMessage(for body: String) -> String` — directly encoding the prompt spec |
| `Rewrite/ConvertIntent.swift` | Two-case enum: `.rewrite(mode: ConvertMode, body: String)` and `.passthrough` |
| `Rewrite/IntentDetector.swift` | Free function `detect(_ transcript: String) -> ConvertIntent`; handles prefix and suffix scanning, case-insensitive match, strips trigger phrase from body |
| `Rewrite/LLMRewriteService.swift` | Actor; wraps `mlx-swift-lm` `loadModel` + `ChatSession`; exposes `prepare()` and `rewrite(body:mode:)` |

### Internal Boundary: ActivationStore ↔ LLMRewriteService

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `ActivationStore` → `LLMRewriteService` | `await llmService.rewrite(body:mode:)` inside existing `transcriptionTask` Task | Already runs in a Task off MainActor; no new concurrency context needed |
| `LLMRewriteService` internal | Actor-serialized; MLX calls are sequential | Prevents concurrent model access |
| `ActivationStore` → `IntentDetector` | Synchronous call; pure function | No concurrency overhead |

---

## Memory and Performance Implications on macOS

| Concern | Detail |
|---------|--------|
| Model size on disk | 869 MB (mlx-community/Qwen2.5-1.5B-Instruct-4bit) |
| Unified memory footprint at inference | ~1–2 GB active; held in unified GPU/CPU pool; does not count against traditional RSS until used |
| Load time (first use) | ~0.5–1 s on M-series hardware; occurs inside `transcriptionTask` so pill stays in processing state during load |
| Inference latency | ~0.39 s per rewrite at ~130 tokens/s on Apple M4 Pro (per PROMPT_SPEC.md testing) |
| Total perceived latency (first use) | Whisper + LLM load + inference ≈ 1–2 s for short recordings |
| Total perceived latency (warm) | Whisper + LLM inference ≈ 0.4–0.8 s |
| Memory pressure behavior | macOS will page the model under memory pressure; subsequent calls trigger reload via `prepare()` guard |
| App memory at idle (no convert triggered) | No additional allocation beyond v1.0 baseline |

**macOS 14+ is required** — the `mlx-swift-lm` package targets macOS 14 minimum, which matches the existing app target.

**Apple Silicon is required for practical performance** — MLX does not run efficiently on Intel. The app is already Apple Silicon-optimized (PROMPT_SPEC.md testing is on M4 Pro); this constraint is pre-existing, not new.

---

## Build Order

Build in this sequence to minimize integration cost:

1. **`ConvertMode.swift` + `ConvertIntent.swift`** — pure types, no dependencies, needed by everything else
2. **`IntentDetector.swift` + `IntentDetectorTests.swift`** — pure function; can be built and fully tested before touching ActivationStore or MLX
3. **`RecordingState.swift` (add `.conversionTooLong`)** — one-line enum addition; unblocks pill/menu failure message work
4. **`LLMRewriteService.swift` + `LLMRewriteServiceTests.swift`** — actor wrapping MLX; needs ConvertMode; can be developed and tested in isolation with mock ChatSession
5. **`ActivationStore.swift` (add intent branch + LLM injection)** — integrates IntentDetector and LLMRewriteService into finalizeSession(); needs all prior components
6. **`RecordingPillView.swift` + `StatusMenuView.swift` (add failure copy)** — UI strings; last because the failure case enum must exist first

---

## Anti-Patterns

### Anti-Pattern 1: Running MLX Directly on MainActor

**What people do:** Call `LLMRewriteService.rewrite()` synchronously or await it inside a `@MainActor` context without a Task.
**Why it's wrong:** MLX inference blocks for hundreds of milliseconds. Blocking the main actor freezes the UI.
**Do this instead:** `ActivationStore` already wraps all transcription work in `Task { await finalizeSession() }`. LLM calls go inside that same task — they never touch the main actor directly.

### Anti-Pattern 2: Eager Model Load at App Launch

**What people do:** Call `LLMRewriteService.shared.prepare()` in `applicationDidFinishLaunching`, mirroring the WhisperService warmup call.
**Why it's wrong:** Qwen2.5-1.5B-4bit is 869 MB / ~1–2 GB working set. Loading it unconditionally at launch penalizes every session with a background utility that balloons memory even when the user never uses convert modes.
**Do this instead:** Load lazily inside the first `rewrite()` call. The `prepare()` guard (`guard session == nil`) ensures idempotency.

### Anti-Pattern 3: Sharing ChatSession State Across Dictations

**What people do:** Use `ChatSession.respond(to:)` sequentially across multiple dictation sessions, leaving prior conversation turns in context.
**Why it's wrong:** Each dictation is an independent rewrite task. Prior session turns will pollute the model's context window and degrade output quality.
**Do this instead:** Use a single-turn generation API if available, or reinitialize `ChatSession` per rewrite call to ensure clean context. Performance cost is negligible compared to model load.

### Anti-Pattern 4: Intent Detection Before Whisper

**What people do:** Try to detect convert intent from audio (keyword spotting) to branch early and avoid running Whisper at all.
**Why it's wrong:** The existing architecture has no keyword spotting path, and adding one would be a separate major feature. The trigger phrase ("convert to X") is short, not sonically distinct, and appears anywhere in the utterance. The correct and only feasible detection point is post-transcript string scanning.
**Do this instead:** Always run Whisper first. Intent detection is a free string scan on the already-produced transcript.

### Anti-Pattern 5: Putting Prompt Templates in ActivationStore

**What people do:** Hard-code system prompts inside ActivationStore's finalizeSession() switch statement.
**Why it's wrong:** Prompt text changes frequently during tuning. ActivationStore is already a complex coordination site.
**Do this instead:** Each `ConvertMode` case owns its own `systemPrompt` and `userMessage(for:)`. `LLMRewriteService.rewrite()` calls these via the enum. ActivationStore never sees prompt strings.

---

## Scaling Considerations

| Scale | Notes |
|-------|-------|
| Single user, current | Lazy load + actor serialization is correct. No queue needed. |
| Add more modes | Extend `ConvertMode` enum only; no architectural change needed |
| Support longer recordings | 350-word guard is the product decision; architecture supports raising or removing it by changing one constant |
| Multiple concurrent users (not in scope) | Would require session isolation; not relevant to a per-user macOS utility |

---

## Sources

- Existing codebase: `ActivationStore.swift`, `WhisperService.swift`, `ClipboardService.swift`, `RecordingState.swift`, `AudioBufferAccumulator.swift` — read directly
- `PROMPT_SPEC.md` — model selection, prompt templates, latency benchmarks, 350-word limit rationale
- `mlx-swift-lm` GitHub README (official) — `loadModel` + `ChatSession` API, macOS 14 platform requirement — https://github.com/ml-explore/mlx-swift-lm
- `mlx-swift-lm` Package.swift (official) — platform targets (macOS 14+, iOS 17+), dependency versions — https://github.com/ml-explore/mlx-swift-lm/blob/main/Package.swift
- Hugging Face model card — file size (869 MB), quantization format — https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit
- MLX unified memory documentation — GPU/CPU memory sharing model on Apple Silicon — https://github.com/ml-explore/mlx/blob/main/docs/src/usage/unified_memory.rst

---
*Architecture research for: LLM rewriting integration into Speech2Test macOS dictation pipeline*
*Researched: 2026-03-18*
