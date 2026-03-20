# Phase 9: ActivationStore Integration and Guards - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire `IntentDetector.detect()` and `LLMRewriteService` into the existing `finalizeSession()` flow. After Whisper produces trimmed text, intent detection branches the path: trigger detected → word-limit check → LLM rewrite → clipboard; passthrough → existing clipboard copy behavior unchanged. Three guards fire before any LLM call: session staleness check (already present), 350-word limit, and LLM failure fallback. The pill gains a new `.converting` state for the duration of LLM inference. A new "Copy Last AI Converted Transcription" menu item is added alongside the existing "Copy Last Transcription". Phase 10 adds the settings UI and custom mode editing; this phase wires the runtime path only.

</domain>

<decisions>
## Implementation Decisions

### RecordingState: new .converting case
- Add `.converting` (no associated value) to `RecordingState` alongside `.idle`, `.recording`, `.processing`, `.success`, `.failure`
- `.converting` is treated as non-terminal, same as `.processing` — `arm()` blocks new recordings while `.converting` is active
- Pill renders a pulsing/animated indicator during `.converting` (visually distinct from the static `.processing` indicator)
- Pill stays the same physical size as `.processing` — no layout shift during transition

### RecordingState: success with conversion flag
- Extend `.success` to carry a `converted: Bool` flag (Claude's discretion on exact shape)
- Pill copy: `converted && pasted` → "Converted & Pasted"; `converted && !pasted` → "Converted"; `!converted && pasted` → "Pasted" (existing); `!converted && !pasted` → "Copied" (existing)
- Sound: `playSuccess()` (Glass) — same as plain transcription success

### 350-word limit alert
- Add `.wordLimitExceeded` to `RecordingState.FailureReason` — reuses the `.failure()` path
- Pill copy: "Input exceeds AI limit", orange color treatment
- Auto-dismiss: 2 seconds (same as other failures)
- Sound: `playFailure()` (Basso)
- Raw transcript is still copied to clipboard before the alert state is set

### LLM failure fallback
- Any `LLMRewriteService.rewrite()` throw silently falls back: raw transcript copied to clipboard, state transitions to `.success(converted: false)`
- No error copy visible to the user — the raw transcript delivery is the silent fallback

### lastTranscription / lastConvertedTranscription
- `lastTranscription` (existing) continues to store the raw Whisper output — "Copy Last Transcription" is unchanged
- Add `lastConvertedTranscription: String?` to `ActivationStore` — stores the LLM output after a successful conversion
- New menu item: "Copy Last AI Converted Transcription" — calls `clipboardService.writeToClipboard(lastConvertedTranscription)` when non-nil

### IntentDetector call site
- `IntentDetector.detect()` is called immediately after `trimmed` is produced, before any clipboard write
- Modes passed: `preferences.convertModes` (new `ShellPreferences` property, defaults to `ConvertMode.allBuiltIns` — all 6 non-passthrough cases)
- Phase 10 adds UI to modify `preferences.convertModes`; Phase 9 adds the storage with the default

### LLMRewriteService injection
- Add `llmRewriteService: any LLMRewriting` parameter to `ActivationStore.init()`, defaulting to `LLMRewriteService.shared`
- Mirrors the existing `whisperService: any WhisperTranscribing` pattern exactly

### Unit test coverage
- Happy path only: trigger detected → LLM call → `.converting` → `.converted` state; passthrough path unchanged
- Use injected mock `LLMRewriting` (same DI seam as production)
- Failure/guard paths (350-word gate, LLM throw fallback) verified manually, not in unit tests

### Claude's Discretion
- Exact `RecordingState.success` shape extension (`converted: Bool` flag vs new case) — whichever requires less switch-statement churn across the codebase
- Pill animation implementation details (pulse timing, opacity range)
- Orange color value for `.wordLimitExceeded` pill rendering
- `ConvertMode.allBuiltIns` computed property name/location

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ActivationStore.finalizeSession()` — async, already background-dispatched; insert intent branch after `trimmed` is produced (line ~267)
- `ClipboardService.writeToClipboard()` — used for both the raw-transcript fallback and the LLM output write
- `ActivationStore.copyLastTranscription()` — pattern to follow for the new `copyLastConvertedTranscription()` method
- `LLMRewriting` protocol (`rewrite(body:mode:) async throws -> String`) — ready to inject
- `IntentDetector.detect(transcript:modes:) -> ConvertIntent` — ready to call; `ConvertIntent.strippedBody` is the LLM input, `ConvertIntent.originalTranscript` is the fallback

### Established Patterns
- `RecordingState` is a simple enum in `RecordingState.swift`; new cases follow the existing shape
- `ActivationStore` init uses protocol-typed parameters with default values for all services — add `llmRewriteService` the same way
- `scheduleDismissToIdle(afterNanoseconds:sessionID:)` handles all auto-dismiss timing — reuse for `.wordLimitExceeded` with 2_000_000_000 ns
- `ShellPreferences` holds all user-configurable settings; add `convertModes: [ConvertMode]` with `@AppStorage` or equivalent persistence

### Integration Points
- `finalizeSession()` in `ActivationStore.swift` — the sole insertion point for the entire Phase 9 branch
- `RecordingPillPanel.swift` — reads `RecordingState` to determine pill size/appearance; add `.converting` case
- Menu bar shell — add "Copy Last AI Converted Transcription" menu item gated on `lastConvertedTranscription != nil`
- `ShellPreferences` — add `convertModes: [ConvertMode]` property (default: all 6 built-ins)

</code_context>

<specifics>
## Specific Ideas

- The pill animation during `.converting` should feel like "thinking" — a slow pulse or shimmer, not a progress bar. Visually distinct from the static indicator used during Whisper `.processing`.
- "Copy Last AI Converted Transcription" is a new menu dropdown item alongside the existing "Copy Last Transcription". Both are always present; the new one is disabled when `lastConvertedTranscription` is nil.
- The LLM failure fallback is completely silent — user sees `.success` with "Copied" copy and the raw transcript in their clipboard. No indication that conversion was attempted and failed.

</specifics>

<deferred>
## Deferred Ideas

- Custom mode editing UI — Phase 10 (Settings Panel)
- Per-mode activation phrase customization — Phase 10
- "Copy Last AI Converted Transcription" persistence across app restarts — not requested, out of scope

</deferred>

---

*Phase: 09-activationstore-integration-and-guards*
*Context gathered: 2026-03-19*
