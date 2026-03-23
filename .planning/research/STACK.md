# Stack Research: v1.3 Qwen 3.5 LLM Upgrade

## Current Dependencies

| Package | Version | Source |
|---------|---------|--------|
| mlx-swift | 0.30.6 | github.com/ml-explore/mlx-swift |
| mlx-swift-lm | commit `06bfeed` (no tag) | github.com/ml-explore/mlx-swift-lm |
| WhisperKit | 0.17.0 | github.com/argmaxinc/WhisperKit |
| swift-transformers | 1.1.9 | github.com/huggingface/swift-transformers |
| swift-jinja | 2.3.2 | github.com/huggingface/swift-jinja |

## Qwen 3.5 Model Architecture

Qwen 3.5 uses a **hybrid attention architecture** with alternating `linear_attention` and `full_attention` layers. This is fundamentally different from Qwen 2.x which used standard `Qwen2ForCausalLM` self-attention.

- **Model type**: `qwen3_5_text` (registered in `mlx-swift-lm` at commit `06bfeed` via PR #135)
- **Config structure**: VLM-style with `text_config` nesting (includes vision tokens even for text-only use)
- **Layer types**: Alternating `linear_attention` (18 layers) and `full_attention` (6 layers) across 24 layers
- **Vocab size**: 248,320 (vs 151,936 for Qwen 2.5)
- **EOS token ID**: 248044 (vs 151645 for Qwen 2.5)
- **Chat format**: ChatML (`<|im_start|>` / `<|im_end|>`)

## MLX Framework Version Requirement

HuggingFace model card states: **mlx-lm >= 0.30.7** required for Qwen 3.5 architecture support. The `mlx-swift` version pinned is **0.30.6** but `mlx-swift-lm` is at a newer commit that includes Qwen 3.5 support.

## WhisperKit / MLXLLM Overlap

Both WhisperKit and MLXLLM depend on `mlx-swift` as their foundation:
- **WhisperKit**: Uses CoreML models via WhisperKit SDK, stores in `~/Documents/huggingface/models/argmaxinc/`
- **MLXLLM**: Uses MLX safetensors, stores in `~/Library/Application Support/Speech2Text/RewriteModel/models/mlx-community/`
- **Shared dependency**: `mlx-swift` v0.30.6 — single version resolved by SPM
- **Risk**: Version conflicts if WhisperKit pins to a different mlx-swift version than MLXLLM needs

## Downloaded Models on Device

| Model | Status | Architecture |
|-------|--------|-------------|
| Qwen2.5-1.5B-Instruct-4bit | ✅ Working | `qwen2` |
| Qwen3.5-2B-OptiQ-4bit | ❌ Failing | `qwen3_5_text` |
| Qwen3.5-2B-MLX-4bit | Unknown | Unknown |
| Qwen3-8B-4bit | Unknown | Unknown |
| Qwen3-1.7B-4bit | Unknown | Unknown |
