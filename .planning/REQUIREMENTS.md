# Requirements: v1.3 Qwen 3.5 LLM Upgrade

## LLM Pipeline Fix
- [ ] **LLM-01**: User can address the AI assistant (Zeus) and receive a rewritten response using the Qwen 3.5 2B model instead of raw transcription
- [ ] **LLM-02**: User can address the AI assistant and receive a rewritten response using the Qwen 3.5 4B model
- [ ] **LLM-03**: User can address the AI assistant and receive a rewritten response using the Qwen 3.5 9B model
- [ ] **LLM-04**: User receives clear error feedback when LLM rewrite fails instead of a silent fallback to raw transcription

## Model Management
- [ ] **MDL-01**: User can switch between 2B, 4B, and 9B tiers in settings and the selected tier is used for subsequent rewrites
- [ ] **MDL-02**: User can download any tier from the settings UI with progress indication
- [ ] **MDL-03**: MLX-Swift framework coexistence between WhisperKit and MLXLLM does not cause loading or inference conflicts

## Traceability

| REQ-ID | Phase |
|--------|-------|
| LLM-01 | — |
| LLM-02 | — |
| LLM-03 | — |
| LLM-04 | — |
| MDL-01 | — |
| MDL-02 | — |
| MDL-03 | — |

## Out of Scope

- Cloud-based LLM inference — local-first remains the product direction
- Model fine-tuning or custom training — using pre-built MLX community models
- Streaming rewrite output to UI — clipboard-only output path unchanged
