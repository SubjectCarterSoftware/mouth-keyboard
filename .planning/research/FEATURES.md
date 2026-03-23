# Features Research: v1.3 Qwen 3.5 LLM Upgrade

## Table Stakes

| Feature | Status | Notes |
|---------|--------|-------|
| Model loads without crash | ❌ Unknown | Need to verify model actually loads with `qwen3_5_text` type |
| Chat template renders correctly | ❌ Unknown | ChatML format with `<|im_start|>` / `<|im_end|>` |
| Generation produces non-empty output | ❌ Failing | Currently falling back to raw transcript |
| Tier switching works | ❌ Unknown | Settings UI exists but untested with new models |
| Model download with progress | ✅ Working | At least 2B tier downloaded successfully |

## Differentiators

| Feature | Priority | Notes |
|---------|----------|-------|
| Thinking mode control | High | Qwen 3.5 small models (2B, 4B, 9B) reportedly have thinking disabled by default, but needs verification |
| Think-tag stripping | High | If thinking mode IS active, output must strip `<think>...</think>` blocks |
| Error visibility | Medium | Silent fallback masks real issues — need user-facing error info |
| Model deletion for unused tiers | Low | Already implemented in settings UI |

## Qwen 3.5 Small Model Behavior

Per research:
- Qwen 3.5 **small models (0.8B, 2B, 4B, 9B) have thinking disabled by default**
- The chat template Jinja variable `enable_thinking` controls this
- To explicitly disable: pass `enable_thinking=false` in chat template kwargs
- The `<|im_end|>` token (ID 248044) is the EOS token for chat turns
