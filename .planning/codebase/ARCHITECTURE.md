# Architecture

**Analysis Date:** 2026-03-22

## Pattern Overview

**Overall:** Menu-bar macOS app with event-driven state machine at the core, layered service architecture, and protocol-based dependency injection for testability.

**Key Characteristics:**
- Single `ActivationStore` state machine drives the entire recording → transcription → output pipeline
- `@MainActor` isolation on all UI-touching classes; Swift actors for background ML services
- Protocol abstractions (`WhisperTranscribing`, `LLMRewriting`, `ReadinessProviding`) at service boundaries to enable unit test injection
- Reactive UI via Combine `@Published` properties flowing into SwiftUI views
- No third-party UI frameworks — pure SwiftUI + AppKit NSPanel for the floating pill

## Layers

**App Layer:**
- Purpose: Entry point, lifecycle, wiring of shared singletons
- Location: `Speech2Text/App/`
- Contains: `Speech2TextApp.swift` (SwiftUI `@main`), `AppDelegate.swift` (NSApplicationDelegate)
- Depends on: All service singletons
- Used by: Nothing (top of graph)

**Activation Layer:**
- Purpose: Central state machine for the recording session lifecycle
- Location: `Speech2Text/Activation/`
- Contains: `ActivationStore.swift`, `RecordingState.swift`, `HotkeyService.swift`, `TriggerProfile.swift`, `TriggerProfileStore.swift`, `TriggerTranscriptParser.swift`, `TriggerTranscriptSplit.swift`, `TriggerCalibrationSession.swift`, `TriggerAliasNormalizer.swift`
- Depends on: Audio, Transcription, Conversion, Clipboard, Persistence, Readiness layers
- Used by: App layer, Shell layer

**Audio Layer:**
- Purpose: Microphone capture, audio buffering, VAD, level monitoring
- Location: `Speech2Text/Audio/`
- Contains: `AudioCaptureService.swift`, `AudioBufferAccumulator.swift`, `AudioLevelMonitor.swift`, `AudioDeviceService.swift`, `VoiceActivityDetector.swift`, `LiveCalibrationSampleCapturer.swift`, `ObjCExceptionCatcher.h/.m`
- Depends on: AVFoundation, CoreAudio
- Used by: App layer (wires capture to ActivationStore), ActivationStore (receives buffers via `AudioBufferReceiving` protocol)

**Transcription Layer:**
- Purpose: Whisper speech-to-text
- Location: `Speech2Text/Transcription/`
- Contains: `WhisperService.swift`, `WhisperModelChoice.swift`, `TranscriptionResult.swift`
- Depends on: WhisperKit (SPM)
- Used by: ActivationStore via `WhisperTranscribing` protocol

**Conversion Layer:**
- Purpose: Intent detection, LLM rewriting of transcribed text
- Location: `Speech2Text/Conversion/`
- Contains: `LLMRewriteService.swift`, `RewriteModelTier.swift`, `RewriteModelLoadState.swift`, `IntentDetector.swift`, `IntentCatalog.swift`, `IntentDefinition.swift`, `ConvertIntent.swift`, `ConvertMode.swift`, `UserIntentStore.swift`, `UserIntentEntry.swift`, `StringSimilarity.swift`
- Depends on: MLXLLM, Hub (MLX Swift), mlx-community HuggingFace models
- Used by: ActivationStore

**Clipboard Layer:**
- Purpose: Write transcribed/rewritten text to system clipboard; optionally simulate paste
- Location: `Speech2Text/Clipboard/`
- Contains: `ClipboardService.swift`, `PasteService.swift`
- Depends on: AppKit (NSPasteboard), CoreGraphics (CGEvent for ⌘V simulation)
- Used by: ActivationStore

**Persistence Layer:**
- Purpose: User preferences, trigger profiles, UserDefaults persistence
- Location: `Speech2Text/Persistence/`
- Contains: `ShellPreferences.swift`
- Depends on: Foundation, Combine, ServiceManagement
- Used by: ActivationStore, App layer, Shell layer, Readiness layer

**Readiness Layer:**
- Purpose: Permission gating — determines whether the app can record
- Location: `Speech2Text/Readiness/`
- Contains: `ReadinessStore.swift`, `ReadinessSnapshot.swift`
- Depends on: Permissions layer, Persistence layer
- Used by: App layer, Shell layer, ActivationStore

**Permissions Layer:**
- Purpose: Platform permission queries and request flows
- Location: `Speech2Text/Permissions/`
- Contains: `MicrophonePermissionService.swift`, `KeyboardPermissionService.swift`, `PostEventPermissionService.swift`
- Depends on: AVFoundation, AppKit
- Used by: ReadinessStore

**Shell Layer (UI):**
- Purpose: All user-facing views — settings window, status menu, floating pill, intent editor
- Location: `Speech2Text/Shell/`
- Contains: `SetupWindowView.swift`, `StatusMenuView.swift`, `StatusCardView.swift`, `RecordingPillPanel.swift`, `RecordingPillView.swift`, `PermissionChecklistView.swift`, `AIAssistantSettingsView.swift`, `IntentListView.swift`, `IntentEditView.swift`, `AssistantCalibrationRunner.swift`, `RecoveryActions.swift`
- Depends on: ActivationStore, ShellPreferences, ReadinessStore
- Used by: App layer (presented by AppDelegate)

## Data Flow

**Recording Session (happy path):**

1. User presses hotkey → `HotkeyService` fires → `ActivationStore.arm()` called
2. `ActivationStore` checks `ReadinessSnapshot` permissions → transitions state to `.recording`
3. `AppDelegate` observes `ActivationStore.$state` → calls `AudioCaptureService.start()` with `VoiceActivityDetector` as `AudioBufferReceiving`
4. `AVAudioEngine` tap delivers PCM buffers → `VoiceActivityDetector.append()` → forwards to `AudioBufferAccumulator`
5. User presses hotkey again (toggle) → `ActivationStore.finish()` → state transitions to `.processing`
6. `AppDelegate` observes `.processing` → calls `AudioCaptureService.stop()`
7. `ActivationStore.finalizeSession()` runs async: `AudioBufferAccumulator.convertToWhisperFormat()` → `WhisperService.transcribe()`
8. Raw transcript parsed: `TriggerTranscriptParser.split()` detects AI assistant trigger word
9. If no trigger → `IntentDetector` scans full transcript for conversion commands → builds `ConvertIntent`
10. If trigger found → split into content + instruction → `IntentDetector.detectPredefinedShortcut()` + custom intent lookup
11. Passthrough path: transcript written to `ClipboardService`; optionally `PasteService.paste()`
12. Conversion path: word-count gate (≤350 words) → `LLMRewriteService.rewrite()` → rewritten text to clipboard
13. `ActivationStore` transitions to `.success` or `.failure` → `RecordingPillPanel` shows result → auto-dismisses to `.idle`

**Model Download Flow:**
1. On launch, `AppDelegate` calls `RewriteModelLoadState.shared.startDownload(for: preferences.rewriteModelTier)`
2. `AppDelegate` observes `preferences.$rewriteModelTier` — on change, triggers new download
3. `LLMRewriteService.download()` uses `Hub` to fetch from mlx-community HuggingFace
4. Model cached to `~/Library/Application Support/Speech2Text/RewriteModel/`
5. `WhisperService.prepare()` downloads and caches model at first use

**State Management:**
- `RecordingState` enum with six states: `.idle`, `.recording`, `.processing`, `.converting`, `.success`, `.failure`
- State transitions exclusively owned by `ActivationStore` — all other objects react to `$state` via Combine
- `AppDelegate` is the primary state observer — drives audio start/stop, menu bar icon updates
- `RecordingPillPanel` independently observes `ActivationStore.$state` for floating UI show/hide

## Key Abstractions

**RecordingState:**
- Purpose: The single source of truth for current app state; drives all reactive behavior
- File: `Speech2Text/Activation/RecordingState.swift`
- Pattern: Value-type enum with associated values; `.isTerminal` computed property separates transient from terminal states

**ActivationStore:**
- Purpose: Orchestrator — owns the session lifecycle, coordinates all services
- File: `Speech2Text/Activation/ActivationStore.swift`
- Pattern: `@MainActor final class ObservableObject`, singleton via `static let shared`; all dependencies injected in `init()` for testability

**WhisperTranscribing protocol:**
- Purpose: Abstraction over WhisperKit so tests inject a mock
- File: `Speech2Text/Transcription/WhisperService.swift`
- Pattern: `protocol WhisperTranscribing: Sendable { func transcribe(samples: [Float]) async throws -> String }`

**LLMRewriting protocol:**
- Purpose: Abstraction over LLMRewriteService so tests inject a mock
- File: `Speech2Text/Conversion/LLMRewriteService.swift`
- Pattern: `protocol LLMRewriting: Sendable` with two `rewrite` variants (mode-based and instruction-based)

**ConvertIntent:**
- Purpose: Value type carrying detection result — mode, stripped body, original transcript, optional custom system prompt
- File: `Speech2Text/Conversion/ConvertIntent.swift`
- Pattern: Immutable struct; `hadCandidates` flag signals near-miss to UI (orange pill)

**TriggerProfile:**
- Purpose: User's configured AI assistant name/aliases for trigger-word detection
- File: `Speech2Text/Activation/TriggerProfile.swift`
- Pattern: Codable struct with preset enum (`zeus`, `atlas`, `gaia`, `custom`) + per-preset alias arrays

**AudioBufferReceiving:**
- Purpose: Protocol allowing the AVAudioEngine tap to deliver PCM buffers to any receiver
- File: `Speech2Text/Audio/AudioCaptureService.swift`
- Pattern: `protocol AudioBufferReceiving: AnyObject { nonisolated func append(_ buffer: AVAudioPCMBuffer) }`

## Entry Points

**Speech2TextApp (SwiftUI @main):**
- Location: `Speech2Text/App/Speech2TextApp.swift`
- Triggers: macOS app launch
- Responsibilities: Creates `MenuBarExtra` scene, holds `@StateObject` refs for shared stores, wires `@NSApplicationDelegateAdaptor`

**AppDelegate:**
- Location: `Speech2Text/App/AppDelegate.swift`
- Triggers: `applicationDidFinishLaunching`
- Responsibilities: Starts `HotkeyService`, triggers model pre-downloads, observes `ActivationStore.$state`, manages `RecordingPillPanel` and setup window, handles UI-testing argument overrides

**HotkeyService:**
- Location: `Speech2Text/Activation/HotkeyService.swift`
- Triggers: User keypress (default Ctrl-V to arm, Ctrl-Shift-V to cancel, Ctrl-B to arm+paste)
- Responsibilities: Debounce duplicate activations, dispatch to `ActivationStore`

## Error Handling

**Strategy:** Errors are caught at service boundaries and converted to domain-specific error types. The `ActivationStore.finalizeSession()` catch blocks translate all errors to `RecordingState.FailureReason` values for display; raw errors never surface in UI.

**Patterns:**
- `WhisperService` wraps all WhisperKit errors → `TranscriptionError`
- `LLMRewriteService` wraps load/generation errors → `LLMRewriteError`; OOM errors detected by description string and mapped to `.modelTooLargeForDevice`
- `AudioCaptureService` wraps AVFoundation/CoreAudio errors → `AudioCaptureError`
- Conversion failure silently falls back: raw transcript written to clipboard, success state shown
- Word-limit guard (350 words) fires before LLM call; raw transcript written to clipboard, failure state shown

## Cross-Cutting Concerns

**Logging:** `NSLog` throughout (no structured logging framework). Logs prefixed with component name (e.g. `"HotkeyService: ..."`, `"Speech2Text: ..."`).

**Validation:** Transcript validation in `ActivationStore.finalizeSession()` — empty string check, word-count guard. Permission validation in `ReadinessSnapshot.derive()` — pure function.

**Authentication:** macOS system permissions only (microphone via AVFoundation, accessibility/post-event via system dialog). No network auth.

**Concurrency:** `@MainActor` on all UI/store classes. `actor` isolation on `WhisperService`, `LLMRewriteService`, `UserIntentStore`. `NSLock` inside `AudioBufferAccumulator` for cross-thread buffer appending.

---

*Architecture analysis: 2026-03-22*
