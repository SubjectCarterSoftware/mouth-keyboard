# Proposal: Resource Lifecycle Management & Stability (Revised)

**Date:** 2026-03-22
**Scope:** 5 connected issues. The first 3 are shared runtime/lifecycle work. The last 2 are stability and maintainability follow-ups that surfaced in the same audit.
**Estimated effort:** Medium-to-large. This is not a small-agent cleanup batch.

---

## Why this document was revised

This revision corrects several important assumptions from the earlier draft:

- Whisper and rewrite-model preparation are not "first use" behaviors today; both are kicked off at launch.
- `RewriteExecutionGate` is not obviously redundant. The current rewrite flow suspends while streaming generation output, so actor isolation alone does not guarantee non-overlap.
- `AudioCaptureService.stop()` does stop the engine and remove the tap; the remaining concern is long-lived object reuse, not a proven permanent device lock.
- OOM fallback should stay targeted to memory-related failures, not "any load failure".

The revised proposal separates immediate, low-risk lifecycle wins from the larger coordinator design that should come later.

---

## Current code facts that the design must respect

Before proposing changes, these are the important current behaviors in the codebase:

1. `AppDelegate` eagerly calls `WhisperService.shared.prepare()` on launch.
2. `AppDelegate` also kicks off rewrite-model download/load-state work on launch via `RewriteModelLoadState.shared.startDownload(...)`.
3. `LLMRewriteService.download()` ends by populating `cachedModel`, so "downloaded" and "resident in RAM" are currently conflated.
4. `applicationWillTerminate` currently stops hotkeys and Combine subscriptions, but does not explicitly unload ML resources.
5. `RewriteExecutionGate` currently enforces single active rewrite generation, and the test suite already asserts that concurrent rewrites must not overlap.
6. `AudioCaptureService.stop()` removes the tap and stops the engine, but intentionally retains the engine object for reuse.

Any lifecycle design that ignores those facts will look coherent on paper and still be wrong in this codebase.

---

## 1. Coordinated resource lifecycle management

### 1a. Rewrite model lifecycle: eager startup work plus indefinite residency

**Where:** `Speech2Text/Conversion/LLMRewriteService.swift`, `Speech2Text/Conversion/RewriteModelLoadState.swift`, `Speech2Text/App/AppDelegate.swift`

**Current problem:** The app begins rewrite-model work at launch, and `LLMRewriteService` keeps `cachedModel` resident until tier change or app exit. There is no general unload path. This creates two separate issues:

- high RAM residency after the first successful load, and
- no clean distinction between "model files exist on disk" and "model is currently resident in memory".

That second point matters because `RewriteModelLoadState` currently reports readiness as if download state and in-memory residency were the same thing.

**Why that matters for the design:** If the app later evicts the model from RAM, the UI/state layer must not keep pretending the model is still warm in memory. Otherwise the system will report "ready" but still pay a cold-load penalty on the next rewrite.

### 1b. Whisper lifecycle: eagerly prepared at launch, never explicitly unloaded

**Where:** `Speech2Text/Transcription/WhisperService.swift`, `Speech2Text/App/AppDelegate.swift`

**Current problem:** Whisper is eagerly prepared at app launch and then retained indefinitely via `pipe` unless another model replaces it. There is no explicit unload path and no load-task sharing model equivalent to the rewrite service's `loadTask`.

**Why that matters for the design:** Whisper is a meaningful resident-memory consumer even when the user is not actively dictating. If the app wants to unload it later, the service first needs a stronger lifecycle contract than the current `isLoading` flag.

### 1c. Audio engine lifecycle: reuse optimization without a bounded release policy

**Where:** `Speech2Text/Audio/AudioCaptureService.swift`

**Current problem:** `stop()` removes the tap and stops the engine, but intentionally keeps the `AVAudioEngine` instance alive for reuse. That avoids fast re-press races, but there is no explicit idle-release policy and no termination-time release hook.

**Important correction:** The earlier draft described this as a proven long-lived device lock. The code alone does not prove that. The engine is stopped and the tap is removed. The remaining concern is that the app keeps audio resources around longer than necessary and has no explicit policy for when to fully tear them down.

**Why that matters for the design:** This still deserves cleanup, but it should be driven by measurement and clear reuse policy, not by an unverified assumption about permanent hardware locking.

### Design constraints for all three resources

A realistic lifecycle design needs to answer these questions together:

- What is the preload policy at launch? Keep current eager behavior, make it conditional, or move it behind a coordinator?
- What state model distinguishes on-disk availability from warm in-memory residency?
- What is the unload ordering when multiple resources are resident?
- What happens if a new request arrives while an unload is in flight?
- Which lifecycle actions are always safe at `applicationWillTerminate`?
- What memory/latency tradeoff is acceptable on low-RAM machines versus larger machines?

### Suggested staged approach

#### Stage A: immediate wins with low design risk

1. Add explicit `unload()` APIs to `LLMRewriteService` and `WhisperService`.
2. Add an explicit release path to `AudioCaptureService` (for example `releaseEngine()`), even if the default runtime policy still keeps a short reuse window.
3. Call those unload/release paths from `AppDelegate.applicationWillTerminate`.
4. Split the notion of "available" versus "resident" in `RewriteModelLoadState` if UI state needs to remain accurate after eviction.
5. Add lightweight instrumentation for load time, unload time, and last-used timestamps before building a smarter policy.

This stage can ship before a full coordinator exists.

#### Stage B: introduce a `ResourceCoordinator`

After the low-risk cleanup above, introduce a single coordinator that owns:

- preload policy,
- idle-timeout policy,
- memory-budget decisions,
- unload ordering,
- safe coordination with active rewrite/transcription work.

The coordinator should receive coarse events such as:

- recording started,
- recording ended,
- transcription started/finished,
- rewrite started/finished,
- application terminating.

It should not bypass service-level synchronization. It should orchestrate policy, not replace correctness inside each service.

### Measurement requirements

Before choosing aggressive idle timeouts, capture real data for:

- cold load latency per resource,
- warm reuse latency,
- peak resident memory per model tier,
- whether audio-engine retention actually affects microphone availability for other apps in practice.

Do not hard-code a lifecycle policy based only on intuition.

---

## 2. `RewriteExecutionGate` must become cancellation-safe, not disappear

**Where:** `Speech2Text/Conversion/LLMRewriteService.swift`, `Speech2TextTests/LLMRewriteServiceTests.swift`

**Current problem:** `RewriteExecutionGate` stores waiting continuations in a FIFO array and never removes a waiter if its task is canceled before acquisition. That can leave canceled waiters stranded in the queue and can starve or deadlock later rewrite requests.

**Important correction:** The earlier draft raised the possibility that the gate could be removed in favor of actor isolation. That is not a safe default assumption here. `rewriteCore(...)` enters an async stream and suspends while generation is in progress. During those suspension points, other calls can enter the actor unless there is an explicit serialization primitive. The existing tests already encode the requirement that rewrite generations must not overlap.

**Implication:** The gate is solving a real problem. The bug is that it is hand-rolled and cancellation-unaware.

### Suggested fix direction

Replace the current gate with a cancellation-aware serialization primitive. Two acceptable shapes are:

1. a corrected in-house gate/semaphore, or
2. a tiny wrapper around a well-understood async semaphore implementation.

The important properties are:

- waiting tasks can be canceled cleanly,
- canceled waiters are removed from the queue,
- active holders release exactly once,
- future requests still serialize to one active generation at a time.

### Recommended implementation shape

A good shape is an acquire/release token or lease pattern:

- `acquire()` is `async throws`
- cancellation while waiting throws `CancellationError`
- the caller stores the returned lease/token
- release happens in `defer`

That keeps lock-release logic centralized and reduces the chance of missed release paths.

### Tests that must exist before calling this done

1. Existing non-overlap test still passes (`maxActive == 1`).
2. A queued waiter canceled before acquisition does not block the next legitimate waiter.
3. Canceling the active rewrite still releases the gate for the next request.
4. A load/unload or lifecycle operation that also needs serialization can acquire the same primitive without deadlocking behind canceled waiters.

This item should be fixed before any larger lifecycle coordinator starts sharing the same execution path.

---

## 3. OOM detection needs targeted classification plus proactive budget checks

**Where:** `Speech2Text/Conversion/LLMRewriteService.swift`, future lifecycle coordinator code

**Current problem:** `LLMRewriteService.isMemoryPressureError(_:)` currently string-matches `localizedDescription` for phrases like `out of memory` and `alloc`. That is brittle and version-sensitive.

**What should not happen:**

- Do not broaden fallback so that *any* load failure is treated as OOM.
- Do not use total physical RAM alone as the decision metric; it does not reflect current memory pressure.

Network failures, corrupted downloads, model-format issues, and framework regressions should not silently downgrade the tier as if they were memory failures.

### Revised design direction

#### Proactive path

Before loading a large tier, the lifecycle layer should estimate whether the requested tier is likely to fit **now**, not just on paper. That may involve:

- known approximate resident sizes per model tier,
- a real available-memory signal if one is available on the deployment target,
- current residency of other large resources such as Whisper.

If memory is obviously insufficient, the system should make a policy decision before attempting the expensive load.

#### Reactive path

Keep a reactive fallback for genuine runtime memory failures, but make the classification logic explicit and testable.

Preferred order:

1. Use typed MLX errors or error codes if the framework exposes them.
2. If typed errors are unavailable, isolate string-based classification in one place and back it with regression tests pinned to the currently supported MLX version.
3. Surface non-memory load failures separately instead of silently downgrading.

### Coordinator interaction

If the rewrite tier does not fit, the coordinator should decide whether to:

1. unload an idle lower-priority resource first,
2. retry the requested tier,
3. downgrade the rewrite tier,
4. surface a user-facing explanation.

That decision belongs in lifecycle policy, not deep inside the rewrite service alone.

---

## 4. `IntentDetector` duplication is still worth refactoring, but only behind tests

**Where:** `Speech2Text/Conversion/IntentDetector.swift`, `Speech2TextTests/IntentDetectorTests.swift`, `Speech2TextTests/IntentCatalogDynamicTests.swift`

**Current problem:** The four scoring families are still largely duplicated:

- `scoreZone(_:modes:)`
- `scoreAllZone(_:modes:)`
- `scoreZoneDefs(_:defs:)`
- `scoreAllZoneDefs(_:defs:)`

This is not a runtime lifecycle bug, but it is a real maintenance and drift risk.

### Revised guidance

This should remain a mechanical refactor, not a behavior redesign.

1. First add or confirm tests that pin current behavior for both:
   - mode-based detection paths, and
   - definition-based detection paths.
2. Extract shared scoring logic into one private implementation that takes:
   - the normalized zone,
   - the resolved definitions,
   - whether to return only the top result or all threshold-passing results.
3. Preserve all existing semantics:
   - exact-match priority,
   - keyword bonus,
   - margin checks,
   - threshold filtering,
   - "exact matches beat fuzzy matches" behavior.

### Success criteria

The refactor is successful only if behavior stays stable and future scoring changes no longer require editing four parallel implementations.

---

## 5. Menu bar icon updates still rely on undocumented view-hierarchy walking

**Where:** `Speech2Text/App/AppDelegate.swift`, `Speech2Text/App/Speech2TextApp.swift`

**Current problem:** The app updates the menu bar icon by walking `NSApp.windows`, looking for status-bar-level windows, then mutating the first `NSButton` it finds. That is an undocumented implementation detail of the current `MenuBarExtra` hierarchy.

A related code smell: `AppDelegate` already has an unused `statusItem` property, which suggests the app may eventually want direct status-item ownership instead of heuristic view walking.

### Revised guidance

The first step here is not implementation. It is deciding whether the app can own a supported status-item API directly on the current deployment target.

#### Preferred direction if deployment target allows it

Use an explicit `NSStatusItem` (or another supported API with direct icon control) instead of reaching into `MenuBarExtra` internals.

#### If `MenuBarExtra` must remain for now

Then at minimum:

1. wrap the heuristic in a dedicated helper,
2. return success/failure from that helper,
3. log when the expected view hierarchy is not found,
4. treat icon update as best-effort but not silently invisible.

### Success criteria

Either:

- the app owns a supported icon-update mechanism, or
- the heuristic fails loudly enough that breakage is diagnosable after a macOS update.

---

## Recommended execution order

For a larger implementation effort, this is the safest order:

1. Stage A lifecycle cleanup from Item 1 (`unload()` / termination release / state-model cleanup)
2. Item 2 (`RewriteExecutionGate` cancellation safety)
3. Item 3 (targeted OOM classification and budget policy groundwork)
4. Stage B lifecycle coordinator from Item 1
5. Item 4 (`IntentDetector` deduplication)
6. Item 5 (menu bar icon fragility cleanup)

This keeps correctness work ahead of policy work and keeps maintainability refactors out of the critical path.
