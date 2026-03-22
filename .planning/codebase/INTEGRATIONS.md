# External Integrations

**Analysis Date:** 2026-03-22

## APIs & External Services

**On-Device AI — Speech Transcription:**
- WhisperKit (argmaxinc) — runs OpenAI Whisper models locally on-device for speech-to-text
  - SDK: `WhisperKit` SPM package (0.17.0)
  - Auth: None — fully local inference
  - Models downloaded from WhisperKit's model hub on first `prepare()` call
  - Available models: `base.en`, `small.en`, `medium.en`, `large-v3-turbo`
  - Entry point: `Speech2Text/Transcription/WhisperService.swift`

**On-Device AI — Text Rewriting:**
- MLX LLM (Apple ml-explore) — runs Qwen3 LLMs locally on Apple Silicon GPU via Metal
  - SDK: `mlx-swift-lm` SPM package (2.30.6), provides `MLXLLM` and `MLXLMCommon`
  - Auth: None — fully local inference
  - Entry point: `Speech2Text/Conversion/LLMRewriteService.swift`
  - Model tier enum: `Speech2Text/Conversion/RewriteModelTier.swift`

**Model Distribution — Hugging Face Hub:**
- Models are downloaded via `swift-transformers` `HubApi` from `huggingface.co`
  - SDK: `swift-transformers` SPM (1.1.9), `Hub` module
  - Auth: None (public models, no token required)
  - Download base: `~/Library/Application Support/Speech2Text/RewriteModel/`
  - Hugging Face slugs:
    - Default (1.7B): `mlx-community/Qwen3-1.7B-4bit`
    - Standard (4B): `mlx-community/Qwen3-4B-4bit`
    - High (8B): `mlx-community/Qwen3-8B-4bit`
  - Download triggered at launch and on tier change via `RewriteModelLoadState.shared.startDownload(for:)` in `Speech2Text/App/AppDelegate.swift`

## Data Storage

**Databases:**
- None — no SQL, Core Data, or embedded database

**User Defaults (preferences):**
- `UserDefaults` suite name: `com.elicarter.Speech2Text.shell`
- Managed by: `Speech2Text/Persistence/ShellPreferences.swift`
- Stores: setup completion flag, permission request flags, mic device UID, Whisper model choice, rewrite tier, thinking mode, convert modes

**File-based JSON stores (Application Support):**
- Trigger profile store: `~/Library/Application Support/Speech2Text/TriggerProfileStore.json`
  - Managed by: `Speech2Text/Activation/TriggerProfileStore.swift`
  - Format: `StoredTriggerProfiles` (`Codable` struct), with legacy `TriggerProfile` fallback
- User intent store: `~/Library/Application Support/Speech2Text/UserIntentStore.json`
  - Managed by: `Speech2Text/Conversion/UserIntentStore.swift`
  - Format: `[UserIntentEntry]` array (`Codable`)
- LLM model cache: `~/Library/Application Support/Speech2Text/RewriteModel/` (binary model files, downloaded by HubApi)

**File Storage:**
- Local Application Support only — no cloud storage, no S3, no iCloud

**Caching:**
- In-memory model caching: `LLMRewriteService.cachedModel` (actor-isolated)
- In-memory WhisperKit pipeline: `WhisperService.pipe` (actor-isolated)
- No external cache service (Redis, Memcached, etc.)

## Authentication & Identity

**Auth Provider:**
- None — the app has no user accounts, no sign-in, no cloud backend
- All processing is local and private

**macOS System Permissions (not auth, but required capabilities):**
- Microphone: `NSMicrophoneUsageDescription` in `Speech2Text/Info.plist` — audio capture via AVFoundation
- Accessibility (keyboard monitoring): `NSAccessibilityUsageDescription` in `Speech2Text/Info.plist` — used for CGEventTap-based paste injection; keyboard shortcut listening uses Carbon hot keys (no Accessibility required)
- Post-event (synthetic input): required for `PasteService` (`Speech2Text/Clipboard/PasteService.swift`) to simulate ⌘V via `CGEvent`

## Monitoring & Observability

**Error Tracking:**
- None — no Sentry, Crashlytics, or remote error reporting

**Logs:**
- `NSLog()` — used throughout for debug/operational messages (writes to system log / Console.app)
- No structured logging framework (no `os_log`, no `Logger`)
- Key logging sites: `HotkeyService`, `AppDelegate`, `AudioDeviceService`, `ShellPreferences`

## CI/CD & Deployment

**Hosting:**
- Direct distribution (no App Store, no Sparkle updater detected)
- No CI pipeline configuration found (no `.github/workflows/`, no `Jenkinsfile`, no Fastlane)

**Build:**
- Manual: `./build.sh` (wraps `xcodebuild -project Speech2Text.xcodeproj -scheme Speech2Text -destination 'platform=macOS,arch=arm64' -configuration Release build`)
- Code signing: Automatic, team `T8UTF8LX97`

## Environment Configuration

**Required env vars:**
- None — the app requires no environment variables

**Secrets location:**
- No secrets. No API keys. No `.env` files. All intelligence is on-device.

## Webhooks & Callbacks

**Incoming:**
- None — no HTTP server, no webhook endpoints

**Outgoing:**
- None — no outbound HTTP calls at runtime (only at model download time via HuggingFace Hub HTTPS)

## System-Level Integrations

**Launch at Login:**
- `ServiceManagement.SMAppService.mainApp` — registers/unregisters the app as a login item
- Managed by: `Speech2Text/Persistence/ShellPreferences.swift` (`setLaunchAtLogin(_:)`)

**Clipboard:**
- `NSPasteboard.general` — write transcribed text to clipboard (`Speech2Text/Clipboard/ClipboardService.swift`)
- `CGEvent` + `NSPasteboard` — simulate ⌘V to auto-paste into active app (`Speech2Text/Clipboard/PasteService.swift`)

**Audio Hardware:**
- CoreAudio `AudioObjectGetPropertyData` — enumerate input devices, detect device disconnect
- Managed by: `Speech2Text/Audio/AudioDeviceService.swift`

**Global Hotkeys:**
- Carbon hot key API via `KeyboardShortcuts` (1.17.0) — no Accessibility permission required
- Managed by: `Speech2Text/Activation/HotkeyService.swift`
- Default shortcuts: Ctrl+V (arm/record), Ctrl+B (arm+paste), Ctrl+Shift+V (cancel)

---

*Integration audit: 2026-03-22*
