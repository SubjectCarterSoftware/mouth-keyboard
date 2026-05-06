# TypeLessBuddy

Just direct speech transcription and refinement. Nothing else.

TypeLessBuddy is a local-first macOS voice writing app. It can give you the raw transcript when that's all you need, or use the built in ai buddy to turn what you said into finished writing you can actually send.

## What It Does

- Seamless dictation anywhere
- Provides a built-in AI buddy for additional refinement when needed
- Always copies to your clipboard or auto-pastes 

## Exampleß

Simple mode: just speak it'll transcribe then paste
Buddy mode: Just say "buddy" anywhere in your message, and it will be passed to your buddy for processing.

## Installation

Once packaged releases are available, installation is simple:

1. Download `TypeLessBuddy.app`.
2. Drag it into `Applications`.
3. Open it.

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
