# Contributing

Thanks for considering a contribution to TypeLessBuddy.

## Setup

Requirements:

- macOS 14 or later
- Xcode with macOS app development support
- Swift Package Manager access to the dependencies pinned in `Package.resolved`

Clone the repository, open `TypeLessBuddy.xcodeproj`, and use the shared
`TypeLessBuddy` scheme for normal development.

## Signing

The repository uses `Config/Signing.xcconfig` for shared signing defaults. If
you need a personal Apple Developer Team ID, create this ignored local file:

```xcconfig
// Config/Signing.local.xcconfig
DEVELOPMENT_TEAM = YOURTEAMID
```

Do not commit local signing files, certificates, provisioning profiles, or
export options.

## Build

Use the repository build script:

```bash
./scripts/build-app.sh
```

The debug app is written to:

```text
build/DerivedData-app/Build/Products/Debug/TypeLessBuddy.app
```

Build products under `build/` and release artifacts under `dist/` are local
artifacts and should not be committed.

## Tests

Run the normal unit suite with the `TypeLessBuddy` scheme:

```bash
xcodebuild test -scheme TypeLessBuddy
```

The default scheme runs `TypeLessBuddyTests` only. It is dependency-injected and
does not trigger microphone, accessibility, or automation OS prompts.

Do not run UI tests as part of normal development or CI. They launch the real
app and may require approving OS prompts. Run them only at a machine where you
can approve prompts, using the `TypeLessBuddyManualUI` scheme.

Real model integration tests are slow and require local model assets. They skip
unless `RUN_MODEL_INTEGRATION_TESTS=1` is set.

## Pull Requests

Before opening a pull request:

- Run the focused tests for the code you changed.
- Update docs when behavior, setup, permissions, or privacy behavior changes.
- Keep generated build output, local models, secrets, and signing files out of
  the diff.
- Note any manual testing that could not be automated, especially permission,
  microphone, clipboard, or accessibility flows.
