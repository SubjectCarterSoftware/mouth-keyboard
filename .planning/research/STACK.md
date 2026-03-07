# Stack Research

**Domain:** macOS system-wide clipboard-first dictation utility
**Researched:** 2026-03-05
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift + AppKit/SwiftUI | Swift 6.x, macOS 14+ target | Native macOS app shell, menu bar UI, settings, overlays | Lowest-friction way to ship a fast background utility that feels native, handles permissions cleanly, and avoids the startup/IPC overhead of web wrappers |
| AVFAudio / AVFoundation (`AVAudioEngine`, `AVAudioNode`) | System framework | Microphone capture, tap-based buffering, device routing | Apple’s supported path for low-latency live microphone capture; it fits both streaming transcription and queued segment capture |
| `whisper.cpp` | v1.8.3 | Primary local-first speech recognition engine | Mature offline ASR stack with Apple Silicon optimization through Metal and optional Core ML acceleration; strong fit for privacy-first, no-network dictation |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `KeyboardShortcuts` | 2.4.0 | User-customizable global activation hotkey | Use for the main idle-state activation shortcut; it is sandboxed, Mac App Store compatible, and removes custom preference UI work |
| `Defaults` | 9.0.6 | Typed persistence for settings and small app state | Use if you want strongly typed storage for hotkey mode, engine selection, microphone choice, and indicator visibility without writing boilerplate wrappers over `UserDefaults` |
| Speech framework (`SpeechAnalyzer`, `SpeechTranscriber`, `SpeechDetector`) | macOS 26 SDK | Optional Apple-native fallback / benchmark path | Use as a benchmark or optional engine abstraction when you want to compare Apple’s built-in speech stack against Whisper-based results or use Apple-provided VAD/transcription assets |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Instruments | Startup, audio, and transcription latency profiling | Treat hotkey-to-record and finish-to-clipboard as first-class traces, not vague “feels fast” checks |
| Accessibility Inspector + System Settings privacy panes | Validate permission flow and event capture behavior | Required to test Accessibility and Input Monitoring paths cleanly across fresh installs |
| Audio MIDI Setup | Verify microphone device changes and sample-rate edge cases | Useful for reproducing external mic, aggregate device, and sample-format mismatches |

## Installation

```bash
# Add Swift packages in Xcode / Swift Package Manager
# - https://github.com/sindresorhus/KeyboardShortcuts @ 2.4.0
# - https://github.com/sindresorhus/Defaults @ 9.0.6

# Resolve package dependencies
xcodebuild -resolvePackageDependencies

# Vendor whisper.cpp and build with Core ML acceleration enabled
git submodule add https://github.com/ggml-org/whisper.cpp vendor/whisper.cpp
cmake -B vendor/whisper.cpp/build -DWHISPER_COREML=1
cmake --build vendor/whisper.cpp/build --config Release -j
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `whisper.cpp` v1.8.3 | Apple Speech framework | Use Apple Speech first if you decide to require very new macOS versions and want tighter system integration over model portability |
| Swift + AppKit/SwiftUI | Tauri / Electron | Only use a web wrapper if your product expands into a much larger cross-platform desktop app where startup latency is less critical |
| `KeyboardShortcuts` for activation | Raw Carbon `RegisterEventHotKey` | Use Carbon directly if you want zero package dependencies and are willing to own recorder UI, collision detection, and storage yourself |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Electron or Tauri for v1 | Adds startup and IPC overhead, complicates macOS permission flow, and weakens the “instant background utility” goal | Native Swift app shell |
| Python-hosted `mlx-whisper` as the primary shipping runtime | Great for prototyping, but Python process startup, packaging, and environment management work against sub-second interaction goals | Embedded `whisper.cpp` or Apple Speech as a native engine |
| `NSEvent.addGlobalMonitorForEvents` as the core hotkey/session key strategy | Apple documents that global key monitoring depends on accessibility trust and cannot modify or suppress delivery; it is the wrong primitive for deterministic capture controls | Use a dedicated hotkey mechanism for activation and a scoped `CGEventTap` / input-access path for background session controls |
| Direct key-event insertion into the active app | Makes the product brittle across secure fields, browsers, Electron apps, and IME-heavy contexts | Clipboard-first output boundary |

## Stack Patterns by Variant

**If targeting the broadest practical modern macOS range:**
- Use `whisper.cpp` for primary transcription
- Use `KeyboardShortcuts` for activation and native frameworks for everything else
- Because the product stays local-first without depending on very recent Speech framework behavior

**If targeting only newer Apple OS releases and you want tight system integration:**
- Prototype an alternative engine adapter around `SpeechAnalyzer` / `SpeechTranscriber`
- Use Apple-managed speech assets and `SpeechDetector` for VAD experiments
- Because the Speech framework now exposes more modern transcription modules, but rollout flexibility is narrower

**If the app is M-series only and internal-use only:**
- Benchmark MLX Whisper as a research branch, not the main shipping path
- Because MLX can be competitive on Apple Silicon, but it is less natural to embed as a polished native macOS app runtime

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Swift 6.x app target | macOS 14+ | Good baseline for a modern menu bar utility without dragging legacy deployment constraints into v1 |
| `KeyboardShortcuts` 2.4.0 | macOS 10.15+ | More permissive than the proposed app target, so it is not the limiting dependency |
| `Defaults` 9.0.6 | macOS 11+ | Safe within a macOS 14+ baseline |
| `whisper.cpp` 1.8.3 | Apple Silicon + Metal/Core ML optional | Strongest fit on Apple Silicon; Intel can work, but performance targets become harder |
| Speech framework modern modules | macOS 26 SDK path | Treat as optional until implementation-phase research confirms deployment and asset behavior for this product |

## Sources

- Apple Developer Documentation, `Speech` framework overview — https://developer.apple.com/documentation/speech
- Apple Developer Documentation, `Recognizing speech in live audio` — https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio
- Apple Developer Documentation, `AVAudioNode` — https://developer.apple.com/documentation/avfaudio/avaudionode
- Apple Developer Documentation, `NSPasteboard.general` — https://developer.apple.com/documentation/appkit/nspasteboard/general
- Apple Documentation Archive, `Monitoring Events` — https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html
- Apple Developer Forums, DTS answer on `CGEventTap`, `CGPreflightListenEventAccess`, and `CGRequestListenEventAccess` — https://developer.apple.com/forums/thread/707680
- `KeyboardShortcuts` repository and tags — https://github.com/sindresorhus/KeyboardShortcuts and https://github.com/sindresorhus/KeyboardShortcuts/tags
- `Defaults` repository — https://github.com/sindresorhus/Defaults
- `whisper.cpp` repository and tags — https://github.com/ggml-org/whisper.cpp and https://github.com/ggml-org/whisper.cpp/tags
- MLX Whisper example — https://github.com/ml-explore/mlx-examples/tree/main/whisper

---
*Stack research for: macOS system-wide clipboard-first dictation utility*
*Researched: 2026-03-05*
