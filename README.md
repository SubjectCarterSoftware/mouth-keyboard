# Mouth Keyboard

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/SubjectCarterSoftware/mouth-keyboard/actions/workflows/ci.yml/badge.svg)](https://github.com/SubjectCarterSoftware/mouth-keyboard/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/SubjectCarterSoftware/mouth-keyboard?display_name=tag)](https://github.com/SubjectCarterSoftware/mouth-keyboard/releases/latest)
[![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#requirements)

Local-first voice writing with a built-in buddy for macOS.

Mouth Keyboard turns speech into text anywhere on your Mac. Use it as plain dictation when you want a raw transcript, or say "buddy" to route the transcript through the built-in assistant for cleanup and rewriting.

## Demo

[![Watch the Mouth Keyboard demo on YouTube](https://img.youtube.com/vi/mV1iYwyAS8I/maxresdefault.jpg)](https://youtu.be/mV1iYwyAS8I)

<p align="center">
  <a href="https://github.com/SubjectCarterSoftware/mouth-keyboard/releases/latest/download/MouthKeyboard.dmg">
    <img src="https://img.shields.io/badge/Download-MouthKeyboard.dmg-2ea44f?style=for-the-badge&logo=apple&logoColor=white" alt="Download MouthKeyboard.dmg">
  </a>
</p>

<p align="center">
  <img src="assets/Pill_recording_state.png" alt="Mouth Keyboard recording pill" width="228">
</p>

## Features

- Local Whisper models for transcription
- Local LLMs for assistant actions
- Context pass-through from copied text, selected text, and the last transcript
- Local history tracking
- Note saving
- Custom vocabulary packs
- Word replacements
- Preferred microphone selection

## Install

1. Download `MouthKeyboard.dmg` from the [latest release](https://github.com/SubjectCarterSoftware/mouth-keyboard/releases/latest).
2. Open the disk image.
3. Drag `MouthKeyboard.app` into `Applications`.
4. Launch Mouth Keyboard from `Applications`.

macOS will ask for Microphone permission on first use. Enable Accessibility permission if you want Mouth Keyboard to auto-paste into other apps.

## Usage

Use your shortcut, speak, and release. Mouth Keyboard transcribes locally and sends the result to your clipboard or active app.

Say "buddy" anywhere in the message when you want the assistant to rewrite or refine the transcript before output.

## Privacy

- Audio is captured only while you are recording.
- Transcription runs locally on your Mac.
- Cloud requests are never made unless you enable a cloud rewrite provider.
- Cloud API keys are stored in the macOS Keychain.

See [PRIVACY.md](PRIVACY.md) for details.

## Requirements

- macOS 14 or later
- Microphone permission
- Accessibility permission for auto-paste

## Build From Source

Build the debug app:

```bash
./scripts/build-app.sh
```

Build the local DMG installer:

```bash
./scripts/build-dmg.sh
```

The DMG is written to `dist/MouthKeyboard.dmg`. Release packaging and notarization notes are in [docs/RELEASING.md](docs/RELEASING.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, signing, build, and test guidance.

## License

[MIT](LICENSE)
