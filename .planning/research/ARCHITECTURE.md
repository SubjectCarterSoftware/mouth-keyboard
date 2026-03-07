# Architecture Research

**Domain:** macOS system-wide clipboard-first dictation utility
**Researched:** 2026-03-05
**Confidence:** HIGH

## Standard Architecture

### System Overview

```text
┌──────────────────────────────────────────────────────────────┐
│                  System Integration Layer                    │
├──────────────────────────────────────────────────────────────┤
│  Menu Bar UI   Global Hotkey   Session Key Tap   Permissions │
│  Status Item   Activation      (space/esc/back)  Gatekeeper  │
└────────┬──────────────┬──────────────┬──────────────┬────────┘
         │              │              │              │
┌────────▼─────────────────────────────────────────────────────┐
│                  Session Orchestration Layer                 │
├──────────────────────────────────────────────────────────────┤
│ Session State Machine │ Recording Coordinator │ UI Presenter │
│ Segment Queue         │ Restart/Cancel Logic  │ Clipboard Job │
└────────┬───────────────────────┬───────────────────────┬──────┘
         │                       │                       │
┌────────▼──────────────┐ ┌──────▼────────────────┐ ┌───▼────────┐
│    Audio Pipeline     │ │   Transcription Core  │ │ Persistence │
├───────────────────────┤ ├───────────────────────┤ ├─────────────┤
│ AVAudioEngine         │ │ Engine Adapter        │ │ Settings    │
│ Device Selection      │ │ Whisper Backend       │ │ Recent State│
│ Buffer + VAD          │ │ Optional Apple Backend│ │ Logs/Metrics│
└───────────────────────┘ └───────────────────────┘ └─────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| Hotkey / input layer | Detect activation and in-session control keys | `KeyboardShortcuts` or Carbon for activation, plus scoped `CGEventTap`/input-monitoring path while recording |
| Session coordinator | Own app state from idle to clipboard-complete | Single state machine actor/object that receives events and emits side effects |
| Audio capture pipeline | Start mic input immediately, buffer samples, detect gaps | `AVAudioEngine` input tap, device abstraction, silence/VAD logic, rolling segment buffers |
| Transcription engine adapter | Convert audio segments into text with swappable backends | Protocol-backed engine abstraction with `whisper.cpp` implementation first |
| Result assembler | Preserve segment ordering, partial failures, and final text cleanup | Queue metadata, ordered merge, punctuation/whitespace normalization, failure markers |
| UI controller | Reflect state without stealing focus | Menu bar icon, lightweight overlay/HUD, error toasts, settings window |
| Clipboard controller | Write final output atomically and confirm success | `NSPasteboard.general`, `clearContents()`, `setString(_:forType:)` |

## Recommended Project Structure

```text
Speech2Test/
├── App/                  # App entry, app delegate, scene wiring
│   ├── Speech2TestApp.swift
│   └── AppRuntime.swift
├── UI/                   # Visible UI only
│   ├── MenuBar/          # Status item, menus, icon state
│   ├── Overlay/          # Floating indicator / transient confirmations
│   └── Settings/         # Hotkey, engine, mic, indicator settings
├── Core/                 # Product behavior and state
│   ├── Session/          # Session state machine, commands, events
│   ├── Permissions/      # Mic, accessibility, input monitoring checks
│   ├── Clipboard/        # Clipboard writer and guard rails
│   └── Telemetry/        # Timings, logs, diagnostic counters
├── Audio/                # Live capture and segmentation
│   ├── Capture/          # AVAudioEngine setup, device switching
│   ├── Buffering/        # PCM ring buffers / segment storage
│   └── Segmentation/     # Silence detection, threshold rules, queueing
├── Transcription/        # Engine abstraction and implementations
│   ├── Engine/           # Protocols, result models, shared types
│   ├── Whisper/          # whisper.cpp bridge and model manager
│   └── AppleSpeech/      # Optional benchmark/fallback backend
├── Support/              # Small cross-cutting helpers
│   ├── Logging/
│   └── Utilities/
└── Tests/
    ├── Unit/
    ├── Integration/
    └── UI/
```

### Structure Rationale

- **`Core/` stays separate from `UI/`:** The recording/transcription loop should be testable without menu bar or overlay UI coupled into it.
- **`Audio/` and `Transcription/` are split:** Capture correctness and ASR behavior change at different rates; keeping them separate reduces regressions when swapping models or tuning segmentation.
- **`Transcription/Engine/` owns protocols:** This preserves the option to benchmark Apple Speech versus Whisper without rewriting the session coordinator.

## Architectural Patterns

### Pattern 1: Session State Machine

**What:** Represent idle, recording, processing, canceled, failed, and completed as explicit states with event-driven transitions.
**When to use:** Always; this app has a short but high-stakes interaction loop where hidden states create user-facing bugs fast.
**Trade-offs:** Slightly more structure up front, much less ambiguity in finish/cancel/restart behavior.

**Example:**
```swift
enum SessionState {
    case idle
    case recording(RecordingSession)
    case processing(QueuedSegments)
    case completed(String)
    case canceled
    case failed(SessionError)
}
```

### Pattern 2: Engine Adapter Boundary

**What:** Hide speech backends behind a single transcription protocol.
**When to use:** Use from day one if the spec includes local, cloud, and hybrid possibilities even though v1 is local-first.
**Trade-offs:** Slight abstraction cost, but much easier benchmarking and fallback behavior later.

**Example:**
```swift
protocol TranscriptionEngine {
    func warmUp() async throws
    func transcribe(_ segment: AudioSegment) async throws -> TranscriptSegment
}
```

### Pattern 3: Ordered Segment Queue

**What:** Treat each long-dictation chunk as an immutable work item with sequence metadata.
**When to use:** As soon as long dictation or restart-in-place is supported.
**Trade-offs:** More bookkeeping than a single buffer, but far better failure isolation and deterministic final assembly.

**Example:**
```swift
struct QueuedSegment: Sendable {
    let sequence: Int
    let startedAt: TimeInterval
    let audioURL: URL
}
```

## Data Flow

### Recording Flow

```text
[User presses hotkey]
    ↓
[Activation handler]
    ↓
[Permissions gate]
    ↓
[Session coordinator enters recording]
    ↓
[AVAudioEngine input tap buffers PCM]
    ↓
[Segmenter decides: keep / cut / restart]
    ↓
[Queued segments sent to engine adapter]
    ↓
[Ordered transcripts assembled]
    ↓
[Clipboard writer updates NSPasteboard]
    ↓
[UI shows success / failure state]
```

### State Management

```text
[Input events + audio events + engine callbacks]
    ↓
[Session coordinator]
    ↓
[State transition]
    ↓
[Side effects: audio / engine / clipboard / UI]
    ↓
[Published state]
    ↓
[Menu bar + overlay render]
```

### Key Data Flows

1. **Activation flow:** idle hotkey triggers permission checks, recording state entry, and UI update in that order.
2. **Segmentation flow:** audio buffers accumulate until threshold + silence gap, then become immutable queued segments for transcription.
3. **Completion flow:** final key ends capture, flushes the last segment, awaits ordered transcription results, and writes the combined string once.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Solo user / single Mac | Single-process architecture is correct; focus on warm-up, latency, and recoverability |
| Small beta across mixed hardware | Add device/model benchmark telemetry, fallback presets, and startup diagnostics |
| Wide public release | Add crash reporting, hardware capability heuristics, and stronger settings migration; keep the runtime single-process unless evidence forces otherwise |

### Scaling Priorities

1. **First bottleneck:** Cold-start model load time; solve with engine warm-up and cached assets before adding more UI.
2. **Second bottleneck:** Long-dictation queue contention and memory growth; solve with file-backed segment storage and bounded in-memory buffers.

## Anti-Patterns

### Anti-Pattern 1: God Manager

**What people do:** Put hotkeys, audio, transcription, clipboard, and UI state into one giant observable object.
**Why it's wrong:** Every change risks cross-domain regressions, and testing becomes almost impossible.
**Do this instead:** Keep a session coordinator at the center, but split audio, engine, permissions, and UI into explicit services.

### Anti-Pattern 2: Process-Per-Transcription

**What people do:** Spawn a new Python or CLI process for every dictation segment.
**Why it's wrong:** It destroys latency and makes warm-up cost dominate short dictations.
**Do this instead:** Keep a warm native backend in-process and feed it segments directly.

### Anti-Pattern 3: UI-Driven Business Logic

**What people do:** Let overlay or menu state decide recording behavior.
**Why it's wrong:** Hidden UI assumptions break background operation and make headless tests meaningless.
**Do this instead:** UI reflects state; it does not own it.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Microphone / audio stack | `AVAudioEngine` input node tap | Must handle permission denial, device changes, and format consistency |
| Accessibility / Input Monitoring | Preflight + request before global session-key capture | Activation and in-session controls may require different primitives; test both fresh-install and upgraded permission states |
| Pasteboard | `NSPasteboard.general` write on completion | Treat clipboard write as the final transaction, not a best-effort side effect |
| Launch at login | `SMAppService` or user-triggered helper integration | Nice to have for a background utility, but not core to the speech loop |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `Core/Session` ↔ `Audio/` | Async service calls + event callbacks | Audio should emit structured events, not mutate UI directly |
| `Core/Session` ↔ `Transcription/` | Protocol-based async API | Enables backend swapping and isolated tests |
| `Core/Session` ↔ `UI/` | Published read-only state | UI observes; it should not skip coordinator transitions |
| `Core/Clipboard` ↔ `UI/` | Success/failure event | Needed for confirmations and error recovery messaging |

## Sources

- Apple Developer Documentation, `Speech` — https://developer.apple.com/documentation/speech
- Apple Developer Documentation, `Recognizing speech in live audio` — https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio
- Apple Developer Documentation, `AVAudioNode` — https://developer.apple.com/documentation/avfaudio/avaudionode
- Apple Developer Documentation, `NSPasteboard.general` — https://developer.apple.com/documentation/appkit/nspasteboard/general
- Apple Documentation Archive, `Monitoring Events` — https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html
- Apple Developer Forums, input-monitoring vs accessibility guidance for global key capture — https://developer.apple.com/forums/thread/707680
- `KeyboardShortcuts` — https://github.com/sindresorhus/KeyboardShortcuts
- `whisper.cpp` — https://github.com/ggml-org/whisper.cpp

---
*Architecture research for: macOS system-wide clipboard-first dictation utility*
*Researched: 2026-03-05*
