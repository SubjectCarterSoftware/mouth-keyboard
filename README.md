# TypeLessBuddy

Just direct speech transcription and refinement. Nothing else.

TypeLessBuddy is a local-first macOS voice writing app. It can give you the raw transcript when that's all you need, or use the built in ai buddy to turn what you said into finished writing you can actually send.

![TypeLessBuddy recording pill](assets/Pill_recording_state.png)

## What It Does

- Seamless dictation anywhere
- Provides a built-in AI buddy for additional refinement when needed
- Always copies to your clipboard or auto-pastes 

## Exampleß

Simple mode: just speak it'll transcribe then paste
Buddy mode: Just say "buddy" anywhere in your message, and it will be passed to your buddy for processing.

## Installation

Once packaged releases are available, installation is simple:

1. Download `TypeLessBuddy.dmg` from GitHub Releases.
2. Open the disk image.
3. Drag `TypeLessBuddy.app` into `Applications`.
4. Open it from `Applications`.

To build that installer locally, run:

```bash
./scripts/build-dmg.sh
```

That produces:

- `dist/TypeLessBuddy.app`
- `dist/TypeLessBuddy.dmg`

If you want to distribute the app publicly on the internet, you should also sign and notarize the DMG. The release steps are documented in [docs/RELEASING.md](/Users/elicarter/Workspace/TypeLessBuddy/docs/RELEASING.md).

Do not commit the generated `.app` or `.dmg` into the repository. Keep source, docs, screenshots, and release scripts in Git, then upload the built DMG to GitHub Releases for each version.

Packaged releases are not published yet.

## Requirements

- macOS 14 or later
- Microphone permission
- Input Monitoring for the trigger
- Accessibility permission for auto-paste

## Privacy

- Audio is recorded and transcribed locally
- No cloud request is made unless you explicitly enable cloud conversion
- If cloud conversion is enabled, only transcript text is sent directly to you selected provider

## Limitations

- macOS only
- First use after a model download or model switch can be slower
- Auto-paste depends on system permissions and target app behavior
- Cloud conversion changes the privacy model

## License

[MIT](LICENSE)
