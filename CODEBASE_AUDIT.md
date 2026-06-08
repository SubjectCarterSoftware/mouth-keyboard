# TypeLessBuddy — Codebase Audit & Cleanup Plan

> Investigation-only review. No source code was modified to produce this report. Read-only validation commands were run and are reported in §8.
> Scope: full repo at `/Users/elicarter/Workspace/TypeLessBuddy` (branch `main`, clean tree, HEAD `c285057`).
> Generated: 2026-06-08.

---

## 1. Executive summary

TypeLessBuddy is a **macOS menu-bar dictation app** (SwiftUI + AppKit) that records mic audio, transcribes locally with WhisperKit, optionally rewrites the text with a local MLX model or a cloud LLM, then copies/auto-pastes the result. For a "largely vibecoded" project it is in **better shape than typical**: clean folder-by-domain layout, protocol-based dependency injection on most services, value-type domain models, and a large unit suite (480 test methods). There is almost no debug cruft — **0 `try!`, 0 `fatalError`, 0 `TODO/FIXME`, 0 `print`**, only 12 (safe) force-unwraps.

The problems are **concentrated and structural**, not scattered sloppiness:

- **Two god-files dominate the codebase.** `SetupWindowView.swift` (4,510 lines) and `ActivationStore.swift` (1,609 lines) hold a huge fraction of all logic and side effects. They are the riskiest things to change and the least view-testable.
- **The default test scheme is not actually green.** A read-only `xcodebuild test` run produced **471 passed / 7 skipped / 1 failed → `** TEST FAILED **`**. The single failure is a flaky ~11-second wall-clock-`sleep` test. This silently undermines "is it safe to change?"
- **The AI feature has five names.** "buddy" / "assistant" / "rewrite" / "conversion" / "LLM" are all the same concept, spread across folders, files, and types.
- **Business logic and file/keychain I/O live inside the giant SwiftUI view**, untested at the view layer.
- **No linter, no formatter, no CI.** Nothing mechanically guards quality on a vibecoded codebase.

Biggest cleanup wins, in order: (1) stabilize the flaky timing tests so the suite is trustworthy; (2) split the two god-files; (3) unify the AI-feature vocabulary; (4) pull file/keychain I/O out of the view.

**Overall health: 6.5/10** — solid bones and good test breadth, dragged down by two oversized modules, vocabulary drift, and a non-green default test run.

---

## 2. What the app does

(Derived from `README.md`, `feature-workflows/*`, and code — no requirements invented.)

**Purpose:** local-first voice-to-text for macOS. Speak via a hotkey, get transcribed/refined text on the clipboard or auto-pasted into the frontmost app.

**Main user flows (observed in code):**
1. **Dictate → transcribe → output.** Hotkey/hold (`HotkeyService`) → `ActivationStore.arm()/beginHoldSession()` → `AudioCaptureService` captures → `WhisperService` transcribes locally → text copied / auto-pasted (`ClipboardService`, `PasteService`).
2. **"Buddy"/assistant rewrite.** If the transcript triggers the assistant (`TriggerTranscriptParser.detect`), text is routed through a rewrite pipeline — local (`LLMRewriteService`, MLX) or cloud (`CloudLLMRewriteService`: OpenAI/Anthropic/Google) selected via the `LLMRewriting` protocol.
3. **Context routing.** `ExternalTextSourceClassifier` deterministically decides whether the command refers to last transcription / clipboard / selected text; `ExternalTextPromptBuilder` assembles the prompt.
4. **Capture to note/history.** Results optionally persisted via `NoteCaptureService` / `HistoryCaptureService`.
5. **Onboarding & permissions.** `SetupWindowView` (onboarding + settings) + `ReadinessStore` gate mic / accessibility (post-event) permissions.

**Core domain concepts:** recording session lifecycle (`RecordingState`), readiness/permissions (`ReadinessSnapshot`, `PermissionKind`), trigger profiles (`TriggerProfile`), rewrite model tiers (`RewriteModelTier`, `WhisperModelChoice`), word-replacement / vocabulary packs (`DictionaryStore`, `ReplacementPackCatalog`).

---

## 3. Architecture map

**Top level:** `TypeLessBuddy/` (app, 58 Swift files, ~20k LOC), `TypeLessBuddyTests/` (31 files), `TypeLessBuddyUITests/` (3 files), `scripts/` (build/dmg), `docs/`, `feature-map/` + `feature-workflows/` (design prose), `build/` (gitignored, ~13 GB of derived data).

**App folders (by domain — this part is good):**
- `App/` — entry & shell: `TypeLessBuddyApp.swift` (`@main`, empty `Settings` scene), `AppDelegate.swift` (565 lines — the *real* bootstrap), `StatusMenuController.swift` (667).
- `Activation/` — input & session: `ActivationStore.swift` (1,609 — central state machine), `HotkeyService.swift` (837), `TriggerProfile*`, `TextReplacementEngine`, `TriggerTranscriptParser`.
- `Audio/` — `AudioCaptureService` (356), `AudioBufferAccumulator`, `AudioDeviceService`, `AudioLevelMonitor`, `MicProbeMonitor`, `LiveCalibrationSampleCapturer`.
- `Conversion/` — the AI/rewrite layer: `LLMRewriteService` (1,196), `CloudLLMRewriteService`, `CloudLLMProvider`, `CloudModelListService`, `ExternalTextPromptBuilder`, `ExternalTextSourceClassifier`, `AssistantNoteIntentClassifier`, `ReplacementPack*`, `RewriteModelTier/LoadState`.
- `Transcription/` — `WhisperService` (678; also defines `WhisperModelLoadState` at line 535), `WhisperModelChoice`, `TranscriptionResult`.
- `Persistence/` — `ShellPreferences` (853), `HistoryCaptureService`, `NoteCaptureService`, `DictionaryStore`, `CloudLLMKeychain`, `StoreURLResolver`, `StoreQuarantine`.
- `Permissions/` — `Microphone/Keyboard/PostEvent PermissionService`.
- `Readiness/` — `ReadinessStore`, `ReadinessSnapshot`.
- `Clipboard/` — `ClipboardService`, `PasteService`.
- `Shell/` — **all SwiftUI views**: `SetupWindowView` (4,510), `RecordingPillView` (1,136), `RecordingPillPanel` (358; also defines `RecordingPillPreviewPanel:228`), `AIAssistantSettingsView` (567), `DictionarySettingsView` (495), `GuideWindowView`, `PermissionChecklistView`, `MicPriorityPicker`, formatters.

**How data/state/UI/side-effects are handled:**
- **State:** Combine `ObservableObject` stores, almost all **singletons** (12 × `static let shared`). `ActivationStore.state: @Published RecordingState` is the spine; `AppDelegate` subscribes (`AppDelegate.swift:116-136`) and drives audio capture + menu icon off state transitions.
- **Side effects:** centralized in `ActivationStore` (transcription, rewrite, paste, note/history, model warmup/unload) and in `AppDelegate` (windows, capture wiring, permission prompts).
- **UI:** SwiftUI hosted in AppKit `NSWindow`/`NSPanel` (`AppDelegate.presentSetupWindow:319`, `presentGuideWindow:393`). Inline styling via `SetupColorPalette` + many private `*Metrics` enums.
- **DI:** good — services take protocol dependencies with `.live`/default factories (e.g. `MicrophonePermissionService.live`, `probeMonitorFactory` in `AudioCaptureService.swift:74`), which is why unit tests can avoid OS prompts.

---

## 4. High-risk issues

### H1 — `ActivationStore` is a god object central to every flow
- **Issue:** 1,609 lines, ~80 methods, `@MainActor final class ActivationStore: ObservableObject` (`ActivationStore.swift:104`). One private method, `finalizeSession(sessionID:)`, spans **lines 541–824 (~283 lines)**. It owns: recording lifecycle, transcription, rewrite routing, note saving, history persistence, AI note-title generation, model download-gating, model warmup/idle-unload, paste with clipboard protection, selected-text/image capture, success-dismiss timers, and sound effects (`ActivationSoundPlayer`).
- **Evidence:** method index in `ActivationStore.swift` (e.g. `finalizeSession:541`, `generateNoteTitle:1090`, `pasteWithClipboardProtection:881`, `beginModelDownloadGate:1532`, `scheduleRewriteModelIdleUnload:1584`).
- **Why it matters:** every behavior change touches this file; the 283-line method is unreviewable in isolation; merge-conflict and regression magnet.
- **Affected files:** `Activation/ActivationStore.swift` (+ `ActivationStoreTests.swift`, 4,840 lines).
- **Recommended future action:** extract cohesive collaborators (e.g. `RewriteRouter`, `CaptureFinalizer`, `ModelGate`, `SuccessTimer`, `NoteTitleGenerator`) behind the existing DI pattern. Break `finalizeSession` into named steps. Do **after** test stabilization (H3).

### H2 — `SetupWindowView` is a 4,510-line view with embedded business logic and I/O
- **Issue:** 36 `struct …: View` types in one file; the main `SetupWindowView` (`:2127`) has **34 stored property wrappers** and methods that perform **filesystem and keychain work directly in the view**: `reloadHistoryEntries:3085`, `deleteHistoryEntry:3154`, `clearAllHistory:3167`, `chooseHistoryFolder:3064`, `chooseAssistantNoteFolder:2998`, `loadCloudAPIKeyIfNeeded:2910`, `saveCloudSettings:2939`, `testCloudConnection:2961`.
- **Evidence:** `grep -c 'struct .*: View'` → 36; property-wrapper count in main struct → 34.
- **Why it matters:** the most-edited surface (settings/onboarding) is the hardest to read and is essentially **untested at the view layer**; logic that belongs in services is trapped in the view.
- **Affected files:** `Shell/SetupWindowView.swift`.
- **Recommended future action:** split each `private struct …: View` into its own file; extract history/cloud/note logic into services or a view model (the project already proves this pattern works with `AIAssistantSettingsViewModel`).

### H3 — Default test scheme is **not green**: a flaky wall-clock test fails the run
- **Issue:** `xcodebuild test -scheme TypeLessBuddy` (the AGENTS.md-blessed "safe" scheme) reported **`** TEST FAILED **`**. The `.xcresult` shows **471 passed / 7 skipped / 1 failed**. The failure is `ActivationStoreTests/test_successActionResetsDismissTimer()` with: *"The test runner exited with code 0 before finishing running tests."* (a crash/early-exit, then xcodebuild re-ran the suite).
- **Evidence:** `xcrun xcresulttool get test-results summary` (run 2026-06-07 21:47). The test sleeps **~11s of real time** (`Task.sleep` 9.5s + 1.2s + 0.2s, `ActivationStoreTests.swift:964–990`). Tooling flagged "3 longest test runs … exceeding 1.99s." Repo-wide: **123 `Task.sleep` call sites across 6 test files, 5 of them ≥ 1 second.**
- **Why it matters:** a non-deterministic red suite destroys the safety net before any cleanup begins, and makes CI impossible to trust.
- **Affected files:** `TypeLessBuddyTests/ActivationStoreTests.swift` and other timing-dependent suites.
- **Recommended future action:** inject a clock / fake scheduler into `ActivationStore`'s success-dismiss timer so these tests advance virtual time instead of sleeping. This is the **prerequisite** for all later refactoring.

### H4 — Release build is hardened-runtime-signed but ships **no entitlements** for a mic app
- **Issue:** there is **no `.entitlements` file** anywhere and **no `ENABLE_APP_SANDBOX`/`ENABLE_HARDENED_RUNTIME` in `project.pbxproj`**. `scripts/build-dmg.sh:68-73` codesigns with `--options runtime` (hardened) **without `--entitlements`**.
- **Evidence:** `find … -name '*.entitlements'` → none; `build-dmg.sh` codesign block has no `--entitlements`.
- **Why it matters:** non-sandboxed is *correct* here (a global `CGEventTap` in `HotkeyService.swift:456` is incompatible with App Sandbox). But under **hardened runtime**, mic access typically also needs the `com.apple.security.device.audio-input` entitlement; the `Info.plist` usage string only covers the TCC prompt, not the hardened-runtime gate. This may bite only in the notarized release, not in dev.
- **Affected files:** `scripts/build-dmg.sh`, `Info.plist`, project signing settings.
- **Recommended future action:** **verify** mic + accessibility work in a notarized/hardened build; add an entitlements plist if needed. Flagged as uncertain — it may already work; confirm before release.

### H5 — No linter / formatter / CI
- **Issue:** no `.swiftlint.yml`, `.swiftformat`, or `.github/` workflows.
- **Why it matters:** nothing mechanically prevents the next vibecoded session from regrowing god-files or re-fragmenting vocabulary; the flaky suite (H3) would not be caught automatically.
- **Recommended future action:** add SwiftFormat + SwiftLint (with a file-length rule) and a CI job running the unit scheme — **after** H3, or CI starts red.

---

## 5. Refactor opportunities

### High priority
- **Split the two god-files (`SetupWindowView`, `ActivationStore`).**
  - *Problem:* see H1/H2.
  - *Direction:* one file per view struct; extract services/view-models from `ActivationStore` using the existing DI style.
  - *Benefit:* reviewable diffs, view-testable UI, lower regression risk.
  - *Effort:* L (large) — do incrementally, behind the stabilized suite.
- **Unify the AI-feature vocabulary** (see §7 D1).
  - *Problem:* buddy/assistant/rewrite/conversion/LLM all name one feature.
  - *Direction:* pick one user-facing term ("buddy") and one code term ("rewrite" or "assistant"); rename the `Conversion/` folder and types consistently.
  - *Benefit:* drastically lowers cognitive load.
  - *Effort:* M (mechanical rename, but wide).

### Medium priority
- **Lift file/keychain I/O out of `SetupWindowView`** into `HistoryCaptureService` / a cloud-settings view model.
  - *Benefit:* testable settings logic; thinner view. *Effort:* M.
- **Reduce real-`Task.sleep` reliance in tests** (123 sites) via an injectable clock.
  - *Benefit:* fast, deterministic suite. *Effort:* M.
- **Rename files whose name ≠ contents** (see §7 D2): `TriggerTranscriptSplit.swift`→`TriggerTranscriptDetection.swift`, `AIAssistantSettingsView.swift` (primary type is `AIAssistantInlineRowView`), `DictionarySettingsView.swift` (primary type is `ReplacementsSectionView`).
  - *Benefit:* navigability. *Effort:* S.

### Low priority
- **Group the many private `*Metrics` enums / inline styling** into a small design-tokens file. *Effort:* S.
- **Revisit the 12 singletons** — at least make them injectable for tests where they aren't already. *Effort:* M, low payoff (DI is mostly already present).
- **Pin `mlx-swift-lm` to a tagged version** (currently a bare branch revision — see §6). *Effort:* S.

---

## 6. Code that may be removable

> Nothing deleted. Each item lists what to verify first.

- **`generate_icon.swift` (repo root, tracked).** One-off `NSImage` icon generator; **not a member of any target** (not in `project.pbxproj`). *Verify:* the icon is now a committed asset (`AppIcon-1024.png` exists). *Risk:* very low — move to `scripts/` or delete.
- **Legacy migration code/keys.**
  - `ShellPreferences.swift:57` `micDeviceUID` ("legacy — kept for migration only") and `:73` `legacyAllowClipboardAccess`.
  - `WhisperService.deleteLegacyUnsupportedModelFiles()` (called `AppDelegate.swift:70`).
  - *Verify:* whether any installed user base still needs the migration; check how long these have shipped (app is pre-release, `MARKETING_VERSION = 0.1`, "Packaged releases are not published yet" per README — suggests **no install base**, so likely safe). *Risk:* low if truly pre-release.
- **`feature-workflows/` (18 docs) + `feature-map/inter-feature-relationships.md` (1).** Dated **May 4**, predate the June refactors; **0 of 18** reference current core type names (`ActivationStore`/`RecordingState`/`WhisperService`). *Verify:* read 2–3 against current behavior to confirm drift. *Risk:* low (docs only) — but **don't delete blindly**; they may be intentional product-spec prose. Prefer updating or dating them.
- **`build/` (~13 GB, 7 separate DerivedData dirs).** Local only, gitignored — not a repo concern, but `rm -rf build/` locally would reclaim ~13 GB. *Risk:* none (regenerated by build scripts).

**Note:** earlier "unused type" suspicions did **not** hold up — `TriggerTranscriptDetection`, `MicProbeMonitor`, `LiveCalibrationSampleCapturer`, `AIAssistantInlineRowView`, `ReplacementsSectionView` are all referenced. The codebase has little genuine dead code; the real waste is *size and naming*, not orphans.

---

## 7. Domain and consistency review

**D1 — One concept, five names (the biggest consistency problem).** The AI refinement feature is called **buddy** (README/UX, 16 files), **assistant** (15 files), **rewrite** (13), **conversion** (folder `Conversion/` + 13 files), and **LLM** (12). Types mix freely: `LLMRewriteService`, `CloudLLMRewriteService`, `AssistantNoteIntentClassifier`, `ExternalTextSourceClassifier`, `RewriteModelTier`. *Recommend:* one user-facing word ("buddy") + one internal word ("rewrite"); rename `Conversion/`→`Rewrite/`.

**D2 — Filenames that don't match their contents.** `TriggerTranscriptSplit.swift` → defines `TriggerTranscriptDetection`; `AIAssistantSettingsView.swift` → primary view is `AIAssistantInlineRowView`; `DictionarySettingsView.swift` → primary view is `ReplacementsSectionView`. Hurts navigation.

**D3 — UI term leaking into persistence.** `ShellPreferences` ("Shell" = the UI shell folder) lives in `Persistence/` and is the **app-wide settings store** (31 `@Published`, UserDefaults-backed). The name implies UI scope but the role is global. *Recommend:* rename to `AppPreferences`/`UserSettings`, or split per-domain settings.

**D4 — Concepts doing too many jobs.** `ActivationStore` (H1) and `SetupWindowView` (H2) each span ~6–8 responsibilities. `ShellPreferences` is a 31-field settings blob that also caches `activeTriggerProfile`/`activeDictionaryData` from other stores.

**D5 — Inconsistent componentization.** MVVM is used in exactly one place (`AIAssistantSettingsViewModel`, with its own tests) and nowhere else; the rest of settings logic sits inline in the view. Either commit to view-models for settings or don't.

**Consistency that is *good* (keep it):** folder-by-domain layout, protocol + `.live` DI, value-type domain models, `LocalizedError` enums for each subsystem, naming of test files.

---

## 8. Testing and safety review

**Commands run (read-only; reported per the brief):**
- `xcodebuild -list -project TypeLessBuddy.xcodeproj` → 3 targets, schemes `TypeLessBuddy`, `TypeLessBuddyBenchmarks`, `TypeLessBuddyManualUI`. SPM graph resolves cleanly.
- `xcodebuild test -scheme TypeLessBuddy -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData-app-tests` (reused existing derived data). **Result: `** TEST FAILED **`** — `.xcresult`: **471 passed / 7 skipped / 1 failed (479 total)**. The build itself succeeded; multiple `TypeLessBuddy.app` products from 2026-06-05 already exist, confirming the app compiles.
- Static greps: 0 `try!`, 0 `fatalError`, 0 `TODO/FIXME`, 0 `print`, 16 `NSLog`, 12 force-unwraps (all on known-safe constants, e.g. `StatusMenuController.swift:470` `UnicodeScalar(NSCarriageReturnCharacter)!`).

> Did **not** run UI tests (`RUN_UI_TESTS`) or model-integration tests (`RUN_MODEL_INTEGRATION_TESTS`) — they require OS prompts / local model downloads (per `AGENTS.md`: integration tests need macOS permissions; failures there are not necessarily code bugs).

**Coverage impression:** **strong on logic, weak on UI.** 480 unit test methods / 31 files; `ActivationStoreTests` alone = 117 methods / 4,840 lines. Core flows (activation, hotkeys, rewrite, cloud, preferences, audio capture, permissions) are well covered.

**Important untested flows:** the entire `SetupWindowView` view layer (history file management, cloud-config UI, onboarding navigation) — only the extracted `AIAssistantSettingsViewModel` is unit-tested (15 tests). `RecordingPillView` (1,136 lines) has no view tests. UI tests exist but are gated off by default.

**Brittle tests:** the timing suite. **123 `Task.sleep` sites**; `test_successActionResetsDismissTimer` waits ~11s of real time and **flaked this run**. These are slow and non-deterministic.

**Minimum tests/changes needed before cleanup:**
1. **Fix the flaky timer tests** (inject a clock) so the default suite is deterministically green — *blocking prerequisite*.
2. Add a thin **smoke test or characterization tests** around `ActivationStore.finalizeSession` routing outcomes before splitting it.
3. Add **view-model tests** for any logic extracted from `SetupWindowView` (history/cloud) as it moves out of the view.

---

## 9. Cleanup plan

### Phase 1 — Stabilize and understand
- **Goal:** a trustworthy, deterministic green suite + shared mental model.
- **Tasks:** inject a clock/scheduler to kill real-`sleep` timing tests (start with `test_successActionResetsDismissTimer`); run `xcodebuild test -scheme TypeLessBuddy` repeatedly to confirm 0 flakes; add SwiftFormat/SwiftLint config (report-only) + a CI job on the unit scheme; refresh or date the `feature-workflows/` docs against current code.
- **Risks:** timer refactor could change real success-dismiss behavior — guard with tests first.
- **Verification:** `xcodebuild test` green 3× in a row; CI green.

### Phase 2 — Remove obvious waste
- **Goal:** delete low-risk cruft.
- **Tasks:** remove/relocate `generate_icon.swift`; remove legacy migration keys/code (`micDeviceUID`, `legacyAllowClipboardAccess`, `deleteLegacyUnsupportedModelFiles`) **after confirming pre-release/no install base**; rename files whose name ≠ contents (§7 D2); pin `mlx-swift-lm` to a tag.
- **Risks:** legacy removal affects upgraders — verify there are none (README says unreleased).
- **Verification:** build + unit suite green; manual launch unaffected.

### Phase 3 — Fix high-risk architecture problems
- **Goal:** make the two god-files safe to edit.
- **Tasks:** split `SetupWindowView` into one-file-per-view-struct; move history/cloud/note I/O out of the view into services/view-models; begin extracting collaborators from `ActivationStore` (`finalizeSession` first).
- **Risks:** behavior regressions in the central state machine — move in small, test-backed steps.
- **Verification:** unit suite green after each extraction; manual smoke of record→transcribe→rewrite→paste.

### Phase 4 — Refactor domain/state
- **Goal:** coherent domain model and state ownership.
- **Tasks:** unify AI-feature vocabulary (§7 D1), incl. renaming `Conversion/`; rename `ShellPreferences`→`AppPreferences` (or split per-domain); decide and apply one componentization pattern for settings (view-models or none).
- **Risks:** wide renames touch many files + `project.pbxproj` (manually maintained — new/renamed files must be hand-registered).
- **Verification:** full build (pbxproj registration intact); unit suite green.

### Phase 5 — Polish consistency
- **Goal:** uniform style.
- **Tasks:** consolidate `*Metrics`/styling into design tokens; enforce SwiftLint file-length + naming rules as errors; backfill view-layer tests for the split-out views.
- **Risks:** minimal.
- **Verification:** lint clean; suite green; CI enforces going forward.

---

## 10. Final action table

| Priority | Area | Finding | Recommended action | Risk | Effort | Evidence |
|---|---|---|---|---|---|---|
| **P0** | Tests | Default `xcodebuild test` is RED: 471 pass / 7 skip / **1 flaky fail**; ~11s real-sleep test | Inject clock; make suite deterministic before any refactor | Med | M | `.xcresult` summary; `ActivationStoreTests.swift:964–990`; 123 `Task.sleep` sites |
| **P0** | Architecture | `ActivationStore` god object (1,609 lines; `finalizeSession` ~283 lines) | Extract collaborators behind existing DI; split the method | High | L | `ActivationStore.swift:104,541–824` |
| **P0** | Architecture/UI | `SetupWindowView` 4,510 lines, 36 view structs, file+keychain I/O in view | One file per view; lift I/O into services/VMs | High | L | `SetupWindowView.swift` (`reloadHistoryEntries:3085`, `saveCloudSettings:2939`) |
| **P1** | Release | Hardened-runtime signing with no entitlements for a mic app | **Verify** mic/accessibility in notarized build; add entitlements if needed | Med | S | `build-dmg.sh:68-73`; no `.entitlements`; `HotkeyService.swift:456` |
| **P1** | Tooling | No linter/formatter/CI | Add SwiftFormat+SwiftLint+CI (after P0 tests) | Low | M | no `.swiftlint.yml`/`.swiftformat`/`.github` |
| **P1** | Domain | One feature, five names (buddy/assistant/rewrite/conversion/LLM) | Pick one UX + one code term; rename `Conversion/` | Med | M | file-count greps; `Conversion/` types |
| **P2** | Persistence | `ShellPreferences` = 31-field settings blob; UI term in persistence | Rename `AppPreferences`; consider per-domain split | Med | M | `ShellPreferences.swift:48` (31 `@Published`) |
| **P2** | Consistency | Filenames ≠ contained types | Rename 3 files (§7 D2) | Low | S | `TriggerTranscriptSplit.swift`, `AIAssistantSettingsView.swift`, `DictionarySettingsView.swift` |
| **P2** | Tests | UI/view layer untested; settings logic only partly extracted | Add VM tests as logic moves out of `SetupWindowView` | Low | M | only `AIAssistantSettingsViewModelTests` exists |
| **P3** | Waste | `generate_icon.swift` not in any target; legacy keys; ~13 GB `build/`; stale-looking design docs | Remove/relocate after verify; clean derived data locally | Low | S | not in `project.pbxproj`; `ShellPreferences.swift:57,73`; `feature-workflows/*` (May 4) |
| **P3** | Deps | `mlx-swift-lm` pinned to bare branch revision (no semver) | Pin to a tagged release | Low | S | `Package.resolved` (no `version` for `mlx-swift-lm`) |

---

### Uncertainty flags
- **H4 (entitlements):** I could not run a notarized build; mic-under-hardened-runtime may already work. Treat as *verify*, not *confirmed broken*.
- **§6 legacy/docs removals:** "pre-release, no install base" is inferred from README + `MARKETING_VERSION 0.1`; confirm before deleting migration code.
- **Flaky test:** failed once this run and the suite passed on xcodebuild's automatic re-run — it is non-deterministic, not a hard failure. Severity is "erodes trust / blocks CI," not "feature broken."
