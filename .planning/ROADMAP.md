# Roadmap: Speech2Test

## Milestones

- ✅ **v1.0** - Phases 1-5 (shipped 2026-03-08) — See `.planning/milestones/v1.0-ROADMAP.md`
- 🚧 **v1.1 Convert Modes** - Phases 6-10 (in progress)

## Archived Milestones

<details>
<summary>✅ v1.0 — Phases 1-5 — SHIPPED 2026-03-08</summary>

See full detail: `.planning/milestones/v1.0-ROADMAP.md`

### Phase 1: Foundation and Permissions
**Goal**: Ship a native menu bar utility that can stay in the background, persist basic settings, and clearly onboard the required macOS permissions.
**Plans**: 2 plans complete

### Phase 2: Activation and Capture
**Goal**: Let the user configure activation behavior and start recording immediately from any app with the chosen microphone and uninterrupted system audio.
**Plans**: 3 plans complete

### Phase 3: Recognition and Clipboard Loop
**Goal**: Produce local transcription with punctuation, finish via the activation hotkey, write the result to the clipboard, and show trustworthy recording/processing feedback.
**Plans**: 3 plans complete

### Phase 4: Recovery Controls
**Goal**: Make cancel, restart, and microphone failure handling safe so the user can recover from mistakes without corrupting output.
**Plans**: 2 plans complete

### Phase 5: Long-Dictation Reliability
**Goal**: Support longer dictation sessions by segmenting capture, queueing transcription work, and combining best-available results in order.
**Plans**: 3 plans complete

</details>

## 🚧 v1.1 Convert Modes (In Progress)

**Milestone Goal:** Add 5 transcript rewriting modes powered by a local LLM, activated when the user's dictation starts or ends with "convert to [mode name]". The no-trigger path is completely unchanged.

### Phase 6: Dependency Integration and Build Gate
**Goal**: The project builds cleanly with mlx-swift-lm 2.30.6 included, all package dependencies resolve on a clean machine, and CI uses xcodebuild so Metal shaders compile correctly.
**Depends on**: Phase 5
**Requirements**: LLM-01, LLM-02
**Success Criteria** (what must be TRUE):
  1. `xcodebuild -resolvePackageDependencies` succeeds on a clean checkout with no Package.resolved present
  2. The app builds and runs via `xcodebuild` with no missing-symbol or metal-shader errors
  3. Plain dictation (no trigger phrase) still copies raw transcript to clipboard — no regression from adding the dependency
  4. CI build configuration comment or step explicitly documents the xcodebuild-only constraint for Metal shaders
**Plans**: 1 plan

Plans:
- [ ] 06-01-PLAN.md — Add mlx-swift-lm 2.30.6, write build.sh, verify build + regression smoke test

### Phase 7: Core Types and Intent Detection
**Goal**: ConvertMode, ConvertIntent, and IntentDetector are implemented as pure value types with no external dependencies, fully unit-tested against a corpus of real Whisper outputs, and the trigger phrase is stripped from the body at the type level before any LLM call can occur.
**Depends on**: Phase 6
**Requirements**: INTENT-01, INTENT-02, INTENT-03, MODE-01, MODE-02, MODE-03, MODE-04, MODE-05, MODE-06
**Success Criteria** (what must be TRUE):
  1. A transcript starting with any trigger phrase (e.g. "Convert to Email …") is detected and returns the correct ConvertMode with the trigger phrase removed from the body
  2. A transcript ending with any trigger phrase (e.g. "… convert to action items") is detected and returns the correct ConvertMode with the trigger phrase removed
  3. Detection is case-insensitive: "Convert to EMAIL", "convert to email", "CONVERT TO EMAIL" all match the same mode
  4. A transcript with no trigger phrase returns `.passthrough` and the body is unchanged
  5. All 6 ConvertMode cases (Clean English, Email, Slack, Teams, Action Items, AI Prompt) are present with their system prompt and activation phrase defaults
**Plans**: 2 plans

Plans:
- [x] 07-01-PLAN.md — Define ConvertMode/ConvertIntent/IntentDetector stubs, add Conversion/ group to Xcode project, write full failing test corpus (RED)
- [x] 07-02-PLAN.md — Implement IntentDetector.detect() real algorithm, turn all 39 tests GREEN, regression-check full suite

### Phase 8: LLM Rewrite Service
**Goal**: LLMRewriteService is a fully functional Swift actor that lazy-loads the Qwen2.5-1.5B-Instruct-4bit model on first use, exposes a `rewrite(body:mode:)` method behind an `LLMRewriting` protocol, and serializes all MLX inference off the main thread.
**Depends on**: Phase 7
**Requirements**: GUARD-02
**Success Criteria** (what must be TRUE):
  1. Calling `rewrite(body:mode:)` with a valid body returns a non-empty rewritten string for each of the 6 modes
  2. Any LLM inference error (model load failure, generation error, cancellation) causes `rewrite` to throw, returning no partial output
  3. The main thread is not blocked during inference — Instruments shows near-zero main-thread CPU while a rewrite is in progress
  4. The model is loaded once and reused across subsequent rewrite calls in the same session (no repeated disk reads)
**Plans**: 2 plans

Plans:
- [ ] 08-01-PLAN.md — Build the `LLMRewriteService` actor, persistent model cache path, explicit inference serialization gate, and deterministic unit coverage
- [ ] 08-02-PLAN.md — Add opt-in real-model integration tests, run the full regression gate, and complete manual profiling/cache-reuse verification

### Phase 9: ActivationStore Integration and Guards
**Goal**: The intent detection branch is wired into the existing `finalizeSession()` flow so that trigger-phrase dictations are rewritten by the LLM and land in the clipboard, the 350-word gate fires before any model call with a visible pill alert, and every failure path silently falls back to the raw transcript.
**Depends on**: Phase 8
**Requirements**: LLM-02, GUARD-01, UX-01
**Success Criteria** (what must be TRUE):
  1. A trigger-phrase dictation produces the LLM-rewritten text in the clipboard, not the raw transcript
  2. A plain dictation (no trigger phrase) still copies the raw transcript to clipboard — passthrough path completely unchanged
  3. When the conversion body exceeds 350 words, the pill flashes orange with "Input exceeds AI limit" and the raw transcript is copied to clipboard
  4. When the LLM call fails for any reason, the raw transcript is silently copied to clipboard with no partial or error output visible
  5. The pill displays a distinct loading indicator while LLM conversion is in progress (visually different from the normal transcription processing state)
**Plans**: 3 plans

Plans:
- [x] 09-01-PLAN.md — TDD: test scaffold + RecordingState contracts + ActivationStore core wiring (intent branch, DI, lastConvertedTranscription)
- [x] 09-02-PLAN.md — UI layer: pill .converting animation + .wordLimitExceeded, AppDelegate, StatusMenuView + Speech2TextApp wiring
- [ ] 09-03-PLAN.md — Manual verification: .converting animation, 350-word guard, LLM fallback, passthrough regression, menu item

### Phase 10: Settings Panel and First-Run Download UX
**Goal**: Users can view, edit, and extend conversion modes in the settings panel, and the 869 MB model download on first use shows visible progress in the menu bar status item so users know the app is working.
**Depends on**: Phase 9
**Requirements**: LLM-03, SETT-01, SETT-02, SETT-03, SETT-04
**Success Criteria** (what must be TRUE):
  1. The settings panel lists all 6 built-in modes with their activation phrase and read-only system prompt
  2. A user can edit the activation phrase for any built-in mode and the updated phrase is detected correctly on the next dictation
  3. A user can add a custom mode with a custom activation phrase and system prompt (max 280 characters) and it appears in the mode list and triggers correctly
  4. A user can delete a custom mode they previously created and it no longer appears in the list or triggers
  5. While the rewrite model is downloading for the first time, the menu bar status item shows "Downloading rewrite model X%…" and updates as progress advances
**Plans**: TBD

Plans:
- [ ] 10-01: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation and Permissions | v1.0 | 2/2 | Complete | 2026-03-08 |
| 2. Activation and Capture | v1.0 | 3/3 | Complete | 2026-03-08 |
| 3. Recognition and Clipboard Loop | v1.0 | 3/3 | Complete | 2026-03-08 |
| 4. Recovery Controls | v1.0 | 2/2 | Complete | 2026-03-08 |
| 5. Long-Dictation Reliability | v1.0 | 3/3 | Complete | 2026-03-08 |
| 6. Dependency Integration and Build Gate | 1/1 | Complete   | 2026-03-19 | - |
| 7. Core Types and Intent Detection | v1.1 | 2/2 | Complete | 2026-03-19 |
| 8. LLM Rewrite Service | v1.1 | 0/2 | Planned | - |
| 9. ActivationStore Integration and Guards | 1/3 | In Progress|  | - |
| 10. Settings Panel and First-Run Download UX | v1.1 | 0/TBD | Not started | - |

---
*Last updated: 2026-03-19 after Phase 8 planning*
