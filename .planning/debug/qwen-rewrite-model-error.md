---
status: awaiting_human_verify
trigger: "Investigate issue: qwen-rewrite-model-error"
created: 2026-03-23T17:45:55Z
updated: 2026-03-23T17:55:56Z
---

## Current Focus

hypothesis: confirmed — stale or partial OptiQ model directories are misclassified as downloaded because artifact detection still matches the pre-OptiQ file set.
test: have the user launch the app and retry the assistant-triggered rewrite flow so the app can redownload/repair any incomplete OptiQ model directory
expecting: setup/runtime should no longer treat incomplete OptiQ model directories as ready; the assistant-triggered rewrite should return rewritten output instead of raw-transcript fallback
next_action: wait for user verification in the real app workflow

## Symptoms

expected: When the assistant name appears in the transcript, the app should split the transcript around the last assistant-name boundary, send the text before the trigger as the user body, send the text after the trigger as instructions/system guidance, run the selected local Qwen 3.5 model via MLX Swift, strip any thinking tags from the output, and return the visible rewritten result.
actual: Trigger detection appears to work, the app enters the rewrite/loading path, but the UI surfaces a model error and the raw transcript is copied to the clipboard.
errors: UI only shows a generic model error; ActivationStore contains a fallback that copies the raw transcript on rewrite failure. Static review suggests likely failure inside LLMRewriteService model resolution or generation.
reproduction: Speak a transcript that includes the assistant name so assistant-triggered rewrite is activated; wait for rewrite path to start. Instead of processed output, model error appears and raw transcript is copied.
started: User reports this worked previously but repeated attempts to restore it have failed. Current milestone is v1.3 Qwen 3.5 LLM Upgrade.

## Eliminated

## Evidence

- timestamp: 2026-03-23T17:47:53Z
  checked: Speech2Text/Activation/ActivationStore.swift
  found: beginRewriteModelWarmup() calls setTier(...) then `try? await llmRewriteService.prewarm()`, while finalizeSession() catches rewrite errors, logs them, copies raw transcript, and surfaces `.modelError("Rewrite failed: ...")`.
  implication: user-visible symptom can hide the original model-loading failure until rewrite() is invoked during conversion.

- timestamp: 2026-03-23T17:47:53Z
  checked: Speech2Text/Conversion/LLMRewriteService.swift
  found: resolveModel() sets an MLX GPU cache limit, downloads model files for the selected tier, then loads a local container via `LLMModelFactory.shared.loadContainer(hub:configuration:)`; rewriteCore maps unknown load errors to `.modelLoadFailed`.
  implication: a bad local model configuration or unsupported model artifact would produce the generic model error seen in UI.

- timestamp: 2026-03-23T17:47:53Z
  checked: Speech2Text/Conversion/RewriteModelTier.swift and Speech2TextTests/LLMRewriteServiceTests.swift
  found: the app now points at Qwen3.5 OptiQ tiers (`mlx-community/Qwen3.5-{2B,4B,9B}-OptiQ-4bit`), and there is an existing real-model test `testRealQwen2BModelGeneration()` meant to exercise the parser plus `prewarm()` + `rewrite()`.
  implication: the failure likely correlates with the recent Qwen 3.5 tier upgrade and can be reproduced through existing focused tests.

- timestamp: 2026-03-23T17:53:52Z
  checked: focused xcodebuild run for Speech2TextTests/LLMRewriteServiceTests
  found: all rewrite-service unit tests passed except `testRealQwen2BModelGeneration`, whose only failure was an outdated parser punctuation expectation; the same test still completed real `prewarm()` + `rewrite()` and logged `Successfully generated result: Here is the list sorted in ascending order:`.
  implication: the local Qwen3.5 2B OptiQ load/generation path works in this environment, so the observed UI failure is more likely triggered by specific on-disk model state than by a universally broken loader/generator.

- timestamp: 2026-03-23T17:53:52Z
  checked: local downloaded model artifacts and `LLMRewriteService.isModelDownloaded`
  found: the current Qwen3.5 2B OptiQ directory contains `config.json`, `tokenizer.json`, `tokenizer_config.json`, `chat_template.jinja`, `optiq_metadata.json`, and weights, but `isModelDownloaded` only requires `config.json`, `tokenizer.json`, and weights.
  implication: interrupted/stale OptiQ downloads can be misclassified as downloaded, causing the app to skip redownload/warmup repair and hit a generic model-load error during rewrite.

- timestamp: 2026-03-23T17:54:57Z
  checked: new focused OptiQ artifact-detection tests
  found: before the fix, a directory containing only `config.json`, `tokenizer.json`, and `model.safetensors` was incorrectly reported as downloaded; after tightening required artifacts to include `tokenizer_config.json`, `chat_template.jinja`, and `optiq_metadata.json`, the focused tests passed.
  implication: this is a concrete, code-level root cause for late model-load failures after the Qwen3.5 OptiQ migration.

- timestamp: 2026-03-23T17:55:56Z
  checked: full `Speech2TextTests/LLMRewriteServiceTests` suite after the fix
  found: all 31 LLM rewrite service tests passed, including the real-model `testRealQwen2BModelGeneration`.
  implication: the fix closes the false-positive download detection gap without regressing the existing Qwen rewrite path in automated coverage.

## Resolution

root_cause: `LLMRewriteService.isModelDownloaded` still used the pre-OptiQ artifact check, so incomplete Qwen3.5 OptiQ model directories could be treated as valid and later fail during actual MLX model load in rewrite().
fix: Tightened downloaded-model detection for current OptiQ tiers to require `tokenizer_config.json`, `chat_template.jinja`, and `optiq_metadata.json` in addition to existing config/tokenizer/weights checks; added focused tests for incomplete vs current OptiQ artifact sets.
verification: Focused OptiQ artifact tests fail before the fix and pass after it; full `Speech2TextTests/LLMRewriteServiceTests` then passed with 31/31 tests, including the real-model generation test.
files_changed: ["Speech2Text/Conversion/LLMRewriteService.swift", "Speech2TextTests/LLMRewriteServiceTests.swift"]
