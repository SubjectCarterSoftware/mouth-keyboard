# Phase 8: LLM Rewrite Service - Research

**Researched:** 2026-03-19
**Domain:** MLX Swift LM integration, actor-isolated local inference, rewrite-service contracts
**Confidence:** HIGH

## Summary

Phase 8 should introduce a dedicated `LLMRewriteService` actor in `Speech2Text/Conversion/LLMRewriteService.swift` that mirrors the existing `WhisperService` pattern: one file containing the error enum, the `LLMRewriting` protocol, and the concrete actor implementation. The service should lazy-load `mlx-community/Qwen2.5-1.5B-Instruct-4bit` on first use through `LLMModelFactory.shared.loadContainer(configuration: LLMRegistry.qwen2_5_1_5b)`, cache the resulting `ModelContainer`, and reuse that container for all later rewrites in the same app session.

The critical design choice is: **cache the `ModelContainer`, but create a fresh `ChatSession` per rewrite call.** `ModelContainer` is the thread-safe isolation boundary provided by `mlx-swift-lm`; `ChatSession` is explicitly not thread-safe and carries conversation/KV-cache state that should not leak across unrelated rewrites. Reusing a `ChatSession` would pollute later conversions with prior prompts, violate mode isolation, and make cancellation/truncation handling harder to reason about.

Do not call `ChatSession.respond()` directly for the production rewrite path. Instead, use `streamDetails(to:)`, accumulate `.chunk` events into a local buffer, and inspect the final `.info(GenerateCompletionInfo)` event. This is the cleanest way to enforce the phase contract that **model load failure, generation error, cancellation, or truncation produce a thrown error and no partial output**. Treat `.cancelled` and `.length` stop reasons as failures. Return a string only when generation ends with `.stop` and the trimmed output is non-empty.

Use an app-owned `HubApi(downloadBase:)` rooted in `Application Support`, not the library default caches directory. `mlx-swift-lm` defaults to the user caches directory, which is convenient but purgeable; the roadmap language says the rewrite model should be cached persistently. The correct move is still to use the official `HubApi`, just with a more durable base URL.

The main-thread rule is straightforward: `ActivationStore` stays `@MainActor`, but all MLX work remains inside the non-main `LLMRewriteService` actor. Phase 8 should not touch clipboard fallback or UI loading indicators; those belong to Phase 9 and Phase 10. Phase 8 only defines the service contract that later phases will rely on.

<user_constraints>
## User Constraints (from REQUIREMENTS.md, STATE.md, ROADMAP.md, Phase 7)

### Locked Decisions

- The rewrite model is fixed for v1.1: `mlx-community/Qwen2.5-1.5B-Instruct-4bit`
- The service exposes `rewrite(body:mode:)` behind an `LLMRewriting` protocol
- Model loading is lazy on first use; do not preload the rewrite model at app launch
- The model must be loaded once and reused across subsequent rewrite calls in the same app session
- Any model load failure, generation error, cancellation, or other LLM failure must throw so Phase 9 can silently fall back to the raw transcript
- No partial rewritten output may be returned on failure
- Main-thread CPU must stay near zero while inference is running; MLX work must stay off `@MainActor`
- `ConvertMode.defaultSystemPrompt` is already locked in Phase 7 and is the authoritative per-mode system instruction source
- Phase 8 defines the failure contract for GUARD-02; the actual raw-transcript clipboard fallback is wired in Phase 9
- Phase 10 owns first-run download progress UI; Phase 8 should not couple the service to AppKit or menu-bar state

### Important Current-State Flags

- `ActivationStore` is `@MainActor` and currently owns the transcription -> clipboard flow in `finalizeSession()`
- `WhisperService` already establishes the local codebase pattern of `protocol + error enum + actor`
- `mlx-swift-lm` 2.30.6 is already linked in the Xcode project; no dependency work remains in this phase
- `STATE.md` flagged ChatSession lifetime as an open question; research resolves this: use **per-call `ChatSession`**, not per-session reuse

### Claude's Discretion

- Exact file placement inside `Speech2Text/Conversion/`
- Exact error-case names (`LLMRewriteError`)
- Exact `GenerateParameters` values, provided output quality is stable and truncation is treated as failure
- Whether to add a small progress callback seam now for Phase 10, as long as Phase 8 itself remains UI-agnostic

### Deferred Ideas (OUT OF SCOPE)

- Clipboard fallback wiring
- Word-count gate / 350-word guard
- Pill or menu-bar loading indicators
- Editable/custom mode prompts
- Cloud fallback or remote inference

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GUARD-02 | On any LLM failure, the raw transcript is copied to clipboard silently (no failed partial output) | Phase 8 must throw on load failure, generation failure, cancellation, truncation, and empty output so Phase 9 can reliably fall back to `originalTranscript` |

### Success Criteria Support

| Success Criterion | Research Support |
|-------------------|-----------------|
| Valid `rewrite(body:mode:)` returns non-empty output for all 6 modes | Use `ConvertMode.defaultSystemPrompt` as system instructions, `body` as the single user message, and reject empty/whitespace-only output |
| Any LLM inference error causes `rewrite` to throw with no partial output | Use `streamDetails`, buffer chunks locally, inspect final stop reason, and throw on `.cancelled`, `.length`, or thrown generation errors |
| Main thread is not blocked during inference | Keep all MLX work inside a non-main actor; Phase 9 awaits the actor from `ActivationStore.finalizeSession()` instead of importing MLX into main-actor code |
| Model loads once and is reused | Cache a `ModelContainer` plus an in-flight `loadTask` inside the actor; do not recreate the container for every rewrite |

</phase_requirements>

## Standard Stack

### Core

| Library / Asset | Version | Purpose | Why Standard |
|-----------------|---------|---------|--------------|
| `MLXLLM` | 2.30.6 | LLM model loading for Qwen2.5 and model registry access | Already linked; exposes `LLMModelFactory` and `LLMRegistry.qwen2_5_1_5b` |
| `MLXLMCommon` | 2.30.6 | `ModelContainer`, `ChatSession`, `GenerateParameters`, `Generation` stream | This is the supported high-level inference API for text generation |
| `Foundation` | bundled | actor state, `Progress`, trimming, errors | Already used everywhere in the codebase |
| Swift Concurrency (`actor`, `Task`) | Xcode 16 / Swift 5.10+ | off-main isolation and lazy-load task dedupe | Matches existing `WhisperService` pattern |
| `XCTest` | bundled | unit tests for service contract and failure semantics | Existing repo convention |

### Supporting

| Asset | Purpose | When to Use |
|-------|---------|-------------|
| `ConvertMode.defaultSystemPrompt` | Authoritative system prompt for each mode | Always — do not duplicate prompts in the service |
| `ConvertIntent.originalTranscript` | Raw-text fallback source for later phases | Phase 9 fallback wiring consumes this after service throws |
| `ActivationStore.finalizeSession()` | Existing async seam where rewrite is integrated later | Phase 9 only — not in this phase |
| `Progress` callback from `loadContainer` | First-run download/load progress hook | Optional seam to preserve now for Phase 10 |
| `HubApi(downloadBase:)` | Model storage location control | Use `Application Support` to satisfy the persistent-cache requirement without custom download code |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Cached `ModelContainer` + fresh `ChatSession` per call | Reuse one long-lived `ChatSession` | Wrong for this app: history/KV cache leaks between unrelated rewrites and `ChatSession` is not thread-safe |
| `streamDetails(to:)` + explicit stop-reason check | `respond(to:)` | `respond()` hides completion metadata, making cancellation/truncation handling too implicit for GUARD-02 |
| `LLMRegistry.qwen2_5_1_5b` | Raw string model id in multiple places | Registry constant is already provided by the library and avoids string drift |
| Optional injected progress callback | AppKit/UI updates from inside the actor | UI coupling belongs to Phase 10, not the core service |

**Primary recommendation:** create a dedicated `HubApi(downloadBase: applicationSupportURL)` once inside the service, use it with `LLMModelFactory.shared.loadContainer(hub:configuration:)`, cache the returned `ModelContainer`, and run each rewrite through a fresh `ChatSession(..., instructions: mode.defaultSystemPrompt, generateParameters: rewriteParameters)` using `streamDetails(to:)`.

## Architecture Patterns

### Recommended Project Structure

```text
Speech2Text/
  Conversion/
    ConvertMode.swift
    ConvertIntent.swift
    IntentDetector.swift
    LLMRewriteService.swift         # NEW: error enum + protocol + actor
Speech2TextTests/
  LLMRewriteServiceTests.swift      # NEW: contract and failure-behavior tests
```

### Pattern 1: Mirror `WhisperService` With a Single Actor Boundary

**What:** Keep the local architecture symmetrical with transcription: one protocol, one error enum, one concrete actor.

**Why:** The codebase already uses this shape successfully for `WhisperService`. It keeps dependencies injectable in tests and gives Phase 9 a clean seam.

**Recommended API shape:**

```swift
import Foundation
import Hub
import MLXLLM
import MLXLMCommon

enum LLMRewriteError: LocalizedError {
    case modelLoadFailed
    case generationFailed
    case cancelled
    case outputTruncated
    case emptyOutput
}

protocol LLMRewriting: Sendable {
    func rewrite(body: String, mode: ConvertMode) async throws -> String
}

actor LLMRewriteService: LLMRewriting {
    static let shared = LLMRewriteService()
}
```

**Integration point:** Phase 9 injects `any LLMRewriting` into `ActivationStore` exactly the way Phase 1-7 inject `any WhisperTranscribing`.

### Pattern 2: Cache `ModelContainer`, Deduplicate First Load With `loadTask`

**What:** Keep two pieces of actor state:

- `private var modelContainer: ModelContainer?`
- `private var loadTask: Task<ModelContainer, Error>?`

**Why:** This prevents duplicate first-use downloads and repeated disk reads when two rewrites arrive close together. The pattern is already validated in `mlx-swift-lm`'s own integration tests, which cache a `Task<ModelContainer, Error>?` inside an actor.

**Recommended flow:**

1. If `modelContainer` exists, return it.
2. If `loadTask` exists, await it.
3. Otherwise create `loadTask`, call `LLMModelFactory.shared.loadContainer(hub: rewriteHub, configuration: LLMRegistry.qwen2_5_1_5b, progressHandler: ...)`, store the result into `modelContainer`, clear `loadTask`, and return the container.

**Important note:** do not use `defaultHubApi` here. Upstream defaults to the user caches directory, which is purgeable. Build a small helper that resolves an `Application Support/Speech2Text/RewriteModel` directory and pass that as `HubApi(downloadBase:)`. This keeps storage durable without hand-rolling download logic.

### Pattern 3: Fresh `ChatSession` Per Rewrite Call

**What:** Build a new `ChatSession` for every rewrite request, using:

- cached `ModelContainer`
- `instructions: mode.defaultSystemPrompt`
- deterministic-ish `GenerateParameters`

**Why:** `ChatSession` is explicitly not thread-safe and owns conversation/KV-cache state. This app's rewrites are one-shot transforms, not a multi-turn chat. Per-call sessions guarantee isolation between "clean english", "email", "slack", and later custom modes.

**Recommended generation preset:**

- `temperature: 0`
- `maxTokens: 512`
- `topP: 1.0`
- leave repetition penalty off initially

This keeps outputs predictable and bounded. If manual validation shows truncation on the AI Prompt or Email mode, increase `maxTokens`, but treat truncation as an error instead of returning clipped output.

### Pattern 4: Use `streamDetails(to:)`, Not `respond(to:)`

**What:** Iterate the generation stream explicitly, append `.chunk` text to a local buffer, and capture the final `.info` event.

**Why:** `respond(to:)` is a convenience wrapper that only concatenates chunks. Phase 8 needs stricter behavior:

- throw on cancellation
- throw on truncation (`.length`)
- never return partial output
- optionally preserve completion metadata for debugging/validation

**Recommended contract:**

1. Create the session.
2. Iterate `for try await generation in session.streamDetails(to: body, images: [], videos: [])`
3. Append `.chunk`
4. Save the last `.info`
5. After the loop, `try Task.checkCancellation()`
6. If final stop reason is `.cancelled`, throw `.cancelled`
7. If final stop reason is `.length`, throw `.outputTruncated`
8. Trim output; if empty, throw `.emptyOutput`
9. Return the trimmed output

This is the cleanest path to GUARD-02 because any failure path produces an error and discards the buffered string.

### Pattern 5: Keep All MLX Work Off `@MainActor`

**What:** `LLMRewriteService` must remain a plain actor, not `@MainActor`.

**Why:** `ActivationStore` is already `@MainActor`. If Phase 8 moved MLX imports or session work into main-actor code, the app would violate the performance criterion immediately.

**Planner guidance:**

- Do not import `MLXLLM` or `MLXLMCommon` into `ActivationStore.swift`
- Do not annotate `LLMRewriteService`, `LLMRewriting`, or helper wrappers with `@MainActor`
- If a progress callback is added now, it should be a plain `@Sendable (Progress) -> Void`; Phase 10 can bridge it to the main actor at the UI boundary

### Pattern 6: Keep Phase 8 Purely Service-Level

**What:** Phase 8 should stop at "service works and throws correctly."

**Why:** The roadmap explicitly assigns UI/loading feedback and raw-transcript fallback wiring to later phases.

**Do in Phase 8:**

- build the actor
- expose the protocol
- verify real rewrites work
- verify error semantics

**Do not do in Phase 8:**

- call the service from `ActivationStore`
- flash the pill
- update the menu bar
- implement the 350-word guard
- paste or copy fallback text

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Hugging Face model download/caching | Custom downloader or manual cache path logic | `LLMModelFactory.shared.loadContainer(...)` | The official library already downloads, caches, loads config, tokenizer, and weights |
| Chat prompt formatting | String-concatenated chat template | `ChatSession` with `instructions:` and a single user message | The library already applies the model's chat template correctly |
| Cross-call conversation reuse | Custom persistent session history | Fresh `ChatSession` per rewrite call | Rewrites are independent one-shot transforms, not a conversation |
| Failure fallback in this phase | Clipboard or raw-text copy logic inside the service | Throw typed errors and let Phase 9 handle fallback | Keeps responsibility boundaries clean |
| Background-thread scheduling primitives for model execution | `DispatchQueue.global()` wrappers around MLX | Actor isolation + library async APIs | The service actor already provides the off-main boundary |
| Model-ID string duplication | Repeated hardcoded `"mlx-community/Qwen2.5-1.5B-Instruct-4bit"` literals | `LLMRegistry.qwen2_5_1_5b` | Avoids drift and keeps the configuration source centralized |

## Common Pitfalls

### Pitfall 1: Reusing a Single `ChatSession`

**What goes wrong:** Later rewrites inherit conversation history, KV cache, or stop-state from earlier calls.

**Why it happens:** `ChatSession` looks convenient to cache, but it is a conversational abstraction, not a stateless formatter.

**How to avoid:** Cache the `ModelContainer` only. Instantiate a new `ChatSession` per rewrite.

**Warning signs:** Email rewrites suddenly mention content from a prior Slack rewrite, or a second call behaves differently after a cancelled first call.

### Pitfall 2: Using `respond(to:)` and Accidentally Returning Partial Output

**What goes wrong:** Cancellation or max-token truncation can still leave a partially accumulated string in memory, and the code returns it because it never inspected completion metadata.

**Why it happens:** `respond(to:)` is designed for convenience demos, not strict "all-or-nothing" rewrite contracts.

**How to avoid:** Use `streamDetails(to:)`, record the final `.info`, and throw unless the stop reason is `.stop`.

**Warning signs:** Cancelled rewrites sometimes produce shortened text instead of throwing.

### Pitfall 3: Assuming Actor Isolation Alone Guarantees Serialization

**What goes wrong:** A future caller issues multiple rewrite requests concurrently and actor reentrancy allows overlap across suspension points.

**Why it happens:** Swift actors are reentrant. A long async method can yield the actor while awaiting model load or generation.

**How to avoid:** The current app architecture already has a single-flight processing path in `ActivationStore`, but planner should document that hard in-service serialization would require an explicit async gate if concurrent callers are introduced later.

**Warning signs:** Two rewrites launched from tests overlap and both start loading/generating at once.

### Pitfall 4: Importing MLX Into `@MainActor` Flow

**What goes wrong:** Main-thread CPU spikes during rewrite or UI responsiveness degrades.

**Why it happens:** The easiest integration path is to call MLX directly from `ActivationStore.finalizeSession()`, which is `@MainActor`.

**How to avoid:** Keep `ActivationStore` limited to orchestration and await the non-main actor service.

**Warning signs:** Instruments shows notable main-thread activity in model loading or token generation functions.

### Pitfall 5: Treating `.length` as Success

**What goes wrong:** The service returns truncated emails or prompts that look superficially valid but are incomplete.

**Why it happens:** `GenerateCompletionInfo.stopReason == .length` is easy to interpret as "good enough."

**How to avoid:** Treat `.length` as `.outputTruncated` and throw. Raise `maxTokens` only after validating real prompts.

**Warning signs:** Output ends mid-sentence or omits sign-off/closing structure for longer prompts.

### Pitfall 6: Duplicating or Rewording Locked System Prompts

**What goes wrong:** Phase 8 drifts from the prompt contract defined in Phase 7, making later settings work harder and risking behavior mismatches.

**Why it happens:** It is tempting to create separate service-local prompt constants.

**How to avoid:** Always read prompts from `ConvertMode.defaultSystemPrompt`.

**Warning signs:** Tests pass for intent detection, but the rewrite mode behavior does not match the prompts shown in settings or planning docs.

### Pitfall 7: Leaving the Model in the Caches Directory

**What goes wrong:** The model may be redownloaded after cache eviction, undermining the product requirement that it remain available after first use.

**Why it happens:** `mlx-swift-lm`'s `defaultHubApi` uses `FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first`.

**How to avoid:** Construct a dedicated `HubApi(downloadBase:)` rooted in `Application Support`.

**Warning signs:** The first rewrite works, later launches unexpectedly redownload the model, or the model disappears after system cleanup.

### Pitfall 8: Making Real-Model Tests Part of the Default Fast Suite

**What goes wrong:** Normal test runs become slow, network-dependent, and hardware-sensitive.

**Why it happens:** The success criteria require real rewrites for all modes, so it is tempting to put those into always-on XCTest.

**How to avoid:** Keep contract tests mocked by default. Put the real-model smoke pass behind an environment flag or manual verification checklist.

**Warning signs:** `xcodebuild test` starts downloading model weights or fails on machines without the model cache.

## Test Strategy

### Default Unit Tests

Create `Speech2TextTests/LLMRewriteServiceTests.swift` with fake collaborators so the fast suite does not require a model download. The key is to isolate the MLX-facing part behind a tiny internal wrapper or factory seam rather than trying to mock `ModelContainer` directly.

Recommended unit cases:

- `rewrite` loads the model once and reuses it across multiple calls
- the service passes `mode.defaultSystemPrompt` into the session instructions
- loader failure throws `LLMRewriteError.modelLoadFailed`
- generation failure throws `LLMRewriteError.generationFailed`
- `.cancelled` stop reason throws and returns no buffered text
- `.length` stop reason throws and returns no buffered text
- whitespace-only model output throws `LLMRewriteError.emptyOutput`
- optional progress callback receives values during first load

### Real-Model Smoke Validation

Use one gated integration pass, not part of the default test loop:

- first run: allow the Qwen2.5-1.5B-Instruct-4bit model to download/load
- invoke `rewrite(body:mode:)` once for each of the six built-in modes
- assert each result is non-empty after trimming
- invoke a second rewrite and confirm no second download/load occurs

This can be a manual checklist or an XCTest guarded by an environment variable such as `ENABLE_LLM_INTEGRATION_TESTS=1`.

### Concurrency / Cancellation Checks

Add at least one test that starts a rewrite, cancels the parent task mid-generation, and verifies the service throws instead of returning partial text. This is the most important behavioral gap between a demo integration and the roadmap contract.

## Validation Architecture

### Automated Validation

- `xcodebuild test` covers contract tests with fake collaborators
- one gated real-model smoke test verifies actual MLX integration against the pinned model

### Manual Validation

- Instruments Time Profiler run during a real rewrite
- confirm main-thread CPU stays near zero while the model is loading/generating
- confirm the second rewrite does not trigger another model download or disk-heavy reload
- spot-check all six modes with representative bodies:
  - Clean English: filler-heavy dictated prose
  - Email: short meeting follow-up
  - Slack / Teams: short workplace status update
  - Action Items: multi-person task list
  - AI Prompt: rough task description requiring structure

### Phase Boundary Validation

Phase 8 verification should end with "service works and throws correctly," not "clipboard fallback works." The fallback path is only fully verified after Phase 9 integrates `LLMRewriting` into `ActivationStore.finalizeSession()` using `ConvertIntent.originalTranscript`.

## Code Examples

### Recommended Service Skeleton

```swift
import Foundation
import MLXLLM
import MLXLMCommon

enum LLMRewriteError: LocalizedError {
    case modelLoadFailed
    case generationFailed
    case cancelled
    case outputTruncated
    case emptyOutput
}

protocol LLMRewriting: Sendable {
    func rewrite(body: String, mode: ConvertMode) async throws -> String
}

actor LLMRewriteService: LLMRewriting {
    private let rewriteHub = HubApi(
        downloadBase: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Speech2Text/RewriteModel", directoryHint: .isDirectory)
    )
    private var container: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?

    func rewrite(body: String, mode: ConvertMode) async throws -> String {
        let container = try await modelContainer()
        let session = ChatSession(
            container,
            instructions: mode.defaultSystemPrompt,
            generateParameters: .init(maxTokens: 512, temperature: 0)
        )

        var output = ""
        var completionInfo: GenerateCompletionInfo?

        do {
            for try await generation in session.streamDetails(to: body, images: [], videos: []) {
                switch generation {
                case .chunk(let chunk):
                    output += chunk
                case .info(let info):
                    completionInfo = info
                case .toolCall:
                    continue
                }
            }
        } catch {
            throw LLMRewriteError.generationFailed
        }

        try Task.checkCancellation()

        switch completionInfo?.stopReason {
        case .stop:
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw LLMRewriteError.emptyOutput }
            return trimmed
        case .length:
            throw LLMRewriteError.outputTruncated
        case .cancelled, .none:
            throw LLMRewriteError.cancelled
        }
    }

    private func modelContainer() async throws -> ModelContainer {
        if let container { return container }
        if let loadTask { return try await loadTask.value }

        let task = Task {
            try await LLMModelFactory.shared.loadContainer(
                hub: rewriteHub,
                configuration: LLMRegistry.qwen2_5_1_5b
            )
        }

        loadTask = task
        do {
            let loaded = try await task.value
            container = loaded
            loadTask = nil
            return loaded
        } catch {
            loadTask = nil
            throw LLMRewriteError.modelLoadFailed
        }
    }
}
```

### Optional Progress Hook for Phase 10

```swift
init(onLoadProgress: @escaping @Sendable (Progress) -> Void = { _ in }) {
    self.onLoadProgress = onLoadProgress
}

let task = Task {
    try await LLMModelFactory.shared.loadContainer(
        hub: rewriteHub,
        configuration: LLMRegistry.qwen2_5_1_5b,
        progressHandler: onLoadProgress
    )
}
```

This keeps Phase 8 UI-agnostic while preserving the correct seam for first-run download progress in Phase 10.
