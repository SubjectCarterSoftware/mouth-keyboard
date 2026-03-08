# Phase 5: Long-Dictation Reliability - Context

**Gathered:** 2026-03-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Support longer dictation sessions by segmenting capture after the app leaves its current short-session path, queueing transcription work for those segments, and producing one final clipboard result in spoken order. This phase improves long-session reliability inside the existing clipboard-first workflow. It does not add direct insertion, new major UI surfaces, or broader engine-mode choices.

</domain>

<decisions>
## Implementation Decisions

### Segmentation Rhythm
- Long-dictation mode should prefer balanced chunk sizes rather than aggressively small chunks or very large ones.
- Once long-dictation mode is active, a clear natural pause should normally close a chunk.
- If the user keeps speaking without a usable pause, the app should allow some overrun and then apply a soft cap rather than waiting forever or cutting exactly at the threshold.
- The long-dictation threshold should stay fixed in v1 rather than being exposed as a user-facing setting.

### Long-Session Feedback
- While the user is still actively dictating, the pill should stay close to the current quiet waveform behavior and should not show running chunk counts.
- During long-session processing and assembly, the pill should remain minimal rather than becoming a detailed progress surface.
- The menu should carry the persistent long-session status while queued chunks are still being processed.
- Successful long dictation should reuse the current brief success confirmation rather than introducing a sticky or expanded completion state.

### Partial-Failure Behavior
- If one chunk fails, the clipboard result should still include every successful chunk in spoken order.
- Successful chunks should be assembled into seamless prose rather than visibly separated chunk output.
- Warnings about partial failure should stay in the pill/menu UI rather than being inserted into the clipboard text itself.
- Partial-failure messaging should be count-based so the user knows the result is incomplete without seeing internal segment mechanics.

### Claude's Discretion
- The exact fixed threshold and soft-cap values, as long as they preserve the balanced / clear-pause / soft-cap behavior chosen above.
- The exact wording and visual treatment for long-session menu status and partial-failure warnings.
- The exact internal queueing, assembly, and retry mechanics, provided the final user-visible behavior matches the decisions above.
- The exact heuristics for when the app transitions from the current short-session path into long-dictation mode.

</decisions>

<specifics>
## Specific Ideas

- Long dictation should still feel like the same quiet utility rather than turning into a dashboard.
- Persistent status belongs in the menu; the pill should stay lightweight even when long dictation takes longer to finish.
- Clean clipboard output matters more than surfacing internal chunk boundaries directly in pasted text.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ActivationStore` (`Speech2Test/Activation/ActivationStore.swift`): already owns the recording, processing, success, failure, and clipboard-write flow. Phase 5 can extend this state machine instead of creating a parallel long-session controller.
- `AudioBufferAccumulator` (`Speech2Test/Audio/AudioBufferAccumulator.swift`): current in-memory accumulation and conversion path is the natural seam for moving from one-buffer capture to chunk-based accumulation.
- `WhisperService` (`Speech2Test/Transcription/WhisperService.swift`): existing shared transcription actor can remain the serialization point for queued chunk transcription work.
- `AudioLevelMonitor` (`Speech2Test/Audio/AudioLevelMonitor.swift`): already tracks silence and has warning/timeout callbacks, making it the obvious place to detect clear pauses after long-dictation mode activates.
- `RecordingPillView` / `RecordingPillPanel` (`Speech2Test/Shell/`): current lightweight transient feedback surface should be reused for long-session recording, processing, and warning states.
- `StatusMenuView` (`Speech2Test/Shell/StatusMenuView.swift`): existing persistent status surface is the right place for long-session progress and partial-failure warnings.

### Established Patterns
- Clipboard-only output remains the compatibility boundary; the app should still produce one final clipboard write rather than incremental direct insertion.
- The product favors quiet, menu-bar-first behavior, so long-dictation status should not introduce heavyweight foreground UI.
- Failure and recovery messaging already flow through `ActivationStore`, the pill, and the menu; Phase 5 should extend that path instead of inventing a new reporting channel.
- The current transcription path is batch-after-finish, with one `WhisperService` actor and a success-only clipboard barrier. Long-dictation planning should preserve those safety guarantees while adding chunking and assembly.

### Integration Points
- `AppDelegate` (`Speech2Test/App/AppDelegate.swift`) currently starts capture, wires silence callbacks, and reacts to `.recording` / `.processing` / terminal states. Phase 5 will need to extend these hooks for long-session processing without breaking the existing short-session path.
- `ActivationStore.finish()` and `transcribeAndDispatch(sessionID:)` are the current boundaries between recording and processing; chunk queueing and final assembly will need to connect here.
- `AudioCaptureService.start(levelMonitor:bufferAccumulator:)` currently feeds one accumulator while recording. Phase 5 will need to rotate or snapshot chunk data at segment boundaries.
- `RecordingState` and menu/pill rendering are already the app-wide contract for user-visible session state, so long-dictation progress and partial-failure warnings should plug into that contract.

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---
*Phase: 05-long-dictation-reliability*
*Context gathered: 2026-03-08*
