# Project Research Summary

**Project:** Speech2Test v1.1 — Local LLM transcript rewriting
**Domain:** macOS menu bar dictation utility — adding on-device LLM post-processing to an existing Whisper pipeline
**Researched:** 2026-03-18
**Confidence:** HIGH

## Executive Summary

Speech2Test v1.1 adds voice-triggered transcript rewriting to an already-shipping macOS dictation app. The integration is additive: a user speaks "convert to email [dictation]" or "[dictation] convert to email," Whisper transcribes it as usual, a pure string scan detects the intent and strips the trigger phrase, and a local Qwen2.5-1.5B-Instruct-4bit model (via mlx-swift-lm) rewrites the body and drops the result in the clipboard. The passthrough path for plain dictation is completely unchanged. All five rewriting modes (Clean English, Email, Slack/Teams, Action Items, Prompt) ship together as v1.1 — shipping a partial set would create documentation debt and user confusion.

The recommended approach is surgical: one new Swift actor (`LLMRewriteService`) mirrors the existing `WhisperService` pattern, one new folder (`Rewrite/`) holds four new source files, and three existing files are minimally modified. The key dependency addition is `mlx-swift-lm` 2.30.6 (SPM), which already has an MLX runtime present transitively through WhisperKit — so the incremental footprint is the language model layer only. Model download (~880 MB) is deferred to first use via lazy loading with visible progress in the menu bar status item; model weights are cached in `~/Library/Application Support/` for persistence across reboots.

The primary risk is a hard SPM version conflict: WhisperKit 0.17.0 pins `swift-transformers` at 1.1.x while mlx-swift-lm requires 1.2.0+. This must be resolved before any other work begins — it is a go/no-go gate for the entire v1.1 milestone. Secondary risks are LLM inference accidentally running on the `@MainActor` (freezing the pill UI), intent detection failing on real Whisper output due to casing and word-substitution artifacts, and the 869 MB model download providing no user feedback in a headless accessory app. All three have clear, documented prevention strategies that the architecture research explicitly addresses.

---

## Key Findings

### Recommended Stack

The existing stack (Swift 6, AppKit/SwiftUI, AVFoundation, WhisperKit, KeyboardShortcuts) is unchanged. The single new SPM dependency is `mlx-swift-lm` 2.30.6, adding the `MLXLLM` and `MLXLMCommon` products. Because WhisperKit already brings the MLX Swift runtime as a transitive dependency, this adds only the language model layer — no new runtime, no additional system entitlements (the app is not sandboxed), and no change to the macOS 14 deployment target.

**Core technologies:**
- `mlx-swift-lm` 2.30.6 (`MLXLLM` + `MLXLMCommon`): Local LLM inference — the only Swift-native MLX LLM library; Qwen2 architecture supported via `LLMTypeRegistry.shared`; SPM-only, no CMake or submodules
- `mlx-community/Qwen2.5-1.5B-Instruct-4bit`: Chosen model — 869 MB, 4-bit quantized, `model_type: qwen2`, ~0.39s average inference on M-series hardware, 32k context
- `ChatSession` high-level API (`MLXLMCommon`): Single-turn rewriting via `session.respond(to:)` — simpler than raw `generate()` streaming; appropriate for clipboard-output use case
- `loadModel(id:)` free function (`MLXLMCommon`): Handles download, progress, caching, and resumption; writes to `~/Library/Caches/huggingface/` automatically

**Critical version constraint:** `mlx-swift-lm` 2.30.6 requires `swift-transformers` 1.2.0+; WhisperKit 0.17.0 requires `swift-transformers` 1.1.x. These ranges are mutually exclusive. Check for a WhisperKit update that relaxes this bound as the very first step. See PITFALLS.md for fallback resolution paths.

### Expected Features

All five rewriting modes are P1 for v1.1 launch — they form a unified user-facing feature, not a menu of options to ship incrementally.

**Must have (table stakes):**
- No-trigger passthrough path completely unchanged — any regression here destroys trust in the existing feature
- Raw transcript as fallback on any LLM failure — silent fallback is correct for all failure modes except the 350-word limit breach
- Trigger phrase stripped from content before passing to LLM — "convert to email\n[body]" must never reach the model
- Case-insensitive intent detection — Whisper capitalises sentence-start words; "Convert to Email" and "convert to email" must both match
- 350-word gate with a visible user alert — the only path where the clipboard is not written; user must know why
- Atomic clipboard write — rewritten output replaces clipboard in one operation, never partial

**Should have (competitive advantage):**
- Voice-triggered mode selection at dictation time (prefix or suffix) — competitors require UI interaction before recording
- Fully local rewriting (~0.39s) — Wispr Flow is cloud-only; Superwhisper uses cloud for best quality
- Prompt mode — no audited competitor has a dedicated "structure as an LLM prompt" mode; highest differentiation for the target audience
- Structural output validation for Email (subject line present) and Action Items (bullet list start) with silent fallback to raw transcript on failure

**Defer (v2+):**
- Per-mode prompt customisation in settings UI
- Cloud LLM fallback (breaks privacy-first positioning)
- Rewrite history or undo (the raw transcript fallback is the recovery path)
- Fuzzy mode name matching (exact matching is safer; mode names are short and memorable)
- Custom mode support beyond the 5 built-in modes

### Architecture Approach

The integration inserts a branch point into the existing `finalizeSession()` flow inside `ActivationStore`, after Whisper returns a transcript and before the clipboard write. Intent detection is a pure synchronous function that returns a `ConvertIntent` enum — either `.passthrough` (existing path, unchanged) or `.rewrite(mode:body:)`. On `.rewrite`, the 350-word guard runs on the trigger-stripped body, then `LLMRewriteService.rewrite(body:mode:)` is awaited across an actor boundary, and the result goes to `ClipboardService`. The actor pattern mirrors `WhisperService` exactly: all MLX calls are serialized inside a non-`@MainActor` actor, preventing main-thread blocking.

**Major components:**
1. `IntentDetector` (new, pure function) — scans transcript for "convert to [mode]" prefix or suffix, case-insensitive, returns `ConvertIntent` with trigger-stripped body
2. `LLMRewriteService` (new, actor) — lazy model load on first use; owns `ChatSession`; exposes `rewrite(body:mode:)` behind `LLMRewriting` protocol for testability
3. `ConvertMode` (new, enum) — each case owns its `systemPrompt` and `userMessage(for:)`; prompt strings never appear in `ActivationStore`
4. `ActivationStore` (modified) — adds intent branch and 350-word guard inside existing `finalizeSession()`; injects `LLMRewriting` alongside existing `WhisperTranscribing`
5. `RecordingState` (modified) — adds `.conversionTooLong` to `FailureReason`

**Recommended build order:** `ConvertMode` + `ConvertIntent` types → `IntentDetector` + unit tests → `RecordingState` failure case → `LLMRewriteService` + tests → `ActivationStore` integration → pill/menu UI copy.

### Critical Pitfalls

1. **swift-transformers version conflict (WhisperKit vs mlx-swift-lm)** — verify `xcodebuild -resolvePackageDependencies` succeeds on a clean machine before writing any LLM code; if it fails, check for a WhisperKit update that accepts 1.2.0+; if none exists, vendor MLXLLM/MLXLMCommon source files directly into the project as a local target
2. **LLM inference on `@MainActor` starves the recording pipeline** — always call `llmService.rewrite()` from inside the existing `transcriptionTask` Task (already off-main); never from a `@MainActor` context directly; verify with Instruments that main thread CPU is near-zero during inference
3. **Intent detection fails on real Whisper output** — normalise transcript (lowercase, collapse whitespace, strip Whisper artifacts) before matching; use an explicit alternatives map per mode; validate with a corpus of 10+ real microphone recordings per trigger phrase, not hand-typed strings
4. **No model download feedback in a headless app** — update `NSStatusItem` title with "Downloading rewrite model X%..." during download; gate rewrite attempts with a clear alert if the model is not ready; store model in `~/Library/Application Support/Speech2Test/Models/` (not a purgeable temp path); verify file size after download
5. **Metal shader bundle missing in CI** — always build via `xcodebuild`, never `swift build`; MLX requires Xcode's build system to compile and embed `default.metallib`; add this constraint to the CI config comment before writing any inference code

---

## Implications for Roadmap

Based on research, the natural phase structure follows the dependency chain in the recommended build order, with the SPM conflict check as a mandatory gate before any other phase begins.

### Phase 1: Dependency Integration and Build Gate

**Rationale:** The swift-transformers version conflict is a go/no-go check for the entire feature. If it cannot be resolved, the integration path changes before any other work begins. The Metal shader CI constraint must also be locked in before the first inference code is written, or it will silently break CI later. Both items are cheap to verify and expensive to discover mid-development.

**Delivers:** A building Xcode project that includes `mlx-swift-lm` 2.30.6, passes clean dependency resolution on a machine with no Package.resolved, and builds successfully via `xcodebuild` in CI.

**Addresses:** Confirms the no-trigger passthrough path remains completely unchanged.

**Avoids:** Pitfall 1 (version conflict) and Pitfall 2 (Metal shader missing in CI).

**Research flag:** Check WhisperKit release notes for a version that accepts swift-transformers 1.2.0+ before Phase 1 begins. If no such version exists, research which MLXLLM/MLXLMCommon source files to vendor — a brief spike is needed before the phase plan is finalised.

---

### Phase 2: Core Types and Intent Detection

**Rationale:** `ConvertMode`, `ConvertIntent`, and `IntentDetector` are pure value types with no external dependencies. They can be built and fully tested before touching `ActivationStore` or MLX. Validating intent detection against real Whisper output early prevents a class of production bugs that only manifest on actual microphone recordings.

**Delivers:** Fully unit-tested intent detection validated against a corpus of real Whisper outputs (10+ recordings per mode trigger); `ConvertMode` enum with all five mode prompt templates; `ConvertIntent` return type that enforces trigger-phrase stripping at the type level.

**Implements:** `IntentDetector`, `ConvertMode`, `ConvertIntent`.

**Avoids:** Pitfall 5 (intent detection fragility on real Whisper output) and Pitfall 6 (trigger phrase preserved in LLM prompt).

**Research flag:** No additional external research needed — pure string matching with fully specified requirements. Skip `$gsd-research-phase` for this phase.

---

### Phase 3: LLMRewriteService Actor

**Rationale:** The LLM service can be developed and tested in isolation before being wired into `ActivationStore`. Separating it from the integration step makes actor boundary enforcement verifiable independently — a mock can stand in for `ChatSession` to test error paths, cancellation, and model-not-ready behavior without requiring the 880 MB model in CI.

**Delivers:** A fully functional `LLMRewriteService` actor with lazy model loading, `prepare()` guard, `Task.checkCancellation()` inside the generate loop, and `LLMRewriting` protocol conformance for injection.

**Uses:** `mlx-swift-lm` 2.30.6 (`MLXLLM` + `MLXLMCommon`), `ChatSession`, `loadModel(id:)`.

**Implements:** `LLMRewriteService`, `LLMRewriting` protocol.

**Avoids:** Pitfall 3 (main actor blocking) and the performance trap of re-loading the model from disk on every rewrite.

**Research flag:** `ChatSession` context bleed across dictations (identified in ARCHITECTURE.md anti-patterns) needs validation. Confirm whether a fresh `ChatSession` per rewrite call or a single-turn `generate()` API call is the correct pattern for mlx-swift-lm 2.30.6 before implementation begins.

---

### Phase 4: ActivationStore Integration and Word-Count Gate

**Rationale:** Integration is last among the core components because it depends on all prior phases. Adding the intent branch and LLM injection to `ActivationStore` is a small change once the types and services exist, but it is the highest-risk modification since it touches the shipping recording pipeline.

**Delivers:** End-to-end rewriting for all five modes; 350-word gate running on trigger-stripped body (not full raw transcript); graceful fallback to raw transcript on any LLM failure; `.conversionTooLong` failure state wired to pill and menu copy.

**Implements:** Modified `ActivationStore`, `RecordingState`, `RecordingPillView`, `StatusMenuView`.

**Avoids:** The pitfall of the 350-word check being applied to the full raw transcript (including the trigger phrase) rather than the stripped body.

**Research flag:** No additional research needed — integration follows directly from the architecture spec. Skip `$gsd-research-phase`.

---

### Phase 5: First-Run UX and Model Download Flow

**Rationale:** The 869 MB model download in a headless accessory app is the highest UX risk in the feature and cannot be treated the same as the 75 MB WhisperKit model. This phase is fifth because it requires the LLM service (Phase 3) and the failure state infrastructure (Phase 4) to exist, but it must ship as part of v1.1 — not deferred.

**Delivers:** Visible download progress via `NSStatusItem` title; model presence and file size verification before load attempts; model storage in `~/Library/Application Support/Speech2Test/Models/`; "Downloading rewrite model X%..." menu copy; clear alert when rewrite is attempted while model is downloading; warmup inference after download completes.

**Avoids:** Pitfall 4 (no download feedback in headless app) and the technical debt of storing the model in a purgeable temp path.

**Research flag:** The `swift-transformers` 1.2.0 download progress handler has a known issue (issue #335 in the swift-transformers repository). Verify whether this is fixed in the current release or requires a workaround before Phase 5 planning begins.

---

### Phase Ordering Rationale

- Phase 1 is a gate, not optional: the dependency graph must build before any ML code is written.
- Phase 2 before Phase 3: `ConvertMode` is a dependency of `LLMRewriteService` — it provides the system prompts and mode enum that the service uses.
- Phase 3 before Phase 4: `ActivationStore` injects `LLMRewriting` — the protocol and actor must exist before the integration can be wired.
- Phase 4 before Phase 5: the download UX gates rewrite attempts using the failure state infrastructure (`RecordingState.conversionTooLong` and the pill alert path) built in Phase 4.
- This order means each phase produces independently verifiable code before the next phase begins, and the highest-risk change (ActivationStore integration) happens only after all components are proven in isolation.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** swift-transformers conflict resolution — check WhisperKit release notes first; if unresolved, research which MLXLLM/MLXLMCommon source files to vendor into the project tree
- **Phase 3:** `ChatSession` context management — confirm single-turn API behavior and correct pattern for isolated per-dictation rewrites in mlx-swift-lm 2.30.6
- **Phase 5:** swift-transformers download progress handler — determine if issue #335 is resolved in 1.2.0 or if a custom progress polling approach is needed

Phases with standard patterns (skip `$gsd-research-phase`):
- **Phase 2:** Pure string matching with fully specified requirements and no external APIs
- **Phase 4:** ActivationStore integration follows directly from architecture spec; all component APIs established in prior phases

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All API signatures verified against live mlx-swift-lm source; version numbers confirmed via GitHub API; model config.json inspected directly; project.pbxproj confirms no sandbox entitlements |
| Features | HIGH (behavior) / MEDIUM (Slack alias edge cases) | Mode behavior and output contracts are well-specified; Whisper transcription variation of "Slack / Teams" is inferred from general Whisper behavior patterns, not a measured corpus |
| Architecture | HIGH | Based on direct reading of existing codebase (ActivationStore.swift, WhisperService.swift, RecordingState.swift); integration points are concrete and verified against actual file structure |
| Pitfalls | HIGH | swift-transformers conflict verified by reading both Package.swift files; Metal shader issue cited to official mlx-swift issue #349; MainActor risk confirmed by inspecting existing @MainActor ActivationStore constraint |

**Overall confidence:** HIGH

### Gaps to Address

- **swift-transformers version conflict resolution:** The exact resolution path (WhisperKit upgrade vs. vendoring MLXLLM source) cannot be determined without checking whether WhisperKit has released a version that accepts swift-transformers 1.2.0+. Resolve at Phase 1 start before any other work begins.
- **ChatSession per-call vs. per-session lifetime:** Whether reinitializing `ChatSession` per rewrite call has meaningful overhead versus using the single-turn `generate()` API needs validation against the actual mlx-swift-lm 2.30.6 runtime. Resolve at Phase 3 start.
- **Real Whisper output corpus for intent detection:** The alternatives map in PITFALLS.md (e.g. `.email` matches "e-mail", "emails", "an email") is derived from expected Whisper behavior, not a measured corpus. A corpus of 10+ real recordings per trigger phrase is required before Phase 2 is considered complete.
- **8 GB unified memory behavior:** Memory pressure behavior with both WhisperKit (tiny.en) and Qwen2.5-1.5B active has not been tested on 8 GB Apple Silicon machines. PITFALLS.md recommends `MLX.GPU.set(cacheLimit:)` as a mitigation — validate on minimum-spec hardware before shipping.

---

## Sources

### Primary (HIGH confidence)
- `mlx-swift-lm` repository and Package.swift — https://github.com/ml-explore/mlx-swift-lm — API signatures, products, platform targets, version 2.30.6
- `MLXLMCommon` source files (`Evaluate.swift`, `ChatSession.swift`, `ModelFactory.swift`) — verified via WebFetch against live repository
- `MLXLLM/LLMModelFactory.swift` — Qwen2 type registry entry confirmation
- `mlx-community/Qwen2.5-1.5B-Instruct-4bit` config.json — model_type, weight size (869 MB) — https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit
- `mlx-swift` release 0.30.6 and `mlx-swift-lm` release 2.30.6 and `swift-transformers` release 1.2.0 — GitHub API
- WhisperKit Package.swift — swift-transformers constraint `.upToNextMinor(from: "1.1.6")` — https://github.com/argmaxinc/WhisperKit/blob/main/Package.swift
- Existing codebase (`ActivationStore.swift`, `WhisperService.swift`, `ClipboardService.swift`, `RecordingState.swift`, `project.pbxproj`) — read directly
- `PROMPT_SPEC.md` — model selection rationale, latency benchmarks (~0.39s, ~130 tok/s on M4 Pro), 350-word limit rationale, mode prompt templates

### Secondary (MEDIUM confidence)
- Superwhisper modes documentation — https://superwhisper.com/docs/modes/ — pre-recording mode selection model, email and Slack output structure
- Wispr Flow features — https://wisprflow.ai/features — confirms cloud-only rewriting, automatic context detection, no voice-prefix switching
- OpenAI Whisper repository — https://github.com/openai/whisper — first-word capitalisation behavior informing case-normalisation requirement
- mlx-swift issues #274, #349 and mlx-swift-examples issues #172, #227, #230, #237 — pitfall evidence from official issue trackers

### Tertiary (LOW confidence)
- swift-transformers issue #335 (download progress handler broken in 1.2.0) — needs validation against current 1.2.0 release before Phase 5
- Slack/Teams alias set ("Slack Teams", "Slack or Teams") — inferred from Whisper transcription patterns, not measured; validate with real recordings in Phase 2

---
*Research completed: 2026-03-18*
*Ready for roadmap: yes*
