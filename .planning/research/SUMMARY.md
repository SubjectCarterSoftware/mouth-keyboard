# Research Summary: v1.3 Qwen 3.5 LLM Upgrade

## Key Findings

### Stack
- `mlx-swift-lm` is pinned to commit `06bfeed` which IS the PR that adds `qwen3_5_text` model type support
- `mlx-swift` v0.30.6 is the shared dependency between WhisperKit and MLXLLM
- Qwen 3.5 requires `mlx-lm >= 0.30.7` (Python) — Swift equivalent may need verification
- 5 model directories exist on disk including the failing `Qwen3.5-2B-OptiQ-4bit`

### Architecture Differences
- **Qwen 2.5** (working): `model_type: "qwen2"`, `Qwen2ForCausalLM`, standard self-attention, flat config
- **Qwen 3.5** (failing): `model_type: "qwen3_5_text"`, hybrid `linear_attention`/`full_attention`, VLM-style `text_config` nesting, larger vocab (248K vs 152K), different EOS token ID (248044 vs 151645)

### Likely Failure Modes (ordered by probability)
1. **Model loading crash/error** — `Qwen35TextModel` may fail to load due to VLM config, missing operators, or mlx-swift version
2. **Chat template Jinja rendering failure** — template may reference variables or tokens not handled by swift-jinja v2.3.2
3. **Thinking mode interference** — if enabled, wastes token budget on `<think>` blocks (though small models reportedly have it off by default)
4. **EOS token mismatch** — model never stops generating if stop tokens aren't configured correctly

### Silent Error Problem
The catch block in `ActivationStore.finalizeSession()` logs via `NSLog` but gives the user their raw transcript as if it succeeded normally. The user sees "success" with raw text — indistinguishable from "no trigger detected" behavior.

## Watch Out For
- VLM-style config nesting — `Qwen35TextConfiguration` must handle the `text_config` wrapper
- Linear attention operators — may require a newer `mlx-swift` version than 0.30.6
- Token limit exhaustion — 1024 tokens for 2B tier may not be enough if thinking mode is active
- Framework overlap — WhisperKit and MLXLLM share `mlx-swift`; updating one may affect the other

## Recommended Approach
1. **Diagnose first**: Build a diagnostic test or add verbose logging to identify the EXACT failure point
2. **Fix model loading**: Ensure `Qwen35TextModel` loads correctly from the local config
3. **Fix generation**: Handle chat template, EOS tokens, and thinking mode
4. **Improve error visibility**: Surface rewrite errors to the user instead of silent fallback
