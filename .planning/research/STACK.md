# Stack Research

**Domain:** macOS system-wide clipboard-first dictation utility — v1.1 LLM rewriting addition
**Researched:** 2026-03-18
**Confidence:** HIGH (core MLX Swift API verified against live source; version numbers from GitHub API)

---

## Existing Stack (v1.0 — DO NOT change)

The shipped app already uses these packages, confirmed from `project.pbxproj`:

| Technology | Version (shipped) | Role |
|------------|-------------------|------|
| Swift + AppKit/SwiftUI | Swift 6.x, macOS 14+ | App shell, menu bar, overlays |
| AVFoundation / AVAudioEngine | System | Microphone capture |
| WhisperKit | ≥ 0.17.0 (up to next major) | Local Whisper transcription via MLX |
| KeyboardShortcuts | shipped | Global hotkey activation |

WhisperKit already depends on `mlx-swift` internally. This matters for v1.1: the MLX Swift runtime is already a transitive dependency of the app — adding `mlx-swift-lm` does not introduce a new runtime, only new library code on top of what is already present.

---

## New Stack Additions for v1.1

### Core Addition: mlx-swift-lm

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `mlx-swift-lm` (product: `MLXLLM` + `MLXLMCommon`) | 2.30.6 | Local LLM inference for transcript rewriting | Only Swift-native MLX LLM library; provides Qwen2 architecture support, model factory, tokenization, and chat generation API in a single SPM package. MLX runtime is already present transitively via WhisperKit — this adds the language model layer on top. |

**Package URL:** `https://github.com/ml-explore/mlx-swift-lm`
**Requirement:** `.upToNextMinor(from: "2.30.6")`
**Minimum macOS:** 14 (matches existing app target)

The package exposes four products; the app needs exactly two:

- `MLXLLM` — Qwen2 model architecture implementation, `LLMModelFactory`, `LLMRegistry`
- `MLXLMCommon` — `ModelFactory.load()`, `ChatSession`, `GenerateParameters`, `generate()` function

`MLXVLM` and `MLXEmbedders` are not needed and should not be linked.

### Transitive Dependencies (resolved automatically via SPM, no manual action required)

| Package | Version | Role |
|---------|---------|------|
| `mlx-swift` | 0.30.6 | MLX tensor/compute runtime (already present via WhisperKit) |
| `swift-transformers` (HuggingFace) | 1.2.0 | Tokenizer, HubApi for model download, chat template rendering |

`swift-transformers` 1.2.0 replaces the older `HubApi` downloader with `swift-huggingface`'s `HubClient`. This is transparent to the app code.

---

## Model: mlx-community/Qwen2.5-1.5B-Instruct-4bit

| Property | Value |
|----------|-------|
| HuggingFace ID | `mlx-community/Qwen2.5-1.5B-Instruct-4bit` |
| Architecture (`config.json` `model_type`) | `qwen2` |
| MLXLLM registry key | `"qwen2"` — maps to `Qwen2Model` via `LLMTypeRegistry.shared` |
| Quantization | 4-bit, group_size 64 |
| Model weights file | `model.safetensors` — 869 MB |
| Total download size | ~880 MB (weights + tokenizer files) |
| Hidden layers | 28, hidden_size 1536 |
| Max context | 32,768 tokens |

The `model_type: qwen2` field in `config.json` is the exact key registered in `LLMTypeRegistry.shared`. Qwen2.5 uses the same architecture class as Qwen2 and loads correctly through the existing `Qwen2Model`/`Qwen2Configuration` path. This is confirmed by inspecting both the model's `config.json` and the `MLXLLM/Models/Qwen2.swift` registration.

---

## Key API: How to Load and Generate

### Model Loading

```swift
import MLXLMCommon
import MLXLLM

// Load model — downloads on first call, caches to ~/Library/Caches/ thereafter
let modelContext = try await loadModel(
    id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
)
```

`loadModel(id:)` is a free function in `MLXLMCommon`. It:
1. Resolves the HuggingFace model ID
2. Downloads all `*.safetensors` and `*.json` files on first call
3. Caches to `FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first` — survives app restarts
4. Returns a `ModelContext` (sendable, safe to store as an actor property)

For warm startup (model already cached), loading is fast (sub-second memory mapping of the weights file). On first launch it downloads ~880 MB.

### Chat-Style Generation (recommended for rewriting)

```swift
let session = ChatSession(
    modelContext,
    instructions: "You are a precise text rewriter. Output only the rewritten text, nothing else.",
    generateParameters: GenerateParameters(temperature: 0.3, maxTokens: 600)
)

let rewritten = try await session.respond(to: rawTranscript)
```

`ChatSession` manages conversation history and KV cache. For single-turn rewriting (one transcript in, one result out), use `respond(to:)` directly.

### Direct Generate API (lower-level, for streaming or token-count control)

```swift
let stream = generate(
    input: preparedInput,
    parameters: GenerateParameters(temperature: 0.3, maxTokens: 600),
    context: modelContext
)

for try await generation in stream {
    // generation.text contains newly decoded text chunks
}
```

`GenerateParameters` key fields for rewriting:
- `temperature: 0.3` — low randomness for deterministic rewriting
- `maxTokens: 600` — safe ceiling for 350-word input (1 word ≈ 1.3 tokens; 350 words → ~455 tokens output budget)
- `topP`, `topK`, `repetitionPenalty` — leave at defaults for rewriting

### Prompt Construction for Each Rewriting Mode

The Qwen2.5-Instruct model uses a system + user message structure. The `ChatSession(instructions:)` parameter maps to the system prompt. The user turn is the raw transcript. Example for Clean English mode:

```swift
ChatSession(
    modelContext,
    instructions: "Rewrite the text as clear, grammatically correct English. Fix dictation errors, filler words, and awkward phrasing. Output only the rewritten text.",
    generateParameters: GenerateParameters(temperature: 0.3, maxTokens: 600)
)
```

---

## Model Download / Bundling Strategy

**Recommendation: Runtime download on first use, cached to user's Library/Caches.**

Do NOT bundle the model in the app binary. At 880 MB the model dwarfs the app binary and would make every update download re-deliver the weights. The mlx-swift-lm `loadModel(id:)` function already handles download + persistent caching transparently.

**Implementation pattern (mirror how WhisperService.prepare() works):**

```swift
actor RewriteService {
    static let shared = RewriteService()
    private var modelContext: ModelContext?
    private var isLoading = false

    func prepare() async throws {
        guard modelContext == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        modelContext = try await loadModel(
            id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        )
    }
}
```

Call `prepare()` eagerly from `AppDelegate.applicationDidFinishLaunching` alongside the existing `WhisperService.shared.prepare()` call. Failure is non-fatal — surface an error to the user only when they attempt a convert-mode dictation.

**Cache location:** `~/Library/Caches/huggingface/` (managed by `swift-transformers` HubClient). This directory is outside the app sandbox, which is fine because the app is not sandboxed (confirmed: no `.entitlements` file exists in the project and no sandbox-related build settings are set in `project.pbxproj`).

---

## macOS Entitlements

The existing app is **not sandboxed** (no `.entitlements` file, no `com.apple.security.app-sandbox` key). This means:

- No `com.apple.security.network.client` entitlement is required — non-sandboxed apps can make outbound network connections freely
- The HuggingFace download will work without any entitlement changes
- The model cache writes to `~/Library/Caches/` without restriction

If the app is ever sandboxed (App Store), `com.apple.security.network.client` would be required for the initial model download, and the cache directory would need to be within the container. That is out of scope for v1.1.

---

## Supporting Libraries

No new supporting libraries are needed beyond `mlx-swift-lm`. Specifically:

| Avoid adding | Why |
|--------------|-----|
| `Accelerate` / `Metal` direct bindings | Already used internally by MLX; no app-level wiring needed |
| Separate tokenizer library | `swift-transformers` (transitive dep) handles Qwen2.5 BPE tokenization |
| `AsyncAlgorithms` | Not needed; Swift's native `AsyncStream` is sufficient for the generate API |

---

## Installation

```bash
# In Xcode: File > Add Package Dependencies
# URL: https://github.com/ml-explore/mlx-swift-lm
# Version rule: Up to Next Minor Version from 2.30.6

# Add to the Speech2Text app target (NOT test targets):
# - Product: MLXLLM
# - Product: MLXLMCommon
```

No `npm install`, CMake, or submodule steps — this is pure SPM.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `mlx-swift-lm` + `MLXLLM` | `llama.cpp` via C bridge | Use `llama.cpp` if you need to support Intel Macs or models not supported by MLX. For Apple Silicon only with MLX-formatted models, `mlx-swift-lm` is simpler and already coherent with the WhisperKit runtime. |
| `mlx-swift-lm` + `MLXLLM` | Cloud API (OpenAI, Anthropic) | Use a cloud API only if model quality matters more than privacy and offline capability. The project constraint is local-first. |
| `mlx-swift-lm` + `MLXLLM` | Apple's on-device Foundation Models (Writing Tools) | Use Apple's framework when targeting macOS 26+ exclusively and the built-in model quality is sufficient. As of March 2026, the API is not yet public for third-party system extension use in the way needed here. |
| Runtime download + cache | Bundle model in app | Bundle only if the app ships on a closed network with no internet access. 880 MB in the bundle means every code-only update re-downloads the full weight file through macOS delta update logic. |
| `ChatSession` high-level API | Raw `generate()` token stream | Use raw `generate()` only if you need per-token streaming UI (e.g., showing text appear word by word). For clipboard-output rewriting, awaiting the full `respond(to:)` string is simpler and less error-prone. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Python `mlx-lm` subprocess | Process startup and IPC overhead break the latency contract; packaging Python with a macOS app is fragile | `mlx-swift-lm` native Swift package |
| `MLXVLM` product | Vision-language model support; not needed, adds binary size and compile time | Only link `MLXLLM` and `MLXLMCommon` |
| Separate download manager (URLSession custom code) | `loadModel(id:)` already handles download, progress, caching, and resumption via `swift-transformers` HubClient | Use `loadModel(id:)` directly |
| Storing `ModelContext` as a `@MainActor` property | The model is large and generation blocks; it must live in an `actor` or background context, not on the main thread | Use a dedicated Swift `actor` (mirror `WhisperService` pattern) |

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| `mlx-swift-lm` 2.30.6 | `mlx-swift` 0.30.6 | `mlx-swift-lm` pins `.upToNextMinor(from: "0.30.6")` for its MLX dependency. WhisperKit also pulls `mlx-swift`. SPM will unify to the highest compatible version — both should resolve to 0.30.x. |
| `mlx-swift-lm` 2.30.6 | `swift-transformers` 1.2.0 | Pinned `.upToNextMinor(from: "1.2.0")`. No conflict with app code. |
| `mlx-swift-lm` 2.30.6 | macOS 14+ | Matches existing app deployment target. No change needed. |
| Qwen2.5-1.5B-Instruct-4bit | `MLXLLM` Qwen2 registry | `model_type: qwen2` in config.json maps directly to `Qwen2Model` in `LLMTypeRegistry.shared`. Confirmed by inspecting both files. |

---

## Sources

- `mlx-swift-lm` repository and releases — https://github.com/ml-explore/mlx-swift-lm — HIGH confidence (source-verified)
- `mlx-swift-lm` Package.swift (products, deps, macOS target) — https://raw.githubusercontent.com/ml-explore/mlx-swift-lm/main/Package.swift — HIGH confidence
- `MLXLMCommon/Evaluate.swift` — `generate()` function signatures — verified via WebFetch — HIGH confidence
- `MLXLMCommon/ChatSession.swift` — `ChatSession` API — verified via WebFetch — HIGH confidence
- `MLXLMCommon/ModelFactory.swift` — `loadModel(id:)` signature — verified via WebFetch — HIGH confidence
- `MLXLLM/LLMModelFactory.swift` — Qwen2 type registry entry — verified via WebFetch — HIGH confidence
- `mlx-community/Qwen2.5-1.5B-Instruct-4bit` config.json — `model_type: qwen2`, 869 MB weights — https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit/raw/main/config.json — HIGH confidence
- `mlx-swift` latest release (0.30.6, 2026-02-10) — GitHub API — HIGH confidence
- `mlx-swift-lm` latest release (2.30.6, 2026-02-18) — GitHub API — HIGH confidence
- `swift-transformers` latest release (1.2.0, 2026-03-09) — GitHub API — HIGH confidence
- Existing project `project.pbxproj` — confirms WhisperKit dep, no sandbox, no entitlements file — direct inspection — HIGH confidence

---
*Stack research for: v1.1 local LLM transcript rewriting — mlx-swift-lm addition to existing Swift macOS dictation app*
*Researched: 2026-03-18*
