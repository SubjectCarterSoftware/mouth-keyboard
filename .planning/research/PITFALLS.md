# Pitfalls Research

**Domain:** Adding MLX-based local LLM inference to an existing macOS Swift dictation app
**Researched:** 2026-03-18
**Confidence:** HIGH (most findings verified against source code, official issue trackers, and Package.swift dependency constraints)

---

## Critical Pitfalls

### Pitfall 1: WhisperKit and mlx-swift-lm Require Incompatible Versions of swift-transformers

**What goes wrong:**
SPM dependency resolution fails — or produces a corrupt lock — when you add mlx-swift-lm alongside the existing WhisperKit dependency. WhisperKit 0.17.0 specifies swift-transformers `.upToNextMinor(from: "1.1.6")`, meaning it accepts 1.1.x and rejects anything 1.2.0 or higher. mlx-swift-lm specifies swift-transformers `from: "1.2.0"`, meaning it requires exactly 1.2.0 or higher. These version ranges do not overlap. SPM cannot satisfy both at the same time.

The project's current Package.resolved pins swift-transformers at 1.1.9 — the version WhisperKit installed. Adding mlx-swift-lm as an SPM dependency will either produce a hard "dependency graph could not be resolved" error, or Xcode will silently keep 1.1.9 and build mlx-swift-lm against it, which may produce binary mismatches or tokenizer runtime failures that are hard to diagnose.

**Why it happens:**
Developers add `mlx-swift-lm` to the project's package dependencies in Xcode, watch it appear to resolve, and assume everything is fine. The breakage surface is either on a clean machine (where the locked version is recalculated) or at runtime when mlx-swift-lm calls tokenizer APIs that changed in 1.2.0.

**How to avoid:**
Before writing a single line of LLM code, run `xcodebuild -resolvePackageDependencies` on a machine with no existing Package.resolved and confirm it exits zero. If it fails, choose one of these paths — in order of preference:

1. Check whether a newer WhisperKit release has relaxed its swift-transformers upper bound. If WhisperKit has been updated to accept 1.2.0+, update the WhisperKit pin and the conflict disappears.
2. If WhisperKit cannot be upgraded, copy the relevant MLXLLM and MLXLMCommon Swift source files directly into the project as local source rather than a remote SPM dependency. This sidesteps the version conflict entirely at the cost of manual updates.
3. Replace WhisperKit with a direct whisper.cpp build (which has no swift-transformers dependency at all) — this is a larger change but produces a clean dependency graph.

Do not attempt to force-pin swift-transformers to a single version that claims to satisfy both — the constraints are mutually exclusive.

**Warning signs:**
- `xcodebuild -resolvePackageDependencies` exits non-zero after adding mlx-swift-lm
- Xcode shows "the package dependency graph could not be resolved" in the Swift Packages list
- A clean build on a second machine fails even though local builds appear to work (stale Package.resolved mask)
- Build log shows swift-transformers being compiled twice at different versions

**Phase to address:**
Phase 1 (dependency integration). This is the first thing to verify — it is a go/no-go check. If the conflict cannot be resolved by a WhisperKit upgrade, the integration path changes before any other work begins.

---

### Pitfall 2: Metal Shader Bundle Missing When Building Outside Xcode's Standard Flow

**What goes wrong:**
MLX requires pre-compiled Metal shaders embedded as `mlx-swift_Cmlx.bundle/default.metallib`. When building via `swift build` on the command line, this bundle is never generated. The app builds without error but crashes at the first MLX call with "Failed to load the default metallib (library not found)." This also affects CI pipelines that use `swift build` as a build gate, and any build orchestration tool (Tuist, Makefile, custom scripts) that does not invoke Xcode's full build system.

**Why it happens:**
SwiftPM has no mechanism to invoke the Metal shader compiler. Xcode handles this automatically by recognizing `.metal` sources and running `xcrun metal` during the standard build phase. The MLX maintainers have explicitly documented this: "swiftpm has no mechanism to build the metal shaders or the metalib. It is not just that they are not declared." Because the project already uses Xcode rather than standalone SPM, this is lower risk in development — but CI is the failure point.

**How to avoid:**
Always build through Xcode or `xcodebuild`. In CI:
```
xcodebuild -scheme Speech2Text -destination "platform=macOS" build
```
Never use `swift build` as a correctness check for this project after MLX is added. Document this constraint in the repository and add a comment in the Makefile or CI config if one exists.

**Warning signs:**
- CI pipeline uses `swift build` and was working before MLX was added
- Runtime crash immediately on first inference even though compilation succeeded
- Error message references "metallib", "Cmlx.bundle", or "Failed to load the default metallib"
- Works on the developer's machine (Xcode build) but fails in CI (swift build)

**Phase to address:**
Phase 1 (dependency integration). Lock down the CI build command before writing any inference code.

---

### Pitfall 3: LLM Inference Called from a `@MainActor` Context Starves the Recording Pipeline

**What goes wrong:**
If inference is placed inside `ActivationStore` (which is `@MainActor`) or called directly from the `finalizeSession` method without crossing an actor boundary, the synchronous portions of MLX evaluation occupy the main thread. During inference, no other work on `@MainActor` can run: hotkey presses are queued and delivered late, UI state updates are delayed, pill animations freeze, and the app appears unresponsive. The `generate()` API from MLXLMCommon uses `AsyncSequence` and is async at the Swift level, but each token iteration calls into synchronous C++/Metal evaluation that takes ~7ms. At 130 tokens/s for a 150-token rewrite, this is ~60 individual blocking steps spread across the async loop, each resuming on the main thread if that is where the call lives.

**Why it happens:**
Developers see `for await token in generate(...)` and assume the `await` fully yields to other work. It does yield between iteration steps, but Swift's structured concurrency resumes a continuation on the actor that owns the suspension point. If the `finalizeSession` task runs on `@MainActor`, every `await` inside it that resumes goes back to the main thread. The existing `WhisperService` pattern — a dedicated `actor` — is the correct template and should be replicated for the LLM service.

**How to avoid:**
Introduce a dedicated `LLMService` actor (not `@MainActor`) that owns model loading and the `generate()` call. The `ActivationStore.finalizeSession` method should `await llmService.rewrite(transcript:mode:)` — this crosses the actor boundary and runs inference on the `LLMService` actor's isolated executor, off the main thread. Do not use `Task.detached` as a substitute for proper actor isolation; detached tasks have no structured cancellation relationship with the calling context.

**Warning signs:**
- Hotkey press during inference is silently ignored or triggers a session that starts late
- The pill UI freezes during the rewrite window
- Instruments shows the main thread blocked on a Metal kernel during the `processing` state
- `CADisplayLink` frame rate drops to near zero during inference

**Phase to address:**
Phase 2 (LLM service design). Enforce the actor boundary in the service design before wiring it to `ActivationStore`.

---

### Pitfall 4: First-Run Model Download Produces No Feedback in a Background-Only App

**What goes wrong:**
The 869 MB model is either downloaded silently at launch (following the `WhisperService.shared.prepare()` pattern) with no user feedback, or it is downloaded lazily on first "convert to X" but there is no mechanism to surface progress in a background accessory app. The user hears the failure sound, sees no explanation, and cannot tell whether the rewrite feature is broken permanently or just loading. In the worst case, a download is interrupted (network drop, sleep), leaves a partial file, and every subsequent "convert to X" attempt silently re-fails until the user manually deletes the partial file.

**Why it happens:**
The existing Whisper model is ~75 MB (tiny.en) and downloads quickly enough that a brief delay is acceptable. The Qwen model is 12x larger and cannot be treated the same way. The HuggingFace Hub downloader in swift-transformers does support progress reporting but only via a callback — a background accessory app has no window or sheet to attach a progress view to by default.

**How to avoid:**
Use a lazy download strategy triggered on first "convert to X" intent detection, not at launch. Before any download:

1. Check whether the model is already fully present on disk (`FileManager.default.fileExists` at the storage path).
2. If absent, initiate the download in a background `Task` and report progress via `NSStatusItem` title updates (e.g. "Downloading rewrite model 34%…") and a dedicated menu item.
3. Store the model in `~/Library/Application Support/Speech2Text/Models/` — not a temp directory that macOS may purge.
4. After the download completes, verify file size against the known size (869 MB) before attempting to load — partial downloads must be detected and deleted.
5. After a verified download, run a cheap warmup inference (5-word test prompt) to pre-allocate GPU memory.
6. Gate rewrite attempts: if the model is downloading or not yet present, show a clear alert ("Rewrite model is downloading, try again in a moment") and skip the LLM call.

**Warning signs:**
- Model path existence is not checked before initiating a download
- Download is fired unconditionally from `applicationDidFinishLaunching`
- No menu item or `NSStatusItem` text exists for download state
- No file size or hash check after download completes
- The app has no recovery path for partially downloaded files

**Phase to address:**
Phase 3 (model download and first-run UX). Design this before wiring the LLM into the recording flow — the recording flow must gracefully skip the LLM when the model is not ready.

---

### Pitfall 5: Intent Detection Breaks on Real Whisper Output

**What goes wrong:**
Naive intent matching works perfectly in unit tests with hand-typed strings and breaks in production against real Whisper output. Whisper with `tiny.en` introduces casing variations, spacing artifacts, and word substitutions that defeat simple string matching. Observed real-world variations of "convert to email" include: "convert to e-mail", "convert to Email", "converttoo email", "convert 2 email", "can vert to email." A simple `text.lowercased().hasPrefix("convert to email")` match fails all of these.

False positives are equally dangerous: "convert to a more professional email tone" contains "email" after "convert to" but is not a trigger for the `.email` mode. Stripping everything after "convert to" from this would destroy the actual dictation content.

The 350-word check against the full raw transcript (before stripping the trigger phrase) will incorrectly fail a 300-word dictation prefixed by a 10-word trigger phrase, blocking a valid rewrite request.

**Why it happens:**
Developers build and test intent detection with copy-pasted clean strings. The `tiny.en` model is particularly prone to substitutions on short, precise functional phrases because they have low contextual support — the model may hear "convert" as a standalone word and make a different prediction than in a longer utterance. Testing with real hardware recordings is skipped because it is slower to set up.

**How to avoid:**
Implement normalization as a first step: lowercase, collapse multiple spaces to one, strip Whisper-specific artifacts (`[BLANK_AUDIO]`, leading/trailing whitespace, punctuation that Whisper adds around functional words). Match prefix AND suffix independently (the spec allows trigger at start or end). For mode name matching, use an explicit allowed-alternatives map per mode:

- `.cleanEnglish`: `{"clean english", "clean", "clean text"}`
- `.email`: `{"email", "e-mail", "emails", "an email"}`
- `.slack`: `{"slack", "slack message", "teams", "teams message", "slack or teams"}`
- `.actionItems`: `{"action items", "action item", "actions", "tasks"}`
- `.prompt`: `{"prompt", "ai prompt", "a prompt"}`

Do not use fuzzy string distance matching — edit distance thresholds produce false positives on short mode names. Build a deterministic unit test suite over a pre-captured corpus of real Whisper outputs for each trigger phrase and run it on CI. Apply the 350-word check on the transcript *after* removing the trigger phrase.

**Warning signs:**
- Intent detection tests use hand-typed strings rather than real Whisper recordings
- No normalization step before `hasPrefix` / `hasSuffix` / `contains` check
- Word count check runs on the full raw transcript before stripping the trigger phrase
- No alternatives map — each mode is matched by exactly one string

**Phase to address:**
Phase 2 (intent detection). Validate with a corpus of real Whisper outputs before integration testing begins.

---

### Pitfall 6: Trigger Phrase Not Stripped from the Content Sent to the LLM

**What goes wrong:**
The trigger phrase detection and the content preparation for the LLM are treated as independent steps, and the stripping step is forgotten or applied to the wrong string. The LLM receives "convert to email\n\nI want to follow up on our meeting..." and produces output that begins with "Subject: Convert to Email" or includes "convert to email" as part of the rewritten content. This is invisible in development where tests construct the prompt manually, and only visible when the full pipeline runs end-to-end.

**Why it happens:**
Stripping the trigger phrase feels like a trivial cleanup step so it gets deferred, added as an afterthought, or added to the wrong place in the pipeline (stripping from the displayed text but not from the `text` variable passed to the LLM).

**How to avoid:**
The intent detection function should return both the detected mode and the cleaned content as a single result type:

```swift
struct DetectedIntent {
    let mode: ConvertMode
    let content: String  // transcript with trigger phrase removed and trimmed
}
```

The `content` field on this struct is the *only* string that ever reaches the LLM prompt. Never pass the raw transcript to the LLM. Assert in debug builds that the content does not start or end with any of the known trigger phrases.

**Warning signs:**
- The LLM prompt is constructed from the raw transcript string rather than a cleaned content string
- Intent detection returns only a mode, not the cleaned content
- LLM output in testing includes words like "convert", "email", "slack" at the start of the rewritten text

**Phase to address:**
Phase 2 (intent detection and prompt construction). The `DetectedIntent` return type enforces this contract from the start.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Load model on first "convert" call, not at launch | No startup impact | User experiences 2-4s latency on first rewrite (cold load + inference) | Acceptable for v1.1 — mitigate with a clear loading indicator |
| Single model instance shared as app-lifetime singleton | Simpler code | Concurrent session risk (not currently possible given single-session architecture) | Acceptable given current architecture; reassess if multi-session is ever added |
| String-matching with a fixed alternatives map per mode | Fast to implement and test | Breaks if new Whisper model behaves differently; requires manual update for new modes | Acceptable for 5 fixed modes; must be revisited if modes become dynamic |
| Store model in Application Support without user-accessible cleanup | Simpler first pass | User cannot reclaim 869 MB without knowing the file path | Never: always add a "Remove downloaded model" menu item |
| Skip Task cancellation checks inside the `generate()` loop | Simpler initial integration | App cannot cancel a slow rewrite; hotkey during processing either hangs or delivers stale output | Never: cancellation checks must be wired before the feature ships |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| mlx-swift-lm + WhisperKit via SPM | Adding both as remote dependencies and assuming version resolution works | Verify swift-transformers constraints are compatible before writing code; vendor MLXLLM source if they are not |
| MLXLMCommon `generate()` from `ActivationStore` | Calling from `@MainActor`, blocking UI | Wrap in a dedicated non-`@MainActor` actor; call across the actor boundary from `finalizeSession` |
| Model download via Hub API | Assuming Hub errors surface as thrown errors and propagate cleanly to the caller | Hub errors may fail silently if not explicitly caught; wrap every download call in `do/catch` and store error state for the menu bar to observe |
| Intent extraction + 350-word limit | Counting words on the full transcript including the trigger phrase | Strip trigger phrase first, then count; the 350-word limit applies to the content body only |
| First-run download in a background-only app | Launching a progress sheet attached to a window | Use `NSStatusItem` title updates or `NSUserNotification` for headless progress reporting |
| MLX model warmup (loading weights into GPU memory) | Warming up once and assuming it stays warm across long idle periods | macOS may page out GPU allocations under memory pressure; add a ready-check before inference and re-warm if needed |
| swift-transformers version pinning | Force-pinning to satisfy both constraints simultaneously | The constraints are mutually exclusive — see Pitfall 1 for the only valid resolution paths |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Re-loading the model from disk on every rewrite | 2-4s latency spike on every "convert" call | Load once at download-completion or on first use; keep `ModelContainer` alive for the app lifetime | The first time a user does two rewrites back-to-back |
| Running Whisper and MLX inference concurrently on the GPU | GPU memory pressure, kernel timeouts (`[Event::wait] Timed out at array.cpp`) | Sequence them: Whisper finishes fully before LLM begins (the existing pipeline already does this — preserve it) | Only a risk if the pipeline is restructured to allow overlap |
| No `maxTokens` ceiling on generation | Rewrite takes 2-3x longer than expected for verbose outputs | Set `maxTokens` to a conservative ceiling (500 tokens) in `GenerateParameters`; model EOS usually fires well before this | When the model produces a preamble or explanation before the actual rewrite |
| Not setting GPU cache limit before inference | System memory pressure, possible OOM kill on machines with 8 GB unified memory | Call `MLX.GPU.set(cacheLimit:)` with a ceiling (e.g. 2 GB) before loading the model | On 8 GB machines running other GPU workloads simultaneously |
| Not prewarming after download | First rewrite takes 3-5s (cold model load to GPU + inference time) | After download completes, run a cheap warmup inference (5-word prompt) to pre-allocate GPU memory | The very first "convert to X" after the model finishes downloading |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No progress feedback during 869 MB model download | User believes the rewrite feature is broken; tries "convert to email" and gets a failure sound | Update `NSStatusItem` title with "Downloading… X%" during download; gate rewrite attempts and show a specific alert if the model is not ready |
| Rewrite failure indistinguishable from transcription failure | User cannot tell whether Whisper failed or the LLM failed | Add a `.rewriteFailed` failure reason variant to `RecordingState` so the pill copy is specific |
| Silent fallback to raw transcript when LLM fails | User believes they received a rewritten version but got the unmodified transcript | Either surface the error explicitly or make the fallback behavior visible; never silently substitute without user awareness |
| No 350-word alert when dictation is too long | User says a long "convert to email" dictation, hears a failure sound with no explanation | Trigger the alert immediately after intent detection and word count check; the alert copy must reference the word limit explicitly (spec: "Recording too long for conversion — max ~350 words") |
| Trigger phrase preserved in clipboard output | User gets "convert to email\n[email body]" pasted into their app | Strip the trigger phrase before building the LLM prompt — not as a post-processing step on the output |

---

## "Looks Done But Isn't" Checklist

- [ ] **SPM dependency resolution:** Verify `xcodebuild -resolvePackageDependencies` succeeds on a clean machine with no Package.resolved present — not just with the existing locked file
- [ ] **Metal shader bundle:** Verify the app launches and runs inference correctly after `xcodebuild clean` — not just after an incremental Xcode build
- [ ] **Intent detection corpus:** Verify intent detection runs against actual Whisper `tiny.en` outputs captured from a real microphone — at least 10 recordings per mode trigger phrase, not hand-typed strings
- [ ] **Trigger phrase stripping:** Verify the content sent to the LLM does not include the "convert to X" phrase — inspect the actual prompt string in a debug build or unit test
- [ ] **350-word check placement:** Verify the word count runs on the stripped content, not the full raw transcript — unit test: 340-word dictation with a 10-word trigger phrase should NOT trigger the alert
- [ ] **Model persistence:** Verify the downloaded model survives app restart — path must be in `~/Library/Application Support/`, not a temp directory
- [ ] **First-run feedback:** Verify a user whose model is not present gets visible progress feedback during download — not just a failure sound
- [ ] **Cancellation during inference:** Verify that cancelling a recording session while LLM inference is in flight stops the rewrite and does not deliver any output to the clipboard
- [ ] **No-trigger path regression:** Verify plain dictation (no "convert to" prefix/suffix) still produces raw transcript in clipboard — no LLM involvement, no latency increase
- [ ] **Actor isolation in Instruments:** Verify main thread CPU is near zero during inference — the main thread should not block while `generate()` runs

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| swift-transformers version conflict blocks SPM resolution | HIGH | Check for a newer WhisperKit that accepts 1.2.0+; if none exists, vendor MLXLLM source files into the project tree and remove the remote SPM dependency |
| Metal shader bundle missing in CI | LOW | Switch CI from `swift build` to `xcodebuild -scheme Speech2Text build`; one-time change |
| LLM inference blocking main thread | MEDIUM | Extract `LLMService` actor, move inference there, rewire `ActivationStore` to `await` across the boundary — approximately 2 hours of refactoring once the design is clear |
| Model stored in a purgeable path | MEDIUM | Move storage to Application Support, add a migration check on launch to relocate existing downloads |
| Intent detection false positives / negatives in production | MEDIUM | Expand the alternatives map and normalization rules; add the failing Whisper output to the corpus test suite to prevent regression |
| Partial or corrupt model download | LOW | Add a file size check after download; on mismatch, delete and re-download; surface a notification to the user |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| swift-transformers version conflict (WhisperKit vs mlx-swift-lm) | Phase 1: Dependency Integration | Clean `xcodebuild -resolvePackageDependencies` succeeds on a machine with no Package.resolved |
| Metal shader bundle missing outside Xcode | Phase 1: Dependency Integration | CI build uses `xcodebuild`; clean build produces a working binary that loads MLX |
| LLM inference blocking the main actor | Phase 2: LLM Service Design | Instruments trace shows main thread near-zero CPU during inference; hotkey responds while rewrite runs |
| Intent detection fragility on Whisper output | Phase 2: Intent Detection | Corpus test suite passes with 10+ real recordings per mode; CI runs this suite |
| Trigger phrase not stripped from LLM prompt | Phase 2: Intent Detection + Prompt Construction | Unit test asserts prompt content does not contain trigger phrase text |
| 350-word check applied to wrong string | Phase 2: Intent Detection | Unit test: 340-word body + trigger phrase does not trigger the alert |
| No model download feedback in a headless app | Phase 3: First-Run UX | Manual test on fresh environment: visible status item progress before, during, and after download |
| Model stored in a purgeable path | Phase 3: First-Run UX | Storage path is `~/Library/Application Support/Speech2Test/Models/`; verified to survive system restart |
| No cancellation support inside `generate()` loop | Phase 2: LLM Service Design | Cancel during `processing` state mid-inference; clipboard unchanged after cancel |
| Model re-loaded from disk on every rewrite | Phase 2: LLM Service Design | Two consecutive rewrites; second is measurably faster than first (warmup already done) |

---

## Sources

- WhisperKit Package.swift — verified swift-transformers constraint `.upToNextMinor(from: "1.1.6")` at WhisperKit 0.17.0 — https://github.com/argmaxinc/WhisperKit/blob/main/Package.swift
- mlx-swift-lm Package.swift — verified swift-transformers requirement `from: "1.2.0"` and macOS 14 minimum — https://github.com/ml-explore/mlx-swift-lm
- Project Package.resolved — swift-transformers 1.1.9 currently pinned by existing WhisperKit 0.17.0 dependency
- mlx-swift issue #349: default.metallib bundle missing when using non-Xcode build tools — https://github.com/ml-explore/mlx-swift/issues/349
- mlx-swift troubleshooting docs: "SwiftPM cannot build the Metal shaders" — https://github.com/ml-explore/mlx-swift
- mlx-swift issue #274: MLX crash on background GPU eval ("Insufficient Permission to submit GPU work from background") — https://github.com/ml-explore/mlx-swift/issues/274
- mlx-swift-examples issue #230: handling inactive app states during Metal inference — https://github.com/ml-explore/mlx-swift-examples/issues/230
- mlx-swift-examples issue #227: canceling ongoing generation via `Task.checkCancellation()` — https://github.com/ml-explore/mlx-swift-examples/issues/227
- mlx-swift-examples issue #172: `[Event::wait] Timed out at array.cpp` from memory pressure — https://github.com/ml-explore/mlx-swift-examples/issues/172
- mlx-swift issue #237: UI rendering stuck and crash during repeated device switching — https://github.com/ml-explore/mlx-swift/issues/237
- mlx-swift README: duplicate linking warning for complex dependency chains — https://github.com/ml-explore/mlx-swift
- swift-transformers issue #335: download progress handler broken in 1.2.0 — https://github.com/huggingface/swift-transformers/issues
- Hugging Face model card: mlx-community/Qwen2.5-1.5B-Instruct-4bit — download size 869 MB — https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit
- PROMPT_SPEC.md: model evaluated at ~0.39s average latency, ~130 tokens/s on M4 Pro 24 GB with MLX 0.31.1
- ActivationStore.swift: existing `finalizeSession` pipeline, `@MainActor` constraint, session ID guard pattern
- WhisperService.swift: existing `actor` isolation pattern — the correct template for `LLMService`

---
*Pitfalls research for: Adding MLX local LLM inference to an existing macOS Swift dictation app (Speech2Test v1.1)*
*Researched: 2026-03-18*
