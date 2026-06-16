# Releasing TypeLessBuddy

## Build A Drag-To-Applications DMG

Run:

```bash
chmod +x scripts/build-dmg.sh
./scripts/build-dmg.sh
```

That script does four things:

1. Builds the Release app bundle with Xcode.
2. Copies `TypeLessBuddy.app` into a staging folder.
3. Adds an `Applications` shortcut beside it.
4. Wraps that layout in `dist/TypeLessBuddy.dmg`.

The result is the normal macOS install flow where the disk image opens and shows:

- `TypeLessBuddy.app`
- `Applications`

The user drags the app onto the Applications shortcut.

## Output Paths

- App bundle: `dist/TypeLessBuddy.app`
- Disk image: `dist/TypeLessBuddy.dmg`

These are local build artifacts only. They should not be committed into Git.

## Recommended GitHub Distribution Flow

1. Commit source code, docs, screenshots, and release scripts.
2. Build `dist/TypeLessBuddy.dmg` locally (signed + notarized — see "Internet Distribution" below).
3. Create a GitHub Release such as `v0.1.0`.
4. Upload the DMG as a release asset, keeping the asset name exactly `TypeLessBuddy.dmg`.
5. The README download button and install link already point at the stable "latest" URL:

   ```text
   https://github.com/subjectCarterSoftware/typelessbuddy/releases/latest/download/TypeLessBuddy.dmg
   ```

   This always resolves to the newest release's `TypeLessBuddy.dmg`, so it never needs
   updating per release — as long as the uploaded asset keeps that exact name.

You can publish a release from the command line with the GitHub CLI:

```bash
gh release create v0.1.0 dist/TypeLessBuddy.dmg \
  --title "v0.1.0" \
  --notes "First public release."
```

Recommended repo contents:

- Source code
- `README.md`
- `docs/RELEASING.md`
- `scripts/build-dmg.sh`
- Screenshots and other lightweight assets

Do not store these in the repo:

- `dist/TypeLessBuddy.dmg`
- `dist/TypeLessBuddy.app`
- Temporary build output

## Internet Distribution

For local testing, an unsigned DMG is enough.

For a real public download, you should also:

1. Sign the app with a `Developer ID Application` certificate.
2. Sign the DMG.
3. Notarize the DMG with Apple.
4. Staple the notarization ticket.

The script supports that if you export these environment variables first:

```bash
export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
./scripts/build-dmg.sh
```

If those variables are unset, the script still builds the DMG, but it will not be suitable for a polished public release.

For local Apple Developer Team configuration, put personal signing settings in
`Config/Signing.local.xcconfig`. That file is ignored by Git.
