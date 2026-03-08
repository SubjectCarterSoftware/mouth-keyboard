# Phase 5: Long-Dictation Reliability - Research

**Researched:** 2026-03-08
**Domain:** Long-session audio segmentation, queued transcription, ordered assembly, partial-failure recovery
**Confidence:** HIGH

## Summary

Phase 5 should extend the current `ActivationStore`-driven recording loop instead of introducing a second long-dictation controller. The app already has the right core seams: `ActivationStore` owns lifecycle and clipboard policy, `AudioCaptureService` owns the live microphone stream, `AudioBufferAccumulator` owns captured audio, `WhisperService` already serializes transcription work behind an actor, and the pill/menu surfaces already separate transient and persistent feedback.

The real work is in the transition from one-buffer batch transcription to a segmented pipeline that can keep recording while earlier chunks are already queued for transcription. The safest architecture is:

1. Keep one live recording session in `ActivationStore`.
2. Add a long-session companion model that tracks whether segmentation is active, which segment index is currently open, and what queued/completed/failed segments exist.
3. Seal segments into immutable snapshots after the session crosses the fixed long-dictation threshold and a natural pause or soft cap is reached.
4. Queue those sealed segments for transcription through the existing `WhisperService` actor.
5. Assemble successful segment transcripts by index into one final clipboard write when the user finishes.
6. Surface partial-failure warnings in the pill/menu only, never in the clipboard text.

**Primary recommendation:** keep `RecordingState` as the coarse lifecycle contract (`idle`, `recording`, `processing`, terminal success/failure), and add companion long-dictation progress/result models rather than overloading the lifecycle enum with detailed segment mechanics. This preserves the current shell architecture, keeps the pill minimal during active dictation, and gives the menu a place to carry persistent long-session status.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Long dictation should favor balanced chunk sizes instead of aggressively tiny segments or giant monolithic captures.
- Once long-dictation mode activates, a clear natural pause should usually close the current chunk.
- If the user keeps speaking without a usable pause, the app should allow some overrun and then apply a soft cap instead of waiting forever or cutting exactly at the threshold.
- The long-dictation threshold remains fixed in v1; it is not a user-facing setting.
- While actively dictating, the pill should stay close to the current quiet waveform behavior and should not show chunk counters.
- During long-session processing and assembly, the pill should remain minimal rather than becoming a detailed progress dashboard.
- The menu should carry the persistent long-session status while queued chunks are still being processed.
- Successful long dictation should reuse the current brief success confirmation rather than a new sticky completion state.
- If one segment fails, the clipboard result must still include every successful segment in spoken order.
- Successful chunks should combine into seamless prose instead of visibly separated chunk text.
- Partial-failure warnings belong in the pill/menu UI, not in clipboard text.
- Partial-failure messaging should be count-based, not internal-segment-detail-heavy.

### Claude's Discretion
- The exact fixed activation threshold, pause duration, and soft-cap values.
- The exact wording and rendering of long-session menu status and partial-failure warnings.
- The exact queue implementation and retry policy, provided the user-visible behavior remains best-effort and ordered.
- The exact heuristic for when the app leaves the current short-session path and enters segmented long-dictation mode.

### Deferred Ideas (OUT OF SCOPE)
- Direct insertion or incremental paste while dictating.
- Rich progress HUDs, visible chunk counters in the pill, or a foreground dashboard.
- User-configurable segmentation controls in v1.
- Alternate transcription engines or model modes.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TRNS-03 | User can dictate longer than 30 seconds without losing earlier audio because the app segments and queues the recording automatically. | Requires a reliable segment-sealing mechanism plus immutable queued segment data that can survive ongoing capture. |
| TRNS-04 | User receives a combined transcript in the original spoken order when a session spans multiple segments. | Requires ordered segment indices, deterministic assembly, and a final clipboard barrier that waits for the session's segment work to settle. |
| TRNS-05 | User still receives the best available combined transcript if one segment fails to transcribe. | Requires per-segment success/failure tracking, best-effort assembly, and count-based warning UI outside the clipboard text. |
</phase_requirements>

## Standard Stack

### Core
| Layer | Existing Asset | Purpose | Why It Fits Phase 5 |
|-------|----------------|---------|---------------------|
| Lifecycle | `ActivationStore` | Owns recording, processing, success/failure, and clipboard policy | The existing state machine should remain authoritative for session lifecycle. |
| Capture | `AudioCaptureService` | Feeds a continuous microphone stream into the monitor and accumulator | Segmentation should happen above this layer so the audio engine stays simple. |
| Buffering | `AudioBufferAccumulator` | Owns in-memory captured buffers and conversion to Whisper format | This is the natural seam for sealing one immutable segment while recording continues. |
| Silence / pause signals | `AudioLevelMonitor` | Already measures normalized levels and tracks silence timers | The current monitor can evolve into pause-aware segment detection, but should not keep Phase 3's fixed 45s/60s rules as the only mechanism. |
| Transcription | `WhisperService` actor | Serializes whisper.cpp access | A segment queue can feed it safely without concurrent whisper context access. |
| Transient feedback | `RecordingPillView` / `RecordingPillPanel` | Lightweight current-session UI | Keeps active recording and completion feedback quiet. |
| Persistent feedback | `StatusMenuView` | Menu-bar status surface | Best home for queued/partial-failure status after recording stops. |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `ActivationStoreTests.swift` | Session-level orchestration coverage | Long-session state transitions, best-effort finish, clipboard barrier |
| `AudioBufferAccumulatorTests.swift` | Segment-snapshot correctness coverage | Seal/reset behavior and immutable segment conversion |
| `WhisperServiceTests.swift` | Transcriber contract coverage | Segment result success/failure handling with mocks |
| `MenuBarShellSmokeTests.swift` | Menu and indicator-hidden shell coverage | Minimal status/warning behavior without animation-heavy assertions |
| XCTest | Core verification framework | Already established by earlier phases |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Store-owned long-session orchestration | Separate `LongDictationController` that owns capture/transcription | Creates a second lifecycle driver that would drift from `ActivationStore` and duplicate state handling. |
| Immutable sealed segments | Keep one mutable accumulator and slice it later | Higher risk of ordering bugs, accidental duplication, and hard-to-test partial-failure behavior. |
| `WhisperService`-serialized queue | Parallel transcription tasks against one whisper context | Unsafe with the current actor-backed whisper design and unlikely to improve reliability. |
| Companion progress model | Encode segment counts/details directly into `RecordingState` | Makes the lifecycle enum noisy and risks shell regressions in earlier phases. |
| Best-effort partial success | Fail the whole session if any segment fails | Violates TRNS-05 and wastes successful work. |

## Architecture Patterns

### Recommended Project Structure
```text
Speech2Test/
  Activation/
    ActivationStore.swift                 # extend with long-session orchestration
    RecordingState.swift                  # keep lifecycle coarse; add companion status/result models if needed
    LongDictationSession.swift            # NEW: segment metadata, queue state, assembly inputs
    LongDictationAssembler.swift          # NEW: ordered best-effort transcript assembly
  Audio/
    AudioBufferAccumulator.swift          # add immutable segment sealing / snapshot support
    AudioLevelMonitor.swift               # add pause-aware segment callbacks or extract detector
  Transcription/
    WhisperService.swift                  # reuse existing actor; no parallel whisper context access
  Shell/
    StatusMenuView.swift                  # persistent long-session status and partial-failure warnings
    RecordingPillView.swift               # keep minimal active/processing/success behavior, add lightweight warning support if needed
```

### Pattern 1: Keep one lifecycle driver; add companion long-session state
**What:** Preserve `RecordingState` as the top-level lifecycle contract while adding a small long-session companion state for segmenting/queueing/assembly.

**Why:** `AppDelegate` already reacts to `RecordingState` to start/stop capture and update the shell. Phase 5 should not break that contract by making every segment closure look like a lifecycle transition.

**Recommended shape:**
```swift
@MainActor
final class ActivationStore: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var longSessionStatus: LongSessionStatus?
    @Published private(set) var resultNotice: LongSessionResultNotice?
}

struct LongSessionStatus: Equatable {
    enum Phase: Equatable {
        case inactive
        case recordingSegmented
        case finalizing
    }

    var phase: Phase
    var queuedSegments: Int
    var completedSegments: Int
    var failedSegments: Int
}

struct LongSessionResultNotice: Equatable {
    let failedSegmentCount: Int
}
```

**Important product fit:** the menu can consume `LongSessionStatus` and `LongSessionResultNotice`, while the pill can stay coarse: normal waveform during recording, minimal processing indicator during finalization, and existing success/failure states with optional warning copy.

### Pattern 2: Seal immutable segments instead of mutating one growing session blob
**What:** Once the session crosses the long-dictation threshold, close the current segment on a natural pause or soft cap and queue that closed segment as immutable data.

**Why:** TRNS-03 is fundamentally about not losing earlier audio while the user keeps speaking. That requires turning "what has been safely captured so far" into a sealed segment that no longer depends on the live capture path.

**Recommended implementation seam:**
- Extend `AudioBufferAccumulator` with a lock-protected segment-sealing API such as `sealSegment()` or `drainSegment()`.
- On seal:
  - snapshot the current buffered audio into an immutable segment payload
  - reset the live buffer storage immediately so recording can continue without engine restarts
  - assign the segment a monotonically increasing index

**Important reliability note:** long-session work magnifies the cost of keeping raw `AVAudioPCMBuffer` references around. The current accumulator stores incoming buffers directly. For Phase 5, prefer one of these:
- deep-copy buffers when appending, then seal copied buffers into a segment, or
- copy/convert the sealed segment into owned sample data at seal time

The point is the same: queued segment data must not depend on mutable live audio callback objects.

### Pattern 3: Use threshold -> pause -> soft-cap sequencing, not one fixed timeout
**What:** After the session becomes "long," detect segment boundaries based on speech behavior:

1. Stay on the current short-session path before the long threshold.
2. After threshold, a natural pause can seal the current segment.
3. If no pause arrives, allow some overrun, then force a soft-cap seal.

**Why:** This matches the context: balanced chunk sizes, pause-preferred boundaries, and no exact-threshold chopping.

**Recommended detector split:**
- Keep `AudioLevelMonitor` responsible for normalized live levels.
- Extract or extend a small pure decision component for long-session boundary logic, for example:
```swift
struct SegmentBoundaryDecision {
    let shouldSeal: Bool
    let reason: Reason?
}
```

This lets tests verify boundary behavior deterministically without needing real-time waits or AVFoundation-heavy fixtures.

**Planner guidance:**
- Do not reuse the current 45s warning / 60s timeout logic as the segmentation policy.
- Keep the exact threshold and soft-cap constants internal and fixed in code for v1.
- Final end-of-session behavior still goes through `finish()`, but `finish()` now needs to await remaining queued segments and final assembly instead of assuming one final transcription job.

### Pattern 4: Queue segment transcription work through the existing whisper actor
**What:** As each segment seals, enqueue its transcription work while recording continues.

**Why:** `WhisperService` is already an actor, so it is the safe serialization point for whisper.cpp access. Phase 5 needs queueing, not unsafe parallelism.

**Recommended queue behavior:**
- Each segment gets:
  - stable index
  - sealed audio payload
  - transcription status (`pending`, `transcribing`, `success`, `failed`)
  - optional transcript text or error
- The store launches async jobs for sealed segments, but those jobs all await the same `WhisperService` actor.
- Order is preserved by index, not by completion timing.

**Important implication:** the queue exists to preserve reliability and overlap capture with transcription, not to run multiple whisper jobs at once. Completion order may differ from spoken order; assembly must always use segment indices.

### Pattern 5: Assemble text by index with best-effort partial success
**What:** At finalization, combine successful segment transcripts in original spoken order and surface failure counts separately.

**Why:** TRNS-04 and TRNS-05 together require:
- ordered combined output
- no duplication or loss among successful segments
- best-effort delivery even when one or more segments fail

**Recommended assembler contract:**
```swift
struct SegmentTranscriptResult: Equatable {
    let index: Int
    let text: String?
    let error: Error?
}

struct AssembledTranscript: Equatable {
    let text: String
    let failedSegmentCount: Int
    let successfulSegmentCount: Int
}
```

**Assembly rules:**
- sort by `index`
- trim each successful segment
- drop empty/whitespace-only segment transcripts as failures, not silent successes
- join successful segment texts with normalized whitespace so clipboard output reads as seamless prose
- if at least one segment succeeded, write one final clipboard result
- if all segments failed, stay on the failure path and leave the clipboard untouched

**Do not do this:** do not inject markers such as `[segment failed]` into the clipboard output. The warning belongs in the pill/menu only.

### Pattern 6: Keep the pill quiet; put persistent long-session status in the menu
**What:** Respect the UI constraints by keeping the pill coarse and moving persistent queue/partial-failure status to the menu.

**Why:** The context is explicit: no chunk counters during recording and no progress-dashboard pill during assembly.

**Recommended UI split:**
- During active dictation:
  - pill remains the current waveform
  - menu may show lightweight "Long dictation active" copy if helpful
- During post-finish finalization:
  - pill stays in the minimal processing state
  - menu shows persistent status such as "Assembling long dictation..." and, when relevant, "1 segment failed; combined result copied"
- On final success:
  - reuse the existing brief success confirmation
  - if there were failures, pair the success with a count-based menu warning

### Pattern 7: Preserve the final clipboard barrier
**What:** Only the final assembled session result may write to `ClipboardService`.

**Why:** The current store writes to the clipboard immediately on one successful transcription. In Phase 5, segment-level success must not trigger intermediate clipboard writes, because the product boundary is still one final clipboard result per session.

**Planner rule:**
- segment transcription success updates queue state only
- final assembly decides whether a clipboard write occurs
- if every segment fails or yields unusable text, keep the clipboard untouched and use the failure path

## Don't Hand-Roll

| Problem | Use | Avoid |
|---------|-----|-------|
| Long-session orchestration | `ActivationStore` plus small helper types | New top-level controller that owns lifecycle separately |
| Segment queue safety | Immutable sealed segment payloads | Re-slicing one mutable session buffer after the fact |
| Whisper concurrency | Existing `WhisperService` actor | Multiple simultaneous whisper context calls |
| Ordered assembly | Explicit segment indices | Assuming completion order matches spoken order |
| Partial-failure UX | Menu/pill warning with failure count | Failure markers in clipboard text |
| Boundary heuristics | Extracted/pure segment-decision logic | Hard-coding pause timing inside views or scattered callbacks |

## Common Pitfalls

### Pitfall 1: `ActivationStore.finish()` currently assumes one transcription task
**What goes wrong:** the store transitions to `.processing`, awaits one `transcribeAndDispatch`, then writes the clipboard immediately.

**Impact:** That is incompatible with segment queueing and final assembly.

**Planner response:** refactor `finish()` into a finalization step that:
- closes any open live segment
- waits for queued segment transcription work to settle
- assembles best-available results
- performs one final clipboard decision

### Pitfall 2: `AppDelegate.onProcessingStarted()` stops capture
**What goes wrong:** today `.processing` means "recording has ended."

**Impact:** If segment sealing tried to drive `.processing` per segment, capture would stop immediately.

**Planner response:** keep the app in `.recording` while segmenting during active speech. Only enter `.processing` when the user finishes and the app is finalizing remaining segment work.

### Pitfall 3: `AudioLevelMonitor` is currently a timeout monitor, not a segment detector
**What goes wrong:** the existing 45s/60s callbacks model extended silence warning and auto-stop, not short natural pauses after the long-session threshold.

**Impact:** Reusing those values directly would create wrong segmentation behavior.

**Planner response:** add or extract a segment-boundary decision layer with pause/soft-cap inputs that can be unit tested directly.

### Pitfall 4: Current accumulator behavior is fine for short sessions but risky for long ones
**What goes wrong:** long dictation multiplies memory and correctness pressure. Holding a single ever-growing in-memory buffer until finish increases duplication/loss risk and makes partial-failure recovery impossible.

**Impact:** TRNS-03 is at risk unless earlier audio becomes sealed work that survives later capture and failures.

**Planner response:** seal/reset per segment, and make queued segment payloads explicitly owned and immutable.

### Pitfall 5: `RecordingState.success(text:)` does not express partial success
**What goes wrong:** the current success path cannot distinguish "full success" from "best-effort success with one failed segment."

**Impact:** the app could either hide partial failures or overcomplicate the clipboard payload.

**Planner response:** keep `success` as the coarse lifecycle and add a companion result notice or menu warning model for partial-failure counts.

## Planning Guidance

The roadmap already defines the right three-plan split:

1. `05-01` should establish threshold activation, segment sealing, immutable queueing, and deterministic boundary logic.
2. `05-02` should implement ordered assembly, best-effort partial-failure behavior, and the shell/status contract for long-session finalization.
3. `05-03` should verify reliability, latency impact, and regressions with focused automated coverage plus a human long-session checkpoint.

File ownership should stay narrow:
- `05-01`: `ActivationStore`, `AudioBufferAccumulator`, `AudioLevelMonitor`, new helper types/tests
- `05-02`: `ActivationStore`, `WhisperService` integration seam, assembly helper, `StatusMenuView`, `RecordingPillView`, tests
- `05-03`: test files, validation docs, and only minimal production changes needed to close uncovered regressions

## Validation Architecture

Phase 5 needs explicit validation because it introduces asynchronous overlap between capture, queued transcription, and final assembly. The safest approach is to add deterministic unit coverage around the new boundary and assembly logic, then keep one manual checkpoint for a real long dictation run.

### Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Config file** | `Speech2Test.xcodeproj` |
| **Quick run command** | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -destination 'platform=macOS'` |
| **Estimated runtime** | ~20 seconds |

### Sampling Strategy

- After each segmentation/assembly task commit: run the relevant focused unit target first.
- After each plan wave: run the full `Speech2TestTests` target.
- Before `$gsd-verify-work`: full suite must be green, then complete one real long-dictation manual run.

### Coverage Recommendations

| Candidate Task ID | Plan | Requirement | Test Type | Command | File Exists |
|-------------------|------|-------------|-----------|---------|-------------|
| 05-01-01 | 01 | TRNS-03 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/AudioBufferAccumulatorTests -destination 'platform=macOS'` | existing (expand) |
| 05-01-02 | 01 | TRNS-03 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | existing (expand) |
| 05-01-03 | 01 | TRNS-03 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/LongDictationBoundaryTests -destination 'platform=macOS'` | new |
| 05-02-01 | 02 | TRNS-04 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/TranscriptAssemblerTests -destination 'platform=macOS'` | new |
| 05-02-02 | 02 | TRNS-05 | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | existing (expand) |
| 05-02-03 | 02 | TRNS-04, TRNS-05 | ui-smoke | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestUITests/MenuBarShellSmokeTests -destination 'platform=macOS'` | existing (expand) |
| 05-03-01 | 03 | TRNS-03, TRNS-04 | integration-ish unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/LongDictationFlowTests -destination 'platform=macOS'` | new |

### Manual-Only Verification

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Long dictation with multiple natural pauses produces one ordered clipboard result | TRNS-03, TRNS-04 | Requires real audio cadence and end-to-end menu/pill observation | 1. Start recording 2. Dictate for >30 seconds with two clear pauses 3. Finish 4. Verify one final clipboard result contains all spoken content in order |
| Continuous speech beyond the threshold still seals via soft cap | TRNS-03 | Hard to simulate faithfully with unit timing alone | 1. Start recording 2. Speak continuously past the long threshold without a usable pause 3. Finish 4. Verify earlier content is still present and the session completes |
| One segment failure still yields best-effort combined output with a warning | TRNS-05 | Needs end-to-end confirmation that clipboard text stays clean while UI carries the warning | 1. Inject or simulate one segment transcription failure 2. Finish the session 3. Verify clipboard text includes successful segments only and the menu/pill shows a count-based incompleteness warning |
| Indicator-hidden mode still exposes long-session status in the menu | TRNS-05 | UI smoke can prove identifiers, but real menu-bar posture still needs manual confirmation | 1. Hide the indicator 2. Run a long dictation session 3. Verify the menu carries the persistent finalization/warning status without a pill |

**Validation takeaway:** extract boundary and assembly logic into small deterministic helpers early. If those stay embedded directly in `ActivationStore` and `AudioLevelMonitor`, Phase 5 will be much harder to verify and much easier to regress.
