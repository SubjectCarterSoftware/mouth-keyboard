# Codebase Structure

**Analysis Date:** 2026-03-22

## Directory Layout

```
speech2test/
├── Speech2Text/                  # All production Swift source
│   ├── App/                      # Entry point and app lifecycle
│   ├── Activation/               # State machine, hotkeys, trigger identity
│   ├── Audio/                    # Microphone capture, VAD, buffering
│   ├── Clipboard/                # Write to clipboard, simulate paste
│   ├── Conversion/               # Intent detection, LLM rewriting, model tiers
│   ├── Permissions/              # macOS permission query/request services
│   ├── Persistence/              # UserDefaults preferences
│   ├── Readiness/                # Permission-state aggregation
│   ├── Resources/                # Non-Swift assets
│   │   └── Sounds/               # .aiff feedback sounds (Tink, Glass, Basso)
│   └── Shell/                    # All SwiftUI + AppKit UI views
├── Speech2TextTests/             # Unit test targets (XCTest)
├── Speech2TextUITests/           # XCUITest end-to-end smoke tests
├── Speech2Text.xcodeproj/        # Xcode project file
├── .planning/                    # GSD planning documents
│   ├── codebase/                 # Auto-generated codebase analysis docs
│   ├── milestones/               # Milestone phase plans
│   ├── phases/                   # Individual phase plans
│   ├── research/                 # Research notes
│   ├── debug/                    # Debug session logs
│   └── feature-proposals/        # Feature proposal documents
├── build.sh                      # Build script
├── README.md
└── .gitignore
```

## Directory Purposes

**`Speech2Text/App/`:**
- Purpose: SwiftUI app entry point and NSApplicationDelegate
- Contains: `Speech2TextApp.swift`, `AppDelegate.swift`
- Key files: `AppDelegate.swift` — the central wiring hub; wires all singletons together on launch

**`Speech2Text/Activation/`:**
- Purpose: The recording session state machine and everything needed to decide when/how to activate
- Contains: `ActivationStore.swift`, `RecordingState.swift`, `HotkeyService.swift`, `TriggerProfile.swift`, `TriggerProfileStore.swift`, `TriggerTranscriptParser.swift`, `TriggerTranscriptSplit.swift`, `TriggerCalibrationSession.swift`, `TriggerAliasNormalizer.swift`
- Key files: `ActivationStore.swift` — the largest and most important file in the project (~512 lines)

**`Speech2Text/Audio/`:**
- Purpose: Everything AVFoundation: raw PCM capture, VAD, level metering, device management
- Contains: `AudioCaptureService.swift`, `AudioBufferAccumulator.swift`, `AudioLevelMonitor.swift`, `AudioDeviceService.swift`, `VoiceActivityDetector.swift`, `LiveCalibrationSampleCapturer.swift`, `ObjCExceptionCatcher.h`, `ObjCExceptionCatcher.m`
- Key files: `ObjCExceptionCatcher.h/.m` — Objective-C bridge to catch AVAudioEngine Obj-C exceptions that Swift cannot catch with `do/try`

**`Speech2Text/Clipboard/`:**
- Purpose: Output delivery — write text to NSPasteboard or simulate ⌘V paste
- Contains: `ClipboardService.swift`, `PasteService.swift`

**`Speech2Text/Conversion/`:**
- Purpose: Post-transcription processing — intent detection and LLM rewriting
- Contains: `LLMRewriteService.swift`, `RewriteModelTier.swift`, `RewriteModelLoadState.swift`, `IntentDetector.swift`, `IntentCatalog.swift`, `IntentDefinition.swift`, `ConvertIntent.swift`, `ConvertMode.swift`, `UserIntentStore.swift`, `UserIntentEntry.swift`, `StringSimilarity.swift`
- Key files: `LLMRewriteService.swift` — MLX actor; `IntentDetector.swift` — fuzzy NLP matching engine

**`Speech2Text/Permissions/`:**
- Purpose: Thin wrappers around macOS permission APIs; injectable for testing
- Contains: `MicrophonePermissionService.swift`, `KeyboardPermissionService.swift`, `PostEventPermissionService.swift`

**`Speech2Text/Persistence/`:**
- Purpose: All persistent user settings
- Contains: `ShellPreferences.swift` — single `ObservableObject` wrapping a named `UserDefaults` suite
- UserDefaults suite name: `com.elicarter.Speech2Text.shell`

**`Speech2Text/Readiness/`:**
- Purpose: Aggregates permission states into a displayable `ReadinessSnapshot`
- Contains: `ReadinessStore.swift`, `ReadinessSnapshot.swift`

**`Speech2Text/Shell/`:**
- Purpose: All UI — menu bar dropdown, settings window, floating pill, intent management views
- Contains: `SetupWindowView.swift`, `StatusMenuView.swift`, `StatusCardView.swift`, `RecordingPillPanel.swift`, `RecordingPillView.swift`, `PermissionChecklistView.swift`, `AIAssistantSettingsView.swift`, `IntentListView.swift`, `IntentEditView.swift`, `AssistantCalibrationRunner.swift`, `RecoveryActions.swift`
- Key files: `RecordingPillPanel.swift` — custom `NSPanel` floating overlay; `SetupWindowView.swift` — settings window (largest UI file)

**`Speech2Text/Resources/Sounds/`:**
- Purpose: Audio feedback files bundled with the app
- Contains: `Tink.aiff` (activation), `Glass.aiff` (success), `Basso.aiff` (failure)

**`Speech2TextTests/`:**
- Purpose: Unit tests; one test file per production source file
- Contains: 21 test files covering all major components
- Key files: `ActivationStoreTests.swift`, `LLMRewriteServiceTests.swift`, `IntentDetectorTests.swift`

**`Speech2TextUITests/`:**
- Purpose: XCUITest smoke tests for full UI flows
- Contains: `AIAssistantSettingsFlowTests.swift`, `MenuBarShellSmokeTests.swift`, `PermissionRecoveryFlowTests.swift`

## Key File Locations

**Entry Points:**
- `Speech2Text/App/Speech2TextApp.swift`: SwiftUI `@main`, MenuBarExtra scene
- `Speech2Text/App/AppDelegate.swift`: Launch wiring, state observation, window management

**Configuration:**
- `Speech2Text/Persistence/ShellPreferences.swift`: All user preferences (UserDefaults-backed, named suite)
- `Speech2Text/Conversion/RewriteModelTier.swift`: LLM model tiers, hub slugs, download sizes
- `Speech2Text/Transcription/WhisperModelChoice.swift`: Whisper model options

**Core Logic:**
- `Speech2Text/Activation/ActivationStore.swift`: Session orchestration, transcription pipeline
- `Speech2Text/Conversion/IntentDetector.swift`: Fuzzy NLP intent matching
- `Speech2Text/Conversion/IntentCatalog.swift`: All built-in intent definitions with phrase patterns
- `Speech2Text/Conversion/LLMRewriteService.swift`: MLX-based local LLM rewriting actor
- `Speech2Text/Transcription/WhisperService.swift`: WhisperKit transcription actor

**Testing:**
- `Speech2TextTests/`: Unit tests, mirroring source structure (one file per production class)
- `Speech2TextUITests/`: XCUITest flows

## Naming Conventions

**Files:**
- `PascalCase.swift` for all Swift files — always matches the primary type name inside
- `ObjCExceptionCatcher.h/.m` — only Objective-C files in the project

**Types:**
- Classes, structs, enums, protocols: `PascalCase`
- Service classes end in `Service` (e.g. `AudioCaptureService`, `ClipboardService`)
- Store classes end in `Store` (e.g. `ActivationStore`, `ReadinessStore`, `UserIntentStore`)
- View files end in `View` or `Panel` (e.g. `StatusMenuView`, `RecordingPillPanel`)

**Test Files:**
- Named `{SourceFileName}Tests.swift` (e.g. `ActivationStoreTests.swift`)
- Integration tests: `{SourceFileName}IntegrationTests.swift`

**Variables and Functions:**
- `camelCase` for all properties, variables, and method names
- Protocols for injectable services use `...ing` suffix (e.g. `WhisperTranscribing`, `LLMRewriting`, `AudioBufferReceiving`, `ReadinessProviding`)

**Singletons:**
- All shared singletons use `static let shared = ...` pattern
- Singletons always provide a DI-friendly `init(...)` with injected dependencies used by tests

## Where to Add New Code

**New Recording Pipeline Feature:**
- Orchestration logic: `Speech2Text/Activation/ActivationStore.swift` (inside `finalizeSession`)
- State changes: extend `RecordingState` in `Speech2Text/Activation/RecordingState.swift`
- Tests: `Speech2TextTests/ActivationStoreTests.swift`

**New Conversion Intent (built-in):**
- Add `ConvertMode` case to `Speech2Text/Conversion/ConvertMode.swift`
- Add `IntentDefinition` entry to `Speech2Text/Conversion/IntentCatalog.swift`
- Tests: `Speech2TextTests/IntentDetectorTests.swift`, `Speech2TextTests/IntentCatalogDynamicTests.swift`

**New LLM Model Tier:**
- Add case to `Speech2Text/Conversion/RewriteModelTier.swift`
- Add picker row in `Speech2Text/Shell/SetupWindowView.swift`

**New Setting/Preference:**
- Add `@Published var` with `didSet` persistence to `Speech2Text/Persistence/ShellPreferences.swift`
- Add `static let key = "..."` to `ShellPreferences.Keys`
- Tests: `Speech2TextTests/ShellPreferencesModelTests.swift`

**New SwiftUI View:**
- Place in `Speech2Text/Shell/`
- Follow `PascalCase + View` naming

**New Service:**
- Place in the most appropriate domain subdirectory
- Define a protocol abstraction if the service needs to be mocked in tests
- Add `static let shared` singleton + full DI `init`
- Add test file to `Speech2TextTests/` as `{ServiceName}Tests.swift`

**New Audio Handling:**
- Place in `Speech2Text/Audio/`
- Implement `AudioBufferReceiving` if the service needs to receive PCM buffers

**New Permission Type:**
- Add case to `PermissionKind` in `Speech2Text/Readiness/ReadinessSnapshot.swift`
- Add service to `Speech2Text/Permissions/`
- Update `ReadinessSnapshot.derive()` and `ReadinessStore`

## Special Directories

**`.planning/`:**
- Purpose: GSD planning documents — milestone plans, phase plans, research, debug logs
- Generated: No (human/AI authored)
- Committed: Yes

**`.planning/codebase/`:**
- Purpose: Auto-generated codebase analysis documents (this file lives here)
- Generated: Yes (by `$gsd-map-codebase`)
- Committed: Yes

**`.build/DerivedData/`:**
- Purpose: Xcode build artifacts
- Generated: Yes
- Committed: No (in `.gitignore`)

**`Speech2Text.xcodeproj/`:**
- Purpose: Xcode project definition, scheme configurations, SPM package resolution
- Key file: `project.xcworkspace/xcshareddata/swiftpm/` — Swift Package Manager dependencies (WhisperKit, KeyboardShortcuts, MLX Swift)

---

*Structure analysis: 2026-03-22*
