## Proposal: Higher-Tier Conversion Models

### 1. Current baseline
- `LLMRewriteService` loads `LLMRegistry.qwen2_5_1_5b`, the Qwen 2.5 1.5B instruct checkpoint, via `HubApi` into `~/Library/Application Support/Speech2Text/RewriteModel`.
- That container feeds every rewrite request, so swapping tiers only needs to change the descriptor passed into `LLMModelFactory`.

### 2. Candidate tiers above 1.5B
- Offer the Hugging Face Qwen 2.5 instruct models as extra tiers:
  * `Qwen/Qwen2.5-3B-Instruct` (≈3.1B params, 36 layers, 32K context).
  * Higher tiers already published in the series (7B, 14B, 32B, 72B) that can be surfaced progressively.
- Each tier should surface expected compute/VRAM requirements in the settings so users know when the model may be too heavy.

### 3. Implementation roadmap
1. **Model registry** – Replace the hardcoded `LLMRegistry.qwen2_5_1_5b` call with a `RewriteModelDescriptor` that includes identifier, human name, Hugging Face slug, parameter count, and hardware hints. `LLMRewriteService` will load whichever descriptor the user or auto-selection logic selects.
2. **Tier selection UI** – Extend the assistant settings to present the new tiers, show latency/resource expectations, and allow auto-selection based on detected hardware (CPU threads, GPU, VRAM). Auto-selection should fall back to the next-lightest tier if loading fails.
3. **Hardware-aware safety** – When loading tiers, capture failure reasons (e.g., OOM) and report them so the user can revert to 1.5B or a safe fallback.

### 4. Custom model download path
1. **URL entry** – Provide a field where a user pastes a Hugging Face (or similar) checkpoint URL and optionally their access token.
2. **Downloader service** – Fetch the archive into the same `RewriteModel` directory, verify checksums/signatures if available, and emit download progress plus validation errors.
3. **Metadata caching** – Store the source URL, download timestamp, tokenizer info, and inferred parameter count so the model appears alongside built-in tiers in the registry.
4. **Deletion & refresh** – Allow users to remove or replace downloaded models without impacting the default bundle.

### 5. Operational/testing work
- Add unit tests around descriptor swapping and fallback logic (mock the `LLMModelFactory`/`HubApi`).
- Expand any UI or integration tests to hit the new tier picker and custom model entry flows.
- Log telemetry around which tier is in use and whether downloads succeed so you can judge adoption.
- Document the steps to add future tiers or trusted URLs.

### 6. Next steps
1. Wire the new registry descriptor into `LLMRewriteService` and expose setters in preferences.
2. Build the tier picker UI and auto-selection logic.
3. Layer in the custom URL downloader and metadata caching, then drop it into the existing menu.
4. Validate on representative hardware tiers and update the docs.
