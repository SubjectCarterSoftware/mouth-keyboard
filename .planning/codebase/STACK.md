# Technology Stack

**Analysis Date:** 2026-03-22

## Languages

**Primary:**
- Swift 5.0 - All application logic, UI, services, and tests
- Objective-C - Single bridging utility (`Speech2Text/Audio/ObjCExceptionCatcher.m`) for catching `NSException` thrown by AVAudioEngine calls that cannot be caught in Swift

**Secondary:**
- None

## Runtime

**Environment:**
- macOS 14.0+ (Sonoma) minimum deployment target
- macOS only — no iOS/tvOS/watchOS targets
- arm64 architecture (production build target per `build.sh`)

**Package Manager:**
- Swift Package Manager (SPM) — integrated via Xcode
- Lockfile: `Speech2Text.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (present and committed)

## Frameworks

**Core (Apple):**
- SwiftUI — menu bar UI, settings window (via `NSHostingController`), recording pill views
- AppKit — `NSApplication`, `NSWindow`, `NSStatusItem`, `NSPasteboard`, menu bar extra
- AVFoundation — `AVAudioEngine`, `AVAudioInputNode`, `AVAudioPCMBuffer` for real-time audio capture
- Combine — reactive bindings between `@Published` properties and UI/services
- CoreAudio — low-level audio device enumeration and disconnect listener registration
- CoreGraphics — `CGEvent` for simulated ⌘V paste injection
- Foundation — `UserDefaults`, `FileManager`, `JSONEncoder`/`JSONDecoder`, `Codable`, `ProcessInfo`
- ServiceManagement — `SMAppService.mainApp` for launch-at-login registration
- Accelerate — used by audio processing pipeline (imported in audio layer)
- AudioToolbox — system sound playback (Tink/Glass/Basso aiff files)

**Testing:**
- XCTest — all unit and UI tests inherit from `XCTestCase`
- No Swift Testing (`@Test`/`@Suite`) — exclusively XCTest

**Build:**
- xcodebuild — required build tool; `swift build` must NOT be used (Metal shaders for MLX GPU inference are compiled only by xcodebuild)
- Xcode project: `Speech2Text.xcodeproj`, scheme `Speech2Text`

## Key Dependencies (Swift Packages)

**Critical (direct):**
- `WhisperKit` 0.17.0 — on-device speech-to-text transcription via OpenAI Whisper models; GitHub: `argmaxinc/WhisperKit`
- `mlx-swift-lm` 2.30.6 — on-device LLM inference via Apple MLX framework; provides `MLXLLM`, `MLXLMCommon`; GitHub: `ml-explore/mlx-swift-lm`
- `KeyboardShortcuts` 1.17.0 — Carbon hot key registration (no Accessibility permission required); GitHub: `sindresorhus/KeyboardShortcuts`

**Transitive (resolved):**
- `mlx-swift` 0.30.6 — Metal/GPU tensor computation backend for mlx-swift-lm
- `swift-transformers` 1.1.9 — HuggingFace tokenizer support for LLM inference; provides `Hub` module
- `swift-jinja` 2.3.2 — Jinja2 template rendering (chat templates for LLM prompts)
- `swift-collections` 1.4.0 — extended collection types
- `swift-numerics` 1.1.1 — numeric protocol extensions
- `swift-crypto` 4.3.0 — cryptographic operations
- `swift-asn1` 1.6.0 — ASN.1 parsing
- `swift-argument-parser` 1.7.0 — CLI argument parsing (used by swift-transformers example target)
- `yyjson` 0.12.0 — fast JSON parsing (C library, used by swift-transformers)

## Configuration

**User Preferences:**
- Stored via `UserDefaults` with suite name `com.elicarter.Speech2Text.shell`
- Managed by `Speech2Text/Persistence/ShellPreferences.swift` — `@MainActor` `ObservableObject`
- UI testing uses isolated suite `com.elicarter.Speech2Text.shell.ui-tests`
- Reset via `-reset-shell-preferences` launch argument

**Persisted Settings:**
- Whisper model choice (`base.en`, `small.en`, `medium.en`, `large-v3-turbo`)
- Rewrite model tier (`qwen3-1.7b`, `qwen3-4b`, `qwen3-8b`)
- Thinking mode enabled flag
- Microphone device UID
- Active trigger profile (stored as JSON in Application Support)
- Convert modes (built-in + user-defined)
- Launch-at-login (via `SMAppService`)

**Model Storage:**
- WhisperKit models: stored in WhisperKit's default cache location
- LLM rewrite models: stored in `~/Library/Application Support/Speech2Text/RewriteModel/` (HuggingFace Hub download base)
- Trigger profile: `~/Library/Application Support/Speech2Text/TriggerProfileStore.json`
- User intent entries: `~/Library/Application Support/Speech2Text/UserIntentStore.json`

**Build:**
- Build config: `Speech2Text.xcodeproj`
- Build script: `build.sh` (wraps xcodebuild for Release, arm64, macOS)
- No `.env` files — no server-side secrets required (fully on-device)
- Bundle ID: `com.elicarter.Speech2Text`
- App version: `0.1` (marketing), build `1`

## Platform Requirements

**Development:**
- macOS with Xcode (xcodebuild required — not `swift build`)
- arm64 Mac strongly recommended (MLX GPU inference requires Apple Silicon Metal shaders)
- Resolve packages: `xcodebuild -project Speech2Text.xcodeproj -resolvePackageDependencies`

**Production:**
- macOS 14.0+ (Sonoma)
- arm64 (Apple Silicon) — MLX Metal GPU inference requires Apple Silicon; Intel Macs will fall back to CPU only
- No network required at runtime for transcription (models downloaded once to Application Support)
- Network required only on first launch or model tier change (Hugging Face model download)

---

*Stack analysis: 2026-03-22*
