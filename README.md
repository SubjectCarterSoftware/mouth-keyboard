# Speech2Text

A lightweight, privacy-first macOS menu bar app that turns your voice into clipboard text. Use toggle hotkeys or hold a configurable key (default: `Right Option`) to capture speech, then paste or reuse the result anywhere.

**No cloud. No subscription. No data leaves your Mac.**

Speech2Text runs [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (OpenAI's Whisper model) entirely on-device with Metal GPU acceleration. Transcription happens in seconds, and your audio never touches a server.

## Features

- 🎙️ **Flexible activation** — Ctrl+V to start/stop recording, Ctrl+Shift+V to cancel, or hold a configurable key (default: `Right Option`) to record until release
- ⚡ **Fast** — Metal GPU acceleration + the tiny.en model = sub-second transcription
- 🔒 **Private** — 100% on-device, no network requests, no telemetry
- 🖥️ **Native macOS** — SwiftUI menu bar app, ~5MB total, minimal resource usage
- 🎯 **Simple** — Records → transcribes → copies to clipboard. That's it.

## How It Works

1. Press **Ctrl+V** or hold **Right Option** — recording starts, and a floating pill shows mic levels
2. Speak naturally
3. Press **Ctrl+V** again or release **Right Option** — recording stops and Whisper transcribes the captured audio
4. Text is automatically copied to your clipboard
5. Paste anywhere with **⌘V**

Press **Ctrl+Shift+V** at any time to cancel and discard the recording.

## Requirements

- macOS 14.0 (Sonoma) or later
- Microphone permission
- Input Monitoring permission for **Hold to Transcribe**
- Accessibility permission for **Auto Paste**

## Installation

### Download
Grab the latest `.app` from [Releases](../../releases) and drag it to your Applications folder.

### Build from Source
```bash
git clone https://github.com/YOUR_USERNAME/speech2text.git
cd speech2text
open Speech2Text.xcodeproj
```
Build and run with Xcode 16+. The Whisper model (`ggml-tiny.en.bin`) is bundled in the project.

## Configuration

Click the menu bar icon → **Settings…** to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Activation Hotkey | Ctrl+V | Start/finish recording |
| Cancellation Hotkey | Ctrl+Shift+V | Cancel and discard |
| Hold to Transcribe | Configurable (default: Right ⌥) | Press and hold to record, then release to transcribe |
| Always Auto Paste | On | Paste after any successful finish, including hold-to-transcribe and AI-converted output |
| Microphone | System Default | Choose a specific input device |
| Activation Sound | Off | Play a sound when recording starts |
| Recording Indicator | On | Show the floating pill during recording |

## Tech Stack

- **Swift + SwiftUI** — Native macOS, menu bar app
- **whisper.cpp** — On-device speech recognition via [whisper.spm](https://github.com/ggerganov/whisper.spm)
- **KeyboardShortcuts** — Global hotkeys via [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- **Metal** — GPU-accelerated inference with flash attention

## Privacy

Speech2Text makes **zero network requests**. Your audio is processed entirely on your Mac using the bundled Whisper model. No data is collected, stored, or transmitted. The app has no analytics, no crash reporting, and no update checks.

## License

[MIT](LICENSE) — do whatever you want with it.
