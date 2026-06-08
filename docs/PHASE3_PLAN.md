# TypeLessBuddy cleanup — continuation handoff (Phase 3 onward)

> **Reading this in a fresh session?** Start here. This is a multi-phase cleanup of
> the TypeLessBuddy macOS app. **Phases 1, 2, and 4a are done and merged to `main`.**
> The remaining work is **Phase 3 (split the god-files)** and optional **Phase 5
> (polish)**. Full findings live in `CODEBASE_AUDIT.md`; test/build conventions live
> in `AGENTS.md`. Read the "Must-know constraints" section before changing code.

---

## What the app is (orientation)

Local-first macOS menu-bar **dictation** app (SwiftUI + AppKit). Flow: hotkey →
record mic → transcribe locally (WhisperKit) → optionally **rewrite** with a local
MLX model or a cloud LLM → copy / auto-paste. Source is folder-by-domain under
`TypeLessBuddy/` (App, Activation, Audio, Clipboard, Conversion*, Permissions,
Persistence, Readiness, Shell, Transcription). ~58 Swift files. 479 unit tests.
(*the `Conversion/` folder is renamed to `Rewrite/` as part of Phase 3 — see below.)

## Status — done and on `main`

- **Phase 1 — stabilize:** unit suite is deterministic and green (479 / 7 skipped /
  0 failures). Injected a `Sleeping` clock into `ActivationStore` so timer tests use
  virtual time; converted fixed `Task.sleep` waits to `waitUntil` polling; silenced
  system sounds in tests (`ActivationSoundPlayer.silent` injected by `makeStore`).
  Added CI (`.github/workflows/ci.yml`) + **report-only** SwiftLint/SwiftFormat
  configs (`.swiftlint.yml`, `.swiftformat`).
- **Phase 2 — waste:** relocated `generate_icon.swift` → `scripts/`; documented the
  `build/` dir in `AGENTS.md`. (The flagged "legacy" migrations turned out to be
  tested/intentional and were **kept** — do not remove them.)
- **Phase 4a — vocabulary (done before the split on purpose):** unified the domain
  language so the split lands on clean concepts. See the locked table below.

## Locked vocabulary (already applied — keep consistent)

| Layer | Canonical term | Notes |
|---|---|---|
| Feature / persona | `assistant` (code), `"Buddy"` (default name + brand) | unchanged |
| **Operation** (transcript → finished text) | **`rewrite`** | `RecordingState.rewriting`, `.success(… rewritten:)`, pill "Rewriting…", `rewriteModel*` |
| Engine — operation side | `rewrite`, no `LLM` | `Rewriting` (protocol), `LocalRewriteService`, `CloudRewriteService`, `RewriteError` |
| Engine — provider side | **`CloudLLM*` (kept)** | `CloudLLMProvider`, `CloudLLMConfig`, `CloudLLMKeychain` |
| Audio format conversion | **`convert*` (do NOT touch)** | `convertToWhisperFormat`, `AVAudioConverter`, `AudioBufferAccumulatorError.conversionFailed` — unrelated to rewrite |

## Must-know constraints (read before coding)

- **`project.pbxproj` is hand-maintained.** Every new/renamed/moved file must be
  registered manually (sequential `A0…` IDs across the four PBX sections). This is
  the main risk/cost in Phase 3 — minimize new files, group cohesively.
- **Test scheme:** run `xcodebuild test -scheme TypeLessBuddy -destination 'platform=macOS' -derivedDataPath build/DerivedData-app-tests`
  after every change. The `TypeLessBuddy` scheme is the DI'd unit suite and never
  triggers OS prompts. Do **not** pipe its output through `tail`/formatters without
  `set -o pipefail` (a pipe masked the real exit code earlier). UI tests
  (`RUN_UI_TESTS`) and model-integration tests (`RUN_MODEL_INTEGRATION_TESTS`) are
  gated off — leave them.
- **Behavior-preserving only.** Phase 3 is a pure refactor; the 479 tests are the
  net. For `SetupWindowView` (view layer, ~no automated coverage) also do a **manual
  app run** (`scripts/build-app.sh`, then exercise settings + onboarding + the pill).
- **`build/`** is the fixed local build/DerivedData dir (gitignored; safe to delete).
- **Definition of "done" for Phase 3 = clear the 4 production SwiftLint errors**
  (below). Warnings are acceptable. The lint job is currently report-only
  (`continue-on-error`); flip it to blocking only after the errors are gone.

### The 4 production lint errors to clear (current)
```
ActivationStore.swift:570  function_body  finalizeSession  259 lines (>250)
ActivationStore.swift:130  type_body      class            1293 lines (>1000)
SetupWindowView.swift      file_length                     4039 lines (>1500)
SetupWindowView.swift:2127 type_body      main struct      2128 lines (>1000)
```
(Test-file lint errors — `ActivationStoreTests`, the `force_try` in
`DictionaryStoreTests` — are separate and lower priority; tackle in Phase 5 if at all.)

---

## Phase 3 — split the god-files

Moderate decomposition, **not** maximal (the owner expects a few features over time,
not heavy development). Aim ~8 new files total. One branch per file/group, merged when
green.

### Stage 1 — `ActivationStore.swift` (logic-only, do FIRST — no manual app run needed)

Current shape (1,639 lines): `ActivationSoundPlayer` (struct, ~L8), `Sleeping`/
`SystemSleeper` (~L111), then `final class ActivationStore` (body L130, 1,293 lines)
with MARKs at `Public API` (L315) and `Private transcription flow` (L500). The
259-line `finalizeSession` starts ~L570.

1. **Break up `finalizeSession`** into named private steps — no new types, just
   methods (e.g. `transcribe(...)`, `routeAndRewrite(...)`, `deliverResult(...)`,
   `handlePipelineFailure(...)`). Clears the function-length error; makes the core
   flow reviewable. **Note:** effects (clipboard write, note save, `rewritten`
   text, `successNoteSaveState`) are intentionally set *before* `state = .success`
   is published — preserve that ordering (tests rely on it via `waitUntil { isSuccess }`).
2. **Split the class across extension files** (same type — SwiftLint counts only the
   primary declaration, so this clears the type/file errors at low risk). Suggested
   grouping by the existing concerns:
   - `ActivationStore+Pipeline.swift` — recording lifecycle + transcription/rewrite flow
   - `ActivationStore+Models.swift` — whisper/rewrite warmup, idle-unload, download gate
   - `ActivationStore+Notes.swift` — note capture, AI title generation, history persistence
   - `ActivationSupport.swift` — move `ActivationSoundPlayer` + `Sleeping`/`SystemSleeper` out
3. Verify: unit suite green; `ActivationStore` lint errors gone.

### Stage 2 — `SetupWindowView.swift` (highest readability win; needs manual run)

Current shape (4,510 lines): **36** `struct …: View`, mostly small self-contained
components, plus the main `SetupWindowView` struct (body L2127, 2,128 lines) that
also performs file/keychain I/O.

1. **Lift the self-contained component structs** into ~4–6 cohesive files (mechanical,
   low risk → clears the file-length error). Suggested grouping:
   - `Shell/Settings/ShortcutRecorders.swift` — `ShortcutRecorderField`, `KeyComboRecorder`, `HoldShortcutRecorder`, `MouseButtonRecorder`
   - `Shell/Settings/SettingsComponents.swift` — `SetupFieldRow`, `SettingsSectionCard`, `SettingsSectionActionButton`, `SettingsSidebarButton`, `SettingsCardFlashModifier`, the `*Row` toggles, `ImmediateHelpIcon`, `CircularProgressRing`, `ModelDownloadStatusRow`, `CompactSetupStatusChip`
   - `Shell/Settings/OnboardingComponents.swift` — the `Onboarding*` structs
   - `Shell/Settings/HistoryViews.swift` — `HistoryModeBadge`, `HistoryEntryRow`, `HistoryFolderRow`, `HistoryDetailPane`, `HistoryFormat`
   - `Shell/Settings/PillPositionPicker.swift` + `AssistantSystemPromptSheet.swift`
2. **Extract business logic out of the view** (the real fix → clears the struct-length
   error AND makes untested logic testable). Follow the existing
   `AIAssistantSettingsViewModel` precedent:
   - Cloud config (keychain/network): `loadCloudAPIKeyIfNeeded`, `fetchCloudModels`,
     `saveCloudSettings`, `testCloudConnection`, `resolvedCloudRequestAPIKey`
   - History file ops: `reloadHistoryEntries`, `selectHistoryEntry`,
     `loadHistoryEntryDetail`, `copySelectedHistoryEntry`, `deleteHistoryEntry`,
     `clearAllHistory`, `revealHistoryFolder/Entry` → push into a view model or the
     existing `HistoryCaptureService`.
   - Add unit tests for the extracted view models.
3. Verify: unit suite + **manual app run** (settings/onboarding/pill); lint errors gone.

### Fold-in file/folder renames (the single pbxproj-churn step)

These are deferred from Phase 4a — do them as part of the Stage-1/Stage-2 moves so
pbxproj is edited once:
- `Conversion/LLMRewriteService.swift` → `Rewrite/LocalRewriteService.swift`
- `Conversion/CloudLLMRewriteService.swift` → `Rewrite/CloudRewriteService.swift`
- rename the `Conversion/` folder → `Rewrite/` (move the other files too:
  `CloudLLMProvider`, `CloudModelListService`, `ExternalTextPromptBuilder`,
  `ExternalTextSourceClassifier`, `AssistantNoteIntentClassifier`,
  `ReplacementPack*`, `RewriteModelTier`, `RewriteModelLoadState`)

---

## Phase 5 — polish (optional, after Phase 3)

Low priority; do opportunistically when touching the relevant code.
- **Filenames ≠ contents** (also pbxproj renames): `TriggerTranscriptSplit.swift`
  defines `TriggerTranscriptDetection`; `Shell/AIAssistantSettingsView.swift`'s
  primary view is `AIAssistantInlineRowView`; `Shell/DictionarySettingsView.swift`'s
  primary view is `ReplacementsSectionView`.
- **Document the 7 skipped tests** (why each skips) — Workstream B leftover.
- **Refresh `feature-workflows/` + `feature-map/` docs** (dated May 4, predate these
  refactors) and add a `RecordingState` transition diagram — Workstream D.
- **Tighten lint**: once Phase 3 clears the production errors, flip the CI lint job
  off `continue-on-error`; optionally split the long test files; remove the test
  `force_try`.
- Consider a small design-tokens file for the inline `*Metrics`/`SetupColorPalette`
  styling (very low priority).

---

## Git state

- All of Phase 1 / 2 / 4a is merged to `main` (latest merge: "Merge Phase 4a").
- Old feature branches (`phase1/*`, `phase2/remove-waste`, `phase4a/vocabulary`) are
  merged and can be deleted.
- Start Phase 3 on a fresh branch off `main` (e.g. `phase3/split-activationstore`).
