# Phase 4: Recovery Controls - Research

**Researched:** 2026-03-07
**Domain:** Session recovery, microphone failure handling, transient feedback, clipboard integrity
**Confidence:** HIGH

## Summary

Phase 4 should harden the existing recording loop rather than introduce a second orchestration layer. The current architecture already has the right seams: `ActivationStore` owns lifecycle state, `AppDelegate` reacts to that state for capture start/stop and menu-bar updates, `AudioCaptureService` owns microphone startup/device failure behavior, and the pill/menu surfaces are already reactive.

The important gaps are architectural, not visual. First, `ActivationStore.stop()` exists, but `.idle` currently does not stop `AudioCaptureService`, so cancel is not yet a safe hard stop. Second, cancel during `.processing` cannot work correctly until the transcription task is tracked and invalidated; the current fire-and-forget `Task` can still publish success and touch the clipboard after a user cancel. Third, microphone failures are thrown or logged, then collapsed back to `.idle`, and selected-device disconnect currently falls back silently to the default microphone, which conflicts with the Phase 4 context.

**Primary recommendation:** keep `RecordingState` as the lifecycle driver for side effects, but add explicit recovery orchestration in `ActivationStore`: `cancelCurrentSession()`, `restartCurrentSession()`, and `handleCaptureFailure(...)`. Use a session token plus stored transcription task to prevent stale async results from mutating state or clipboard after cancel/restart. Surface microphone failures as typed failure reasons, and treat the clipboard as a write barrier: only the final confirmed success path may call `ClipboardService`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- `Escape` cancels an in-flight session during both recording and processing.
- Cancel is a hard stop: discard captured audio or work in progress, return to safety, and leave the clipboard unchanged.
- Restart stays in-session; it does not become a "finish and start again" shortcut.
- There is no dedicated restart keyboard shortcut.
- Restart, if exposed, should clear the current captured audio and continue recording from a clean point.
- Microphone failures should be visible in the existing pill and recoverable from the menu without stealing focus.
- If the selected microphone disappears during an active session, stop with a clear error instead of silently switching devices.
- Partial audio from a microphone failure is discarded and must not reach the clipboard.

### Claude's Discretion
- Exact restart affordance, as long as it is low-friction and not a dedicated shortcut.
- Exact canceled/restarted/microphone-failure copy and timing.
- Whether recovery is exposed in the menu, the pill, or both.
- Whether restart confirmation is carried by lifecycle state or a small companion feedback state.

### Deferred Ideas (OUT OF SCOPE)
- New foreground windows or setup-stealing behavior for recovery.
- Long-dictation salvage, partial transcript preservation, or alternate output modes.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SESS-02 | User can cancel the active recording with Escape and leave the clipboard unchanged. | Requires a session-key interception path plus a real hard-stop path that tears down capture and invalidates in-flight transcription work. |
| SESS-03 | User can restart the current recording from a clean point without leaving recording state. | Best implemented as buffer/session reset while capture continues, not as stop-then-arm. |
| SESS-04 | User receives a clear visual confirmation when a session is canceled or restarted. | Reuse the existing pill/menu surfaces; do not invent a new window or foreground flow. |
| AUDI-04 | User receives a clear error when the selected microphone is unavailable or access is denied. | Requires typed microphone failures from `AudioCaptureService` through `ActivationStore` into the existing failure UI. |
| CLIP-02 | User can rely on the app to avoid overwriting the clipboard when a session is canceled or produces no usable transcription. | Enforce a strict clipboard write barrier: recovery and failure paths must never call `ClipboardService`. |
</phase_requirements>

## Standard Stack

### Core
| Layer | Existing Asset | Purpose | Why It Fits Phase 4 |
|-------|----------------|---------|---------------------|
| Lifecycle | `ActivationStore` | Owns recording/transcription state | Already centralizes start/finish policy and clipboard writes. |
| Side effects | `AppDelegate` state observer | Starts/stops capture, updates menu-bar icon | Recovery should plug into the existing observer model, not bypass it. |
| Audio | `AudioCaptureService` + `AudioDeviceService` | Starts capture, routes selected device, observes disconnects | This is where microphone failures already originate. |
| UI feedback | `RecordingPillView` + `RecordingPillPanel` | Immediate transient state surface | Existing failure UI can carry cancel/restart/mic-failure copy. |
| Persistent recovery | `StatusMenuView` | Menu-bar surface for recovery actions | Matches the "visible but quiet" product posture. |
| Clipboard | `ClipboardService` | Final clipboard mutation | Must stay behind a strict success-only gate. |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `AudioBufferAccumulator` | Owns captured audio that restart/cancel must discard | Reset on arm, cancel, restart, and microphone failure. |
| `AudioLevelMonitor` | Silence callbacks and waveform state | Reset on restart/cancel to avoid stale warning state. |
| `CGEventTap` via a generalized session-key interceptor | Background `Escape` handling | Only if the project keeps literal `Escape` cancel while the app stays in the background. |
| XCTest | Recovery-unit coverage | Existing test suite already uses injectables for the right seams. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Store-owned recovery APIs | AppDelegate-specific cancel/restart branches | Spreads policy into the shell layer and makes recovery harder to test. |
| Buffer reset restart | Stop capture and re-arm | More state churn, more menu-bar/pill flicker, and a worse fit for SESS-03. |
| Typed microphone failures | Logging and returning to `.idle` | Hides AUDI-04 failures and makes the pill/menu useless for recovery. |
| Event-tap session cancel | Menu-only cancel | Lower implementation risk, but does not satisfy literal `Escape` cancel while staying in the current app. |
| Success-only clipboard writes | Attempting clipboard rollback after a failed write | `NSPasteboard` writes are destructive and not meaningfully transactional for arbitrary content types. |

## Architecture Patterns

### Recommended Project Structure
```text
Speech2Test/
  Activation/
    ActivationStore.swift          # add cancel/restart/failure orchestration, session invalidation
    RecordingState.swift           # add typed microphone failures; keep lifecycle states explicit
    SessionKeyInterceptor.swift    # optional: generalize SpacebarInterceptor to Escape/session keys
  Audio/
    AudioCaptureService.swift      # stop silent fallback; surface typed start/disconnect failures
    AudioBufferAccumulator.swift   # existing reset seam for restart/cancel/failure
    AudioLevelMonitor.swift        # existing reset seam for restart/cancel/failure
  Shell/
    RecordingPillView.swift        # add canceled/restarted/microphone-failure copy
    RecordingPillPanel.swift       # optional: allow interaction only if the pill becomes an action surface
    StatusMenuView.swift           # add persistent recovery actions / messaging
```

### Pattern 1: Keep lifecycle state authoritative; add explicit recovery orchestration
**What:** Keep `RecordingState` responsible for lifecycle (`idle`, `recording`, `processing`, terminal success/failure), and add explicit recovery APIs in `ActivationStore` that own cancel, restart, and microphone failure handling.

**Why:** `AppDelegate` already reacts to lifecycle transitions. Recovery logic should stay in the store so it is testable and consistent across hotkey, Escape, menu, and future pill actions.

**Recommended shape:**
```swift
@MainActor
final class ActivationStore: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var recoveryFeedback: RecoveryFeedback?

    private var activeSessionID = UUID()
    private var transcriptionTask: Task<Void, Never>?

    func cancelCurrentSession() { ... }
    func restartCurrentSession() { ... }
    func handleCaptureFailure(_ error: AudioCaptureError) { ... }
}

enum RecoveryFeedback: Equatable {
    case canceled
    case restarted
}
```

**Why `recoveryFeedback` is recommended:** SESS-03 says restart should not leave recording state. A lightweight companion signal lets the pill/menu show "Restarted" while `state` stays `.recording`, which keeps capture side effects stable.

**Fallback if the planner wants a single enum:** use transient cases such as `.canceled` and `.recording(recovery: .restarted)`, but be careful not to make AppDelegate stop/restart capture just to drive UI copy.

### Pattern 2: Cancel must invalidate both capture and async transcription
**What:** Treat cancel as a session invalidation event, not just a state assignment.

**Why:** The current `finish()` path launches an untracked `Task`. Without task invalidation, cancel during `.processing` can still produce `.success`, write to the clipboard, and violate both SESS-02 and CLIP-02.

**Recommended behavior:**
- Recording cancel:
  - Increment `activeSessionID`
  - Cancel and clear `transcriptionTask`
  - Reset `AudioBufferAccumulator`
  - Transition to `.idle`
  - Publish `.canceled` feedback
- Processing cancel:
  - Increment `activeSessionID`
  - Cancel and clear `transcriptionTask`
  - Transition to `.idle`
  - Publish `.canceled` feedback
  - Ignore any late transcription result whose session ID no longer matches

**Important AppDelegate implication:** `.idle` currently clears silence callbacks and UI, but does not stop `AudioCaptureService`. Phase 4 needs one of these:
- call `audioCaptureService.stop()` on any transition from `.recording` to `.idle`, or
- introduce a distinct cancel state that AppDelegate treats as a hard teardown.

The first option is lower risk and better aligned with the existing observer pattern.

### Pattern 3: Restart should reset the session buffer, not the microphone engine
**What:** Implement restart during `.recording` by clearing the current audio/session state and continuing capture on the same active engine.

**Why:** `AudioBufferAccumulator.reset()` and `AudioLevelMonitor.reset()` already exist, and restart is defined as "continue recording from a clean point." Tearing down the engine is unnecessary and adds latency/flicker.

**Recommended behavior:**
- Only allow restart while `.recording`
- Increment `activeSessionID`
- Reset `AudioBufferAccumulator`
- Reset `AudioLevelMonitor`
- Leave `state` as `.recording`
- Publish `.restarted` feedback and auto-clear it after a short timer

**Affordance options that fit the current shell:**
1. `StatusMenuView` action while recording. Lowest engineering risk; persistent and testable.
2. Optional pill action if the product wants lower friction. Requires turning off `ignoresMouseEvents`, adding closures/accessibility identifiers, and ensuring the panel still does not become a focus-stealing window.

**Recommendation:** plan for menu support first, then add pill interaction only if the phase still needs a faster affordance after planner review.

### Pattern 4: Surface microphone failures as typed errors, never silent fallback
**What:** Expand `AudioCaptureError` and `RecordingState.FailureReason` so the app can distinguish microphone permission denial, missing selected device, missing usable input, and mid-session disconnect.

**Why:** Today start failures are logged and collapsed to `.idle`, while selected-device disconnect silently falls back to the default microphone. That conflicts directly with AUDI-04 and the Phase 4 context.

**Recommended error mapping:**
```swift
enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case selectedInputUnavailable
    case noUsableInputDevice
    case selectedInputDisconnected
    case engineException(NSError)
}

extension RecordingState.FailureReason {
    case microphonePermissionDenied
    case microphoneUnavailable
    case selectedMicrophoneDisconnected
}
```

**Recommended propagation path:**
1. `AudioCaptureService.start(...)` throws typed start errors.
2. `AudioCaptureService` disconnect listener calls back with a typed disconnect failure instead of silently re-starting on the default mic.
3. `AppDelegate` forwards that failure into `ActivationStore.handleCaptureFailure(...)`.
4. `ActivationStore` resets the buffer, invalidates the session, and enters `.failure(reason: ...)`.
5. `RecordingPillView` and menu-bar icon react through existing state observation.

**Important product-specific note:** if the selected microphone is gone at recording start, do not clear `preferences.micDeviceUID` and silently fall back. Preserve the user's choice, fail visibly, and let the menu/setup flow help them recover.

### Pattern 5: Enforce a clipboard write barrier
**What:** Treat clipboard mutation as the final step of a valid success path only.

**Why:** `ClipboardService.writeToClipboard(_:)` currently calls `clearContents()` before `setString`, and `ActivationStore` ignores the returned `Bool`. The app therefore has no meaningful rollback path once it starts writing.

**Planner rule for CLIP-02:**
- Cancel: never call `ClipboardService`
- Restart: never call `ClipboardService`
- Microphone failure: never call `ClipboardService`
- No speech / unusable transcription: never call `ClipboardService`
- Late async result from a canceled/restarted session: ignore before state or clipboard mutation

**Scope note:** surfacing clipboard write failure on the success path is a real quality gap, but it is adjacent to CLIP-02 rather than required to satisfy it. The minimum correct Phase 4 behavior is to ensure recovery and no-output paths never begin a pasteboard write.

### Pattern 6: Keep recovery messaging in existing surfaces
**What:** Reuse the pill for immediate confirmation and the menu for persistent recovery actions.

**Why:** This matches the Phase 4 constraint to stay menu-bar-first and avoid opening setup automatically.

**Recommended UI split:**
- Pill:
  - `Canceled`
  - `Restarted`
  - `Microphone unavailable`
  - `Microphone access denied`
- Menu:
  - Recovery action(s): open setup, refresh microphone list, optionally retry recording
  - Persistent explanatory copy when the pill has already dismissed

## Don't Hand-Roll

| Problem | Use | Avoid |
|---------|-----|-------|
| Session invalidation | `Task` handle + session ID/token in `ActivationStore` | Letting stale async completion update state after cancel/restart |
| Restart implementation | Reset accumulator + level monitor while capture continues | Full stop/start engine cycles for every restart |
| Microphone failure mapping | Typed `AudioCaptureError` -> `RecordingState.FailureReason` translation | Stringly typed failure branching in the view |
| Recovery UI | Existing pill + menu surfaces | New setup windows or ad hoc alerts for normal recovery |
| Clipboard safety | Success-only write barrier | Attempted pasteboard rollback after a destructive write |

## Common Pitfalls

### Pitfall 1: `.idle` is not currently a hard teardown
**What goes wrong:** `ActivationStore.stop()` sets `.idle`, but `AppDelegate.onReturnedToIdle()` does not call `audioCaptureService.stop()`.

**Impact:** A naive cancel implementation can leave capture running after the UI says the session ended.

**Planner response:** treat `recording -> idle` as a teardown boundary, or add a dedicated cancel terminal state that AppDelegate tears down explicitly.

### Pitfall 2: `finish()` cannot currently be canceled safely
**What goes wrong:** `ActivationStore.finish()` launches an untracked `Task` and never stores a handle.

**Impact:** Cancel during `.processing` can still allow late success/failure updates and clipboard writes.

**Planner response:** store a task handle and gate completion on a session token.

### Pitfall 3: `AudioCaptureService` currently hides selected-mic failures
**What goes wrong:** missing selected devices are cleared from preferences at start, and mid-session disconnect triggers silent fallback to the default microphone.

**Impact:** AUDI-04 is violated and the user loses the explicit recovery path requested in context.

**Planner response:** preserve selection, stop the session, and surface a typed failure.

### Pitfall 4: Literal `Escape` cancel likely depends on pending keyboard-monitoring work
**What goes wrong:** the shipped hotkey path uses Carbon hot keys and does not need Accessibility/Input Monitoring, but background `Escape` interception is an event-tap style problem.

**Impact:** SESS-02 may be coupled to pending `CONF-02` unless the product changes the interaction model.

**Planner response:** make the dependency explicit in the plan. If `Escape` remains required, generalize the existing session-key interceptor path and wire the permission/recovery story coherently.

### Pitfall 5: Pill actions are not free
**What goes wrong:** `RecordingPillPanel` currently ignores mouse events and `RecordingPillView` has no action closures or accessibility identifiers.

**Impact:** A pill-based restart/cancel affordance is possible, but it is not a zero-cost UI tweak.

**Planner response:** use menu actions as the baseline recovery surface; add pill interaction only if needed.

### Pitfall 6: Clipboard safety depends on not starting a write
**What goes wrong:** `ClipboardService` clears contents first and `ActivationStore` ignores the return value.

**Impact:** Once a pasteboard write begins, preserving the prior clipboard is not guaranteed.

**Planner response:** satisfy CLIP-02 by preventing writes on cancel/restart/failure paths rather than trying to undo them later.

## Code Examples

### Session-Token-Gated Finish / Cancel
```swift
@MainActor
func finish() {
    guard state == .recording else { return }

    let sessionID = UUID()
    activeSessionID = sessionID
    state = .processing

    transcriptionTask = Task { [weak self] in
        await Task.yield()
        await self?.transcribeAndDispatch(for: sessionID)
    }
}

@MainActor
func cancelCurrentSession() {
    activeSessionID = UUID()
    transcriptionTask?.cancel()
    transcriptionTask = nil
    bufferAccumulator.reset()
    state = .idle
    recoveryFeedback = .canceled
}

private func transcribeAndDispatch(for sessionID: UUID) async {
    let samples = try bufferAccumulator.convertToWhisperFormat()
    guard !Task.isCancelled, sessionID == activeSessionID else { return }

    let text = try await whisperService.transcribe(samples: samples)
    guard !Task.isCancelled, sessionID == activeSessionID else { return }

    state = .success(text: text)
    _ = clipboardService.writeToClipboard(text)
}
```

### Restart Without Leaving Recording State
```swift
@MainActor
func restartCurrentSession() {
    guard state == .recording else { return }

    activeSessionID = UUID()
    bufferAccumulator.reset()
    levelReset?()              // closure from AppDelegate or injected helper
    recoveryFeedback = .restarted

    Task { [weak self] in
        try? await Task.sleep(nanoseconds: 900_000_000)
        if self?.state == .recording {
            self?.recoveryFeedback = nil
        }
    }
}
```

### Typed Capture-Failure Propagation
```swift
// AppDelegate
private func onRecordingStarted() {
    do {
        try audioCaptureService.start(...)
    } catch let error as AudioCaptureError {
        audioCaptureService.stop()
        activationStore.handleCaptureFailure(error)
    } catch {
        audioCaptureService.stop()
        activationStore.handleCaptureFailure(.engineException(error as NSError))
    }
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (bundled with Xcode) |
| Config file | `Speech2Test.xcodeproj` |
| Quick run command | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests -destination 'platform=macOS'` |
| Full suite command | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -destination 'platform=macOS'` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SESS-02 | Cancel invalidates recording/processing session, tears down capture, and leaves clipboard unchanged | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | Existing (needs expansion) |
| SESS-02 | Background `Escape` interception triggers cancel only while session keys are active | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/SpacebarInterceptorTests -destination 'platform=macOS'` | Existing interceptor tests can be generalized |
| SESS-03 | Restart clears buffered audio and keeps lifecycle in `.recording` | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | Existing (needs expansion) |
| SESS-04 | Canceled/restarted confirmation state is emitted and clears on schedule | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | Existing (needs expansion) |
| AUDI-04 | Unauthorized / unavailable / disconnected microphone becomes a typed user-visible failure | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/AudioCaptureServiceTests -destination 'platform=macOS'` | Existing (needs expansion) |
| CLIP-02 | Cancel, restart, mic failure, and no-usable-transcription paths never touch the clipboard | unit | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | Existing (needs expansion) |

### Recommended Test Seams
- `ActivationStoreTests.swift`
  - best seam for cancel/restart policy, session-token invalidation, and clipboard non-write assertions
  - add a reset-counting `AudioBufferAccumulator` test double if restart is implemented as a pure reset
- `AudioCaptureServiceTests.swift`
  - best seam for authorization denial, start failure mapping, and selected-device disconnect behavior
  - add tests that prove the service stops surfacing silent fallback when a selected device disappears
- `ClipboardServiceTests.swift`
  - keep using named pasteboards for isolation
  - useful for documenting the destructive write semantics, but Phase 4 assertions belong primarily in `ActivationStoreTests`
- `PermissionRecoveryFlowTests.swift`
  - natural UI suite for microphone-denied recovery copy/actions
  - if pill or menu recovery actions become interactive, add accessibility identifiers before depending on UI tests

### Wave 0 Gaps
- [ ] Expand `Speech2TestTests/ActivationStoreTests.swift` for cancel-during-processing, restart buffer reset, and session-token stale-result suppression
- [ ] Expand `Speech2TestTests/AudioCaptureServiceTests.swift` for typed start/disconnect failures
- [ ] Generalize `Speech2TestTests/SpacebarInterceptorTests.swift` into a session-key interceptor test if `Escape` cancel uses the same pattern
- [ ] Add UI identifiers for any new menu or pill recovery action before trying to cover SESS-04 with UI automation
- [ ] Consider extracting AppDelegate recovery branching into an injectable coordinator if integration coverage becomes hard to maintain

## Open Questions

1. Does the project want literal background `Escape` cancel strongly enough to take on the pending event-tap / keyboard-monitoring permission dependency from `CONF-02`, or should the requirement wording be revisited?
2. Is a menu-only restart affordance sufficient for Phase 4, or does the planner want the extra scope of interactive pill controls now?
3. Should clipboard-write failure on the success path be promoted into this phase, or remain a known post-Phase-4 hardening gap once CLIP-02 is satisfied?

## Sources

### Primary (HIGH confidence)
- `./.planning/phases/04-recovery-controls/04-CONTEXT.md` - locked Phase 4 product decisions and scope boundaries
- `./.planning/REQUIREMENTS.md` - authoritative requirement IDs and traceability for SESS-02, SESS-03, SESS-04, AUDI-04, CLIP-02
- `./.planning/STATE.md` - current milestone status and known clipboard-risk note
- `Speech2Test/Activation/ActivationStore.swift` - current lifecycle, finish flow, clipboard write location
- `Speech2Test/App/AppDelegate.swift` - current state observer and audio start/stop behavior
- `Speech2Test/Audio/AudioCaptureService.swift` - current audio failure origins and silent selected-device fallback
- `Speech2Test/Activation/RecordingState.swift` - current lifecycle/failure-state shape
- `Speech2Test/Shell/RecordingPillView.swift` and `Speech2Test/Shell/RecordingPillPanel.swift` - current feedback surfaces and interaction limits
- `Speech2TestTests/ActivationStoreTests.swift`, `Speech2TestTests/AudioCaptureServiceTests.swift`, `Speech2TestTests/ClipboardServiceTests.swift`, `Speech2TestUITests/PermissionRecoveryFlowTests.swift` - current validation seams
- Apple `CGEvent.tapCreate` documentation - background event-tap interception model
- Apple `CGPreflightListenEventAccess` documentation - event-tap permission preflight path
- Apple `AVCaptureDevice.authorizationStatus(for:)` documentation - microphone authorization status boundary
- Apple `AudioObjectAddPropertyListenerBlock` documentation - device-disconnect observation model
- Apple `NSPasteboard.clearContents()` and `NSPasteboard.setString(_:forType:)` documentation - destructive clipboard write semantics

### Secondary (MEDIUM confidence)
- `./.planning/phases/01-foundation-and-permissions/01-RESEARCH.md` - earlier project research on keyboard-monitoring capability boundaries
- `./.planning/phases/03-recognition-and-clipboard-loop/03-RESEARCH.md` - prior decisions on state-driven pill feedback and clipboard safety posture

## Metadata

**Confidence breakdown:**
- Current state-machine hooks: HIGH - directly verified in app code and existing tests
- Cancel/restart architecture fit: HIGH - derived from concrete lifecycle and buffer-reset seams in the current codebase
- Microphone failure propagation: HIGH - failure origins are explicit in `AudioCaptureService`, though user-visible handling is currently missing
- Clipboard integrity constraints: HIGH - current pasteboard write path is simple and easy to reason about
- Escape-cancel permission coupling: MEDIUM-HIGH - supported by current repo research and Apple event-tap guidance, but still depends on the final interception strategy

**Research date:** 2026-03-07
**Valid until:** 2026-04-07
