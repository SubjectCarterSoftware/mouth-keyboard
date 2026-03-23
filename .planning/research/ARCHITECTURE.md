# Architecture Research: v1.3 Qwen 3.5 LLM Upgrade

## Current LLM Rewrite Flow

```
ActivationStore.finalizeSession()
  → TriggerTranscriptParser.split() → .validTrigger(content, instruction)
  → state = .converting
  → llmRewriteService.rewrite(body: content, instructions: instruction)
    → resolveModel() → downloadFiles() → loadContainer()
    → ChatSession(container, instructions:, generateParameters:, tools:[])
    → session.streamDetails(to: body)
    → chunks accumulated → trimmed → returned
  → clipboardService.writeToClipboard(rewritten)
  → state = .success(converted: true)
```

**On failure**: catch block (ActivationStore:363-372) logs error via NSLog and falls back to raw transcript silently.

## Key Integration Points

### 1. Model Loading (`LLMRewriteService.resolveModel`)
- Downloads model files via HubApi
- Creates `ModelConfiguration` with hub slug or local directory
- Loads via `LLMModelFactory.shared.loadContainer(hub:configuration:)`
- **Issue**: `ModelConfiguration(id: hubSlug)` creates config from hub ID, then `localModelConfiguration()` wraps it with a local directory. The `extraEOSTokens` and `eosTokenIds` from the source config may not include Qwen 3.5 specific tokens.

### 2. Chat Session (`LLMRewriteService.defaultStreamFactory`)
- Creates `ChatSession(container, instructions:, generateParameters:, tools:[])`
- Streams via `session.streamDetails(to: body, images: [], videos: [])`
- **Issue**: No handling of thinking mode tokens (`<think>`/`</think>`). If thinking mode is active, the model may generate thinking tokens that get included in the output or cause the model to hit the token limit generating thoughts instead of content.

### 3. Generation Parameters
- `temperature: 0, topP: 1.0` — deterministic
- `maxTokens`: 1024 (2B), 1536 (4B), 2048 (9B)
- **Issue**: No `repetitionPenalty` or thinking-mode-aware parameters

### 4. Model Warmup (`ActivationStore.beginRewriteModelWarmup`)
- Calls `setTier(preferences.rewriteModelTier)` then `prewarm()`
- Happens when recording starts — preloads model for fast rewrite

## Potential Failure Points

1. **Model type not recognized** → `loadContainer` throws → `resolveModel` catches → `modelLoadFailed`
2. **Chat template rendering fails** → `ChatSession` or `streamDetails` throws → `generationFailed`
3. **Thinking mode produces `<think>` tokens** → output filled with thinking, filtered to empty → `emptyOutput`
4. **Token limit exhausted on thinking** → `completion(.length)` → `outputTruncated`
5. **EOS token mismatch** → model never stops generating → hangs or hits max tokens
6. **VLM config nesting** → model loads as VLM but used as text-only → unexpected behavior
