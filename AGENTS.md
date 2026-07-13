# AGENTS.md

> **Project rename (2026-07-13):** This app was previously called
> **TypeLessBuddy** — same tool, new name. Display name: "Mouth Keyboard";
> code/target/scheme/module: `MouthKeyboard`; bundle ID:
> `com.elicarter.MouthKeyboard`; repo slug: `SubjectCarterSoftware/mouth-keyboard`.
> Any reference to TypeLessBuddy in old issues, branches, chat history, notes,
> or `~/Library/Application Support/TypeLessBuddy` refers to this project.
> Full record: [docs/RENAME.md](docs/RENAME.md).

Whenever you need to run a build, use the repository build script: `scripts/build-app.sh`.

## Running tests

Use the **`MouthKeyboard`** scheme for normal test runs (Cmd+U or
`xcodebuild test -scheme MouthKeyboard`). It runs only the unit suite
(`MouthKeyboardTests`), which is fully dependency-injected and **never triggers
microphone, accessibility, or automation OS prompts**. This is the default and
what CI should use.

### Tests that launch the real app (need manual approval)

The UI tests (`PermissionRecoveryFlowTests`, `MenuBarShellSmokeTests`) launch
the real app. Running them requires approving OS prompts — the XCUITest runner's
one-time "enable automation mode" prompt, and potentially mic/accessibility.

- **Don't** run them as part of normal/CI test runs.
- They are gated behind `RUN_UI_TESTS=1` and skip otherwise, so the default
  scheme can never trigger them by accident.
- **Run them only when you are at the machine to approve the prompts**, by
  selecting the **`MouthKeyboardManualUI`** scheme (it sets `RUN_UI_TESTS=1`).

### Real-model integration tests (slow, need local models)

`LLMRewriteServiceIntegrationTests` and `RealModelIntegrationTests` load real
MLX models and are slow (minutes). They skip unless `RUN_MODEL_INTEGRATION_TESTS=1`.
Run them when validating the actual model-loading / inference path, not in the
default suite.

## Build output

The `build/` directory (gitignored) is the one fixed local location for build
products and DerivedData — kept on purpose so builds don't scatter across
default DerivedData paths. It can grow large and is safe to delete anytime; it
regenerates on the next build.
