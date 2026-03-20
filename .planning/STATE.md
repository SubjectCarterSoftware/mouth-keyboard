---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Convert Modes
current_plan: 2
status: planning
stopped_at: Completed 11-05-PLAN.md
last_updated: "2026-03-20T11:45:05.116Z"
last_activity: 2026-03-20
progress:
  total_phases: 11
  completed_phases: 11
  total_plans: 28
  completed_plans: 28
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-18)

**Core value:** From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.
**Current focus:** Phase 8 complete — LLM Rewrite Service production actor + offline unit coverage + opt-in integration tests; ready for Phase 9 planning

## Current Position

Phase: 8 of 10 (LLM Rewrite Service)
Current Plan: 2
Total Plans in Phase: 2
Status: Phase complete; ready for Phase 9 planning (ActivationStore integration)
Last Activity: 2026-03-20
Progress: [██████████] 100%

## Performance Metrics

**Velocity (v1.0 reference):**
- Total plans completed: 13 (v1.0)
- Average duration: ~25 min (excluding multi-session 02-03)
- Total execution time: ~3h 03m

**By Phase (v1.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 foundation-and-permissions | 2 | — | — |
| 02 activation-and-capture | 3 | ~2h | ~40m |
| 03 recognition-and-clipboard-loop | 3 | ~22m | ~7m |
| 04 recovery-controls | 2 | ~5h | ~2.5h |
| 05 long-dictation-reliability | 3 | ~63m | ~21m |
| Phase 06-dependency-integration-and-build-gate P01 | 20 | 4 tasks | 4 files |
| Phase 07-core-types-and-intent-detection P01 | 5 min | 2 tasks | 5 files |
| Phase 07-core-types-and-intent-detection P02 | 4 min | 2 tasks | 2 files |
| Phase 08 P01 | 5 min | 2 tasks | 3 files |
| Phase 08 P02 | 30 min | 3 tasks | 6 files |
| Phase 09-activationstore-integration-and-guards P09-01 | 25 | 3 tasks | 8 files |
| Phase 09-activationstore-integration-and-guards P02 | 8 | 3 tasks | 4 files |
| Phase 09-activationstore-integration-and-guards P03 | 10 | 2 tasks | 0 files |
| Phase 10-fuzzy-intent-detection P01 | 8 | 2 tasks | 8 files |
| Phase 10-fuzzy-intent-detection P02 | 525757 | 2 tasks | 3 files |
| Phase 11-intent-configuration-ui P01 | 15 | 2 tasks | 5 files |
| Phase 11-intent-configuration-ui P02 | 11 | 2 tasks | 7 files |
| Phase 11-intent-configuration-ui P03 | 12 | 2 tasks | 3 files |
| Phase 11-intent-configuration-ui P04 | 5 | 2 tasks | 4 files |
| Phase 11-intent-configuration-ui P05 | 20 | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: LLM-02 (passthrough unchanged) is verified in Phase 9, not Phase 6 — Phase 6 confirms no regression from adding the SPM dependency; Phase 9 verifies the behavior is preserved through ActivationStore integration
- [Roadmap]: GUARD-02 (LLM failure fallback) spans Phase 8 (error contract defined in LLMRewriteService) and Phase 9 (fallback wired in ActivationStore) — assigned to Phase 8 for traceability, verified in Phase 9 success criteria
- [Research]: swift-transformers version conflict (WhisperKit 0.17.0 pins 1.1.x, mlx-swift-lm requires 1.2.0+) is a go/no-go gate — must resolve before Phase 6 plan execution
- [Research]: Metal shaders require xcodebuild; swift build will silently miss default.metallib — CI constraint must be documented in Phase 6
- [Research]: LLM inference must never run on @MainActor — LLMRewriteService actor pattern mirrors WhisperService
- [Phase 06-dependency-integration-and-build-gate]: mlx-swift-lm 2.30.6 uses upToNextMinorVersion; swift-transformers conflict did not materialize; Package.resolved committed for reproducible builds
- [Phase 07-core-types-and-intent-detection]: ConvertMode owns activationPhraseCandidates so future detector callers can consume mode contracts directly.
- [Phase 07-core-types-and-intent-detection]: Plan 01 remains intentionally RED: IntentDetector.detect stays passthrough until Plan 02 turns the corpus green.
- [Phase 07-core-types-and-intent-detection]: Verification retries redirect Swift and SwiftPM caches into the workspace before treating GitHub DNS failures as environment blockers.
- [Phase 07-core-types-and-intent-detection]: Trailing matches strip any surviving leading trigger phrase from the returned body so end-wins transcripts resolve to clean content.
- [Phase 08]: Use Application Support-backed Hub downloads at ~/Library/Application Support/Speech2Text/RewriteModel for rewrite models.
- [Phase 08]: Serialize rewrite generation with an explicit async gate so concurrent calls cannot overlap MLX inference across suspension points.
- [Phase 08]: Expose internal loader/stream seams in LLMRewriteService so deterministic offline tests can cover GUARD-02 failure contracts without model downloads.
- [Phase 08-02]: AsyncThrowingStream terminates via nil (not CancellationError) when consumer task is cancelled — must check Task.isCancelled after the for-try-await loop.
- [Phase 08-02]: Opt-in integration test pattern: guard ENABLE_LLM_INTEGRATION_TESTS=1 + XCTSkip; use defaultLoader (internal) as loader seam for counting proxy without importing MLXLLM types.
- [Phase 09-01]: Passthrough path in finalizeSession() is completely unchanged (LLM-02): pasteOnCompletion honored, raw text to clipboard, converted: false
- [Phase 09-01]: Word count gate (GUARD-01) measures strippedBody (trigger removed), not full trimmed transcript
- [Phase 09-01]: LLM failure (GUARD-02) is silent: raw transcript to clipboard, state .success(converted: false) — no error surfaced to user
- [Phase 09-01]: .converting is non-terminal so arm() is blocked but cancelCurrentSession() guard unchanged (.recording || .processing only)
- [Phase 09-02]: convertingContent uses scale animation (scaleEffect toggled by pulseOpacity) while processingContent uses opacity — same @State var, different visual treatment for clear distinction
- [Phase 09-02]: failureBackground(for:) helper isolates color-per-reason logic — easy to extend for future FailureReason types needing distinct colors
- [Phase 09-02]: StatusMenuView 'Copy Last AI Converted Transcription' is always-present with .disabled modifier (not conditionally hidden) — consistent menu layout per CONTEXT.md spec
- [Phase 09-activationstore-integration-and-guards]: All 5 Phase 9 verification behaviors confirmed in live app — no code changes required
- [Phase 10-fuzzy-intent-detection]: IntentCatalog now drives IntentDetector phrase matching; activationPhraseCandidates removed from ConvertMode
- [Phase 10-fuzzy-intent-detection]: StringSimilarity stub returns 0.0; Plan 02 provides real Jaro-Winkler implementation
- [Phase 10-fuzzy-intent-detection]: confidenceThreshold: 0.82 for email/slack/teams; 0.85 for cleanEnglish; 0.80 for actionItems/aiPrompt
- [Phase 10-fuzzy-intent-detection]: Windowed token JW (not full-string JW) aligns individual tokens; 3-token minimum prevents 2-token pattern false positives; exact-match priority in scoreAllZone discards fuzzy competitors when exact wins exist
- [Phase 10-fuzzy-intent-detection]: rangeInOriginal with normalized fallback: body extraction works when normalization changes string length by mapping prefix offset and clamping upperBound
- [Phase 10-fuzzy-intent-detection]: Catalog additions 'as a mail' and 'send as an email': natural paraphrases belong in catalog as explicit patterns rather than relying on fuzzy edge cases
- [Phase 11-01]: UserIntentStore uses actor isolation; all mutation serialized via Swift concurrency
- [Phase 11-01]: storeURL init parameter enables hermetic tests using FileManager.temporaryDirectory UUIDs — no App Support pollution
- [Phase 11-01]: Silent degradation on JSON corruption: store starts fresh, never propagates decode errors to callers
- [Phase Phase 11-02]: rewrite(body:mode:) delegates to rewriteCore(body:instructions:) private helper — single code path, backward compatible
- [Phase Phase 11-02]: Custom intent mode field is .passthrough (no new ConvertMode cases); caller distinguishes via customIntentID = aliases.first
- [Phase Phase 11-02]: effectiveSystemPrompt nil from detector — ActivationStore (Plan 03) resolves it; detector stays pure detection logic
- [Phase Phase 11-03]: allEntries() snapshot taken once at session-start — avoids repeated actor hops, provides consistent view for the whole finalizeSession call
- [Phase Phase 11-03]: passthrough check updated to intent.mode == .passthrough && intent.customIntentID == nil — custom intents use .passthrough mode but are NOT passthrough
- [Phase Phase 11-03]: Dual-path LLM routing: instructions overload for user-configured intents, mode overload for defaults — zero behavior change for unconfigured modes
- [Phase Phase 11-03]: UserIntentStore.shared singleton added alongside existing init(storeURL:) injection pattern for tests
- [Phase 11-04]: SetupWindowView uses sheet (not TabView) for Modes — existing view is a ScrollView form; sheet is consistent and minimal
- [Phase 11-04]: Phrase pattern generation updates store entry only if it already exists — avoids orphan entries before user saves a new custom mode
- [Phase 11-05]: NavigationSplitView on macOS requires List(selection:) binding to drive detail column — NavigationLink inside sidebar is a no-op
- [Phase 11-05]: Use .id(row.id) on detail IntentEditView to force StateObject recreation when sidebar selection changes
- [Phase 11-05]: Manage Modes sheet minWidth set to 920 to fit sidebar + HSplitView left+right panes without clipping

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 10 flag]: swift-transformers issue #335 (download progress handler) needs validation against current 1.2.0 release before Phase 10 planning begins.
- [Unresolved pre-existing failures]: HotkeyServiceTests.testDefaultActivationShortcutIsControlV (default shortcut changed from ⌃ to ⌥) and ShellPreferencesModelTests.testLaunchAtLoginDefaultsToFalse (state leak between test runs) — both out of scope, need separate attention.
- [Uncommitted project.pbxproj changes]: Xcode reformatted project.pbxproj (UUID reassignment for MLXLLM/MLXLMCommon framework refs, whitespace normalization). Needs review and commit before Phase 9.

## Session Continuity

Last session: 2026-03-20T11:45:05.114Z
Stopped at: Completed 11-05-PLAN.md
Resume file: None
