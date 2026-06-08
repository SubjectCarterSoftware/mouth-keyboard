# Phase 4a (vocabulary) + Phase 3 (split) — implementation plan

Domain language is unified **first** so the structural split lands on clean,
consistent concepts (and we never rename a file twice). Phase 4a is **symbol
renames only** — no file/folder moves, no `project.pbxproj` changes. File and
folder renames (incl. `Conversion/` → `Rewrite/`) fold into Phase 3 so the
hand-maintained pbxproj churns exactly once.

Safety net throughout: the 480-test unit suite + CI. Run after every chunk;
behavior-preserving only.

## Locked vocabulary (decided)

- **Operation** (transcript → finished text) = **`rewrite`** everywhere, including
  user-facing copy and state:
  - `RecordingState.converting` → `.rewriting`; pill "Converting…" → "Rewriting…"
  - success field `converted: Bool` → `rewritten: Bool`
  - `lastConvertedTranscription` → `lastRewrittenTranscription`
  - `conversionModel*` / `canManageConversionModels` → `rewriteModel*`
  - `minimumConvertingDisplayDuration`, `convertingStartedAt`, `onConvertingStarted`,
    `shouldConvert`, `conversionError`/`conversionFailed` → `rewrite…` equivalents
- **Engine / provider (Option A)** — strip redundant `LLM` from the *operation*
  types, keep it on the *provider* types:
  - `LLMRewriting` → `Rewriting`
  - `LLMRewriteService` (local MLX) → `LocalRewriteService`
  - `CloudLLMRewriteService` → `CloudRewriteService`
  - `LLMRewriteError` → `RewriteError`
  - **keep**: `CloudLLMProvider`, `CloudLLMConfig`, `CloudLLMKeychain`, `cloudLLMConfig`
- **Keep as-is**: `assistant` (feature/persona code term), `"Buddy"` (default persona
  name + brand), and already-correct `RewriteModelTier` / `rewriteSystemPromptPrefix` /
  `makeRewriteInstructions` / etc.
- **Never touch**: Audio `convertToWhisperFormat` / `AVAudioConverter` / `converter`
  — that's PCM→Whisper format conversion, unrelated to the rewrite operation.

## Phase 4a — vocabulary renames (symbols only)

Order matters for substring safety (rename longer/containing identifiers first).

1. **Engine types** (contained, ~93 refs): `CloudLLMRewriteService` → `CloudRewriteService`
   first, then `LLMRewriteService` → `LocalRewriteService`, then `LLMRewriteError` →
   `RewriteError`, then `LLMRewriting` → `Rewriting`. Build + test. Commit.
2. **Operation cluster**: the conversion/converting/converted → rewrite/rewriting/
   rewritten renames above, excluding Audio. Watch the `converted` success-field
   rename for clashes with the existing local `let rewritten` in `finalizeSession`.
   Build + test (+ manual pill check for the "Rewriting…" label). Commit.

Files stay named as-is during 4a (e.g. `LLMRewriteService.swift` keeps its filename;
class inside becomes `LocalRewriteService`). Filenames are reconciled in Phase 3.

## Phase 3 — split the god-files (done == SwiftLint *errors* cleared)

Target the 4 production lint errors; leave warnings. Group cohesively (~8 new files).

- **`ActivationStore.swift`**: break `finalizeSession` into named private steps;
  split the class across extension files (`+Pipeline`, `+Models`, `+Notes`); move
  `ActivationSoundPlayer`/`Sleeping` to a support file.
- **`SetupWindowView.swift`**: move the ~30 self-contained component structs into
  ~4 files (recorders, settings components, onboarding, history views); lift cloud
  + history I/O out of the view into a view model / `HistoryCaptureService`; add
  view-model tests for the extracted logic.
- Fold file renames here: `LLMRewriteService.swift` → `LocalRewriteService.swift`,
  rename `Conversion/` → `Rewrite/`, etc. — the single pbxproj-churn step.

Verify: unit suite + CI green per file; manual app run for the settings/onboarding
and pill changes.

## Out of scope (deliberately)

Warning-level files (`RecordingPillView`, `ShellPreferences`, the long test files)
unless a feature touches them. No maximal decomposition.
