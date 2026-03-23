# Pitfalls Research: v1.3 Qwen 3.5 LLM Upgrade

## Critical Pitfalls

### 1. Silent Error Swallowing (CONFIRMED — Active Bug)
**Phase:** Immediate
**Risk:** The catch block in `ActivationStore.finalizeSession` (line 363-372) silently falls back to raw transcript on ANY rewrite error. This makes debugging impossible because:
- The model could be failing to load
- The chat template could be failing to render
- The generation could be hitting token limits
- All of these look the same to the user: "just got raw text back"
**Prevention:** Add structured error logging and optionally surface the error type in the pill UI

### 2. Architecture Mismatch (`qwen2` vs `qwen3_5_text`)
**Phase:** Investigation
**Risk:** The Qwen 3.5 OptiQ model uses `model_type: "qwen3_5_text"` which was only recently added to `mlx-swift-lm`. If the project's SPM resolution didn't fully update, the model type may still be unrecognized at runtime.
**Prevention:** Verify the Xcode build resolves to the exact commit `06bfeed` and that `Qwen35TextConfiguration`/`Qwen35TextModel` are linked

### 3. VLM Config Nesting
**Phase:** Investigation  
**Risk:** The Qwen 3.5 OptiQ model's `config.json` has its architecture params nested under `text_config` (VLM pattern) rather than at the top level (LLM pattern). `Qwen35TextConfiguration` must specifically handle this nesting or the model weights won't load correctly.
**Prevention:** Check if `Qwen35TextConfiguration` reads from `text_config` key

### 4. Thinking Mode Token Generation
**Phase:** Fix
**Risk:** If thinking mode is enabled (even unintentionally via chat template), the model will waste tokens on internal reasoning (`<think>...</think>`) before responding. With only 1024 max tokens for the 2B tier, this could exhaust the budget on thinking alone and return either empty or truncated output.
**Prevention:** Ensure chat template passes `enable_thinking=false`; implement think-tag stripping as safety net

### 5. EOS Token ID Mismatch
**Phase:** Fix
**Risk:** Qwen 3.5 uses EOS token ID 248044 (`<|im_end|>`) vs Qwen 2.5's 151645. If `ModelConfiguration.extraEOSTokens` or `eosTokenIds` aren't configured correctly, the model may never stop generating.
**Prevention:** Verify `ModelConfiguration` propagates EOS tokens from the downloaded model's config

### 6. MLX-Swift Version Floor
**Phase:** Investigation
**Risk:** The HuggingFace model card states `mlx-lm >= 0.30.7` is required. The `mlx-swift` version is pinned at 0.30.6. While the Python `mlx-lm` and Swift `mlx-swift` version numbers don't directly correspond, the underlying MLX operations for linear attention may require the newer version.
**Prevention:** Check if mlx-swift 0.30.6 includes the linear attention operators that Qwen 3.5 needs
