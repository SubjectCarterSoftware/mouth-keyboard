## Proposal: Higher-Tier Conversion Models

> **Scope:** This proposal only affects the LLM rewrite/conversion step (`LLMRewriteService`) —
> the part that transforms raw transcribed text into a formatted output (e.g. "convert to
> email", "make this formal"). The Whisper transcription pipeline is completely separate
> and untouched by this work.

---

### 1. Current baseline

- `LLMRewriteService` loads `LLMRegistry.qwen2_5_1_5b` (Qwen 2.5 1.5B Instruct) via `HubApi` into `~/Library/Application Support/Speech2Text/RewriteModel/`.
- The model is hardcoded in `defaultLoader` (line 222–228 of `LLMRewriteService.swift`).
- The project depends on `mlx-swift-lm` **v2.30.6** — recent enough for Qwen 3.5 support.
- `ActivationStore` consumes the service via the `LLMRewriting` protocol. `IntentEditView` calls `LLMRewriteService.shared` directly in three places — minor cleanup needed but not a blocker.

---

### 2. Tier ladder

All tiers are Qwen 3.5 (February 2026), from a single model family with consistent prompt templates and tokenizers. All have official MLX 4-bit quantised ports on Hugging Face and run on Apple Silicon via the existing `MLXLLM` + `HubApi` stack. No new dependencies required.

| Tier | Model | HF Slug | 4-bit disk | RAM guidance |
|------|-------|---------|-----------|--------------|
| Default | Qwen 3.5 2B | `mlx-community/Qwen3.5-2B-MLX-4bit` | ~1.6 GB | 8 GB+ (any Mac) |
| Standard | Qwen 3.5 4B | `mlx-community/Qwen3.5-4B-MLX-4bit` | ~2.9 GB | 8 GB+ |
| High | Qwen 3.5 9B | `mlx-community/Qwen3.5-9B-MLX-4bit` | ~5 GB | 16 GB+ |

> **Default tier change:** The current hardcoded model (Qwen 2.5 1.5B) is replaced by
> Qwen 3.5 2B as the new default. It is a newer, more capable model at a similar size
> (~500 MB larger). The old 1.5B tier is dropped — there is no reason to offer an older,
> weaker model when a better one exists at the same weight class.

> **Thinking mode — not a concern.** Qwen 3.5 small models (0.8B, 2B, 4B, 9B) ship with
> reasoning/thinking **disabled by default**. No `enable_thinking: false` configuration is
> needed, no `<think>` tags appear in output, no post-processing required, no latency
> impact. This was confirmed across Qwen's official model cards and Unsloth documentation.

> **All slugs verified (2026-03-21):**
> - [`mlx-community/Qwen3.5-2B-MLX-4bit`](https://huggingface.co/mlx-community/Qwen3.5-2B-MLX-4bit) — ~1.6 GB, 6.225 bits/weight
> - [`mlx-community/Qwen3.5-4B-MLX-4bit`](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) — ~2.9 GB
> - [`mlx-community/Qwen3.5-9B-MLX-4bit`](https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit) — ~5 GB
>
> All three are Apache 2.0 licensed and converted for Apple Silicon via mlx-vlm.

---

### 3. Implementation plan

Ordered to front-load risk. Each phase is independently shippable.

#### Phase 1 — Spike: confirm Qwen 3.5 loads and generates cleanly

Before writing any production code, verify the full path works:
1. Temporarily swap `LLMRegistry.qwen2_5_1_5b` in `defaultLoader` with a `ModelConfiguration` pointing at `mlx-community/Qwen3.5-4B-MLX-4bit`.
2. Run a rewrite through `LLMRewriteService` (via the existing test harness or a manual trigger).
3. Confirm: the model downloads, loads into `ModelContainer`, generates clean output through `ChatSession` with no `<think>` blocks, and stops normally.
4. Revert the spike. If this fails, investigate before proceeding.

**Exit criteria:** A Qwen 3.5 model produces clean rewrite output through the existing `ChatSession` → `streamDetails` path with zero code changes beyond the model slug.

#### Phase 2 — `RewriteModelTier` enum + `LLMRewriteService.setTier`

1. **`RewriteModelTier`** — A `String`-rawValue `CaseIterable` enum modelled on `WhisperModelChoice`:
   ```
   enum RewriteModelTier: String, CaseIterable, Identifiable {
       case standard2B = "qwen3.5-2b"    // Default
       case standard4B = "qwen3.5-4b"
       case high9B     = "qwen3.5-9b"
   }
   ```
   Properties: `displayName`, `hubSlug`, `approximateDownloadSizeGB`, `recommendedMaxTokens`, `ramGuidance`.

2. **`LLMRewriteService.setTier(_:)`** — Actor-isolated method that:
   - Stores the new tier's `ModelConfiguration`
   - Cancels any in-flight `loadTask`
   - Nils out `cachedModel` (forcing re-load on next call)
   - The existing `Loader` closure and `resolveModel()` pattern require no restructuring — `setTier` just changes what `defaultLoader` resolves to.

3. **`maxTokens` per tier** — Replace the hardcoded `GenerateParameters(maxTokens: 1_024)` with `tier.recommendedMaxTokens`. Suggested values: 1024 (2B), 1536 (4B), 2048 (9B).

#### Phase 3 — `ShellPreferences` persistence

1. Add `rewriteModelTier` key to `ShellPreferences.Keys`.
2. Add `@Published var rewriteModelTier: RewriteModelTier` with the same `didSet { defaults.set(...) }` pattern as `whisperModel`.
3. Default to `.standard2B` when no stored value exists.
4. Add `rewriteModelTier = .standard2B` and `defaults.removeObject(forKey: Keys.rewriteModelTier)` to `reset()`.
5. In `AppDelegate` or wherever `ShellPreferences` and `LLMRewriteService` are both accessible, observe `rewriteModelTier` changes and call `setTier` on the service.

#### Phase 4 — Tier picker UI

1. Add a "Conversion Model" section to the settings sheet (near the existing AI assistant section).
2. List all tiers with `displayName`, approximate download size, and RAM guidance.
3. Show a checkmark on the active tier (same pattern as preset rows in `AIAssistantSettingsView`).
4. Selecting a tier updates `preferences.rewriteModelTier`, which triggers the observer → `setTier`.
5. If the model hasn't been downloaded yet, show the download size inline (e.g. "~2.9 GB download") before the user confirms.

#### Phase 5 — Error handling + eager warm-up

1. **OOM / load failure fallback:**
   - Add `.modelTooLargeForDevice` to `LLMRewriteError`.
   - In `resolveModel()`, inspect load errors — if the error suggests memory pressure, throw `.modelTooLargeForDevice` instead of generic `.modelLoadFailed`.
   - Surface to the user: "This model is too large for your device — reverting to default."
   - Reset `preferences.rewriteModelTier` to `.standard2B`.

2. **Eager warm-up:**
   - In `AppDelegate.applicationDidFinishLaunching`, after the existing `WhisperService.shared.prepare()` call, add a `Task` that calls a new `LLMRewriteService.shared.prepare()` method (which just calls `resolveModel()` and discards the result).
   - Gate on tier being above `.standard2B` to avoid unnecessary early load for the lightest tier.

#### Phase 6 — Disk management (future, not in v1)

Known gap: if a user tries all three tiers, ~9.4 GB of models accumulate on disk under `RewriteModel/`. A future iteration should:
- Show total cached model size in settings.
- Let the user delete unused tiers.
- This is not a blocker for the initial release.

---

### 4. Testing

- **`setTier` unit tests** — verify `cachedModel` is cleared, `loadTask` is cancelled, next `resolveModel()` uses the new tier's slug (mock `LLMModelFactory` / `HubApi`).
- **`.modelTooLargeForDevice` fallback test** — inject a loader that throws a simulated OOM error, verify the preference reverts to `.standard2B`.
- **`ShellPreferences` round-trip** — set tier, read it back from a fresh `ShellPreferences` instance with the same `UserDefaults`, confirm it persists. Confirm `reset()` restores the default.
- **Tier picker UI test** — select a tier, verify the checkmark moves and preferences update.

---

### 5. Files touched

| File | Change |
|------|--------|
| `Speech2Text/Conversion/RewriteModelTier.swift` | **New** — enum with tier definitions |
| `Speech2Text/Conversion/LLMRewriteService.swift` | Add `setTier`, `prepare()`. Replace hardcoded `LLMRegistry.qwen2_5_1_5b` with tier-driven `ModelConfiguration`. Make `generationParameters` dynamic. |
| `Speech2Text/Persistence/ShellPreferences.swift` | Add `rewriteModelTier` key, property, and `reset()` line |
| `Speech2Text/Shell/AIAssistantSettingsView.swift` (or new settings section) | Tier picker UI |
| `Speech2Text/App/AppDelegate.swift` | Eager warm-up call, tier change observer |
| `Speech2Text/Shell/IntentEditView.swift` | Minor: replace `LLMRewriteService.shared` with injected `LLMRewriting` (cleanup, not blocking) |
| `Speech2TextTests/LLMRewriteServiceTests.swift` | `setTier`, fallback, and cache invalidation tests |
| `Speech2TextTests/ShellPreferencesTests.swift` (or existing test file) | Tier persistence + reset tests |
