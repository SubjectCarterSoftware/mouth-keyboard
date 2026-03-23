---
status: awaiting_human_verify
trigger: "Investigate issue: rewrite-tier-download-cancels"
created: 2026-03-23T00:00:00Z
updated: 2026-03-23T00:30:00Z
---

## Current Focus

hypothesis: Confirmed — stale partial rewrite model directories need to be removed before retrying a tier download; idle-only rewrite model management is already present in the current settings/recording-state code.
test: Have the user retry 4B/9B download/selection from Settings while idle, then confirm model controls stay disabled during active recording/transcription/conversion.
expecting: 4B/9B downloads should proceed from a clean directory, remain selectable once complete, and rewrite model controls should stay unavailable until the app returns to idle.
next_action: wait for human verification in the real app workflow

## Symptoms

expected: From settings, when the app is idle, the user can download 4B or 9B rewrite tiers, then select them for future assistant-triggered rewrites. Switching should not conflict with active recording/transcription/conversion, and the chosen tier should prewarm on next session and idle-unload later.
actual: Clicking download for 4B/9B starts for a second and then cancels/stops. The user cannot reliably download or assign those tiers.
errors: No specific error text provided; UI appears to start then cancel.
reproduction: Open settings and click download on 4B or 9B rewrite tier.
started: Discovered after the base assistant-triggered rewrite path started working.

## Eliminated

## Evidence

- timestamp: 2026-03-23T00:05:00Z
  checked: SetupWindowView.swift conversion model controls
  found: Download action calls RewriteModelLoadState.startDownload(for: tier); a 3-second timer repeatedly calls modelLoadState.refreshStatus() but the action button is only disabled by transfer/deletion state.
  implication: The cancellation is unlikely to come directly from the UI button; investigate underlying load state/service interactions.

- timestamp: 2026-03-23T00:05:00Z
  checked: RewriteModelLoadState.swift
  found: startDownload(for:) cancels any previous local downloadTask, sets phase to downloading, and calls static LLMRewriteService.downloadModelFiles(for:) rather than the actor instance. refreshStatus() only recomputes downloaded tiers and warm tier.
  implication: A separate code path would be needed to cancel or invalidate the actual file transfer; inspect LLMRewriteService static download implementation and actor lifecycle.

- timestamp: 2026-03-23T00:10:00Z
  checked: LLMRewriteService.swift tier/download lifecycle
  found: setTier(_:) and unload() cancel only model loadTask/cached model, not fileDownloadTasks; file downloads are keyed by tier and persist independently until completion or deleteDownloadedModel(for:).
  implication: The 4B/9B transfer is probably not being canceled by model warm/unload logic itself; investigate who changes visible phase or whether the UI is triggering a second action.

- timestamp: 2026-03-23T00:18:00Z
  checked: local Application Support rewrite model directories
  found: the 4B tier directory already exists on disk but is incomplete (`config.json`, `model.safetensors*`, `optiq_metadata.json`, `tokenizer.json`, `tokenizer_config.json`, no `chat_template.jinja`), while 2B is complete and 9B is absent.
  implication: the observed “starts briefly then stops” behavior matches retrying against a stale partial 4B directory instead of forcing a clean re-download; add incomplete-download repair before starting a new transfer.

- timestamp: 2026-03-23T00:18:00Z
  checked: SetupWindowView.swift and ActivationStore.swift interaction
  found: the current settings code already gates rewrite model selection/download/delete on `activationStore.state.allowsRewriteModelManagement`, and `RecordingState` limits that to `.idle`; activation warmup later sets the selected tier on arm().
  implication: idle-state gating already exists in the current working tree, so the remaining user-facing bug is the stale partial-download retry path.

- timestamp: 2026-03-23T00:30:00Z
  checked: LLMRewriteService.swift and focused unit tests
  found: `downloadFiles(for:)` now removes incomplete tier directories before starting a fresh download; focused tests passed for removing a partial 4B directory, preserving a complete 4B directory, and confirming only idle state allows rewrite model management.
  implication: the code now directly repairs the stale on-disk state that caused brief-start/stop retries, and automated coverage exists for both the cleanup path and idle-only management semantics.

## Resolution

root_cause: Incomplete rewrite tier directories can remain on disk after interrupted downloads, and retrying a download reuses that stale directory instead of forcing a clean snapshot. Local evidence showed the existing 4B directory was missing `chat_template.jinja`, matching the “starts briefly then stops” symptom.
fix: Added `LLMRewriteService.deleteIncompleteDownloadedModelFilesIfNeeded(...)` and invoke it before starting a new tier download so stale partial directories are removed before retry. Verified that idle-only rewrite model management already exists in the current settings UI via `activationStore.state.allowsRewriteModelManagement`.
verification:
Focused xcodebuild runs passed:
- `Speech2TextTests/LLMRewriteServiceTests/testDeleteIncompleteDownloadedModelFilesIfNeededRemovesPartialTierDirectory`
- `Speech2TextTests/LLMRewriteServiceTests/testDeleteIncompleteDownloadedModelFilesIfNeededPreservesCompleteTierDirectory`
- `Speech2TextTests/LLMRewriteServiceTests/testOnlyIdleAllowsRewriteModelManagement`
files_changed: ["Speech2Text/Conversion/LLMRewriteService.swift", "Speech2TextTests/LLMRewriteServiceTests.swift"]
