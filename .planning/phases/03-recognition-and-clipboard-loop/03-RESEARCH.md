# Phase 3: Recognition and Clipboard Loop - Research

**Researched:** 2026-03-06
**Domain:** Local speech transcription (whisper.cpp), clipboard integration, spacebar interception, state-machine-driven UI feedback
**Confidence:** MEDIUM-HIGH

## Summary

Phase 3 transforms Speech2Test from a recording tool into a functional dictation utility. The core loop is: user finishes recording (spacebar or hotkey) -> audio is batch-transcribed locally via whisper.cpp -> text lands on the clipboard -> optional auto-paste via simulated Cmd+V -> pill shows success/failure feedback then auto-dismisses.

The primary technical challenges are: (1) integrating whisper.cpp via SPM and converting AVAudioEngine's native-format buffers to whisper's required 16kHz mono Float32, (2) intercepting spacebar system-wide during recording only (requires CGEventTap, not the Carbon hot key API currently used), (3) expanding the RecordingState enum to drive processing/success/failure pill states with timed auto-dismiss, and (4) implementing auto-paste via CGEvent posting without App Sandbox interference.

**Primary recommendation:** Use whisper.cpp via the `ggerganov/whisper.spm` SPM package (branch: master) with the `small.en` model (~466 MB). Accumulate audio buffers in-memory during recording, convert to 16kHz mono Float32 via AVAudioConverter on finish, run whisper_full synchronously on a background actor, then write to NSPasteboard and optionally auto-paste.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Use **whisper.cpp** via the Swift Package Manager wrapper (whisper.spm), compiled directly into the app.
- Default model: **small** (~500MB) for accuracy with punctuation.
- Transcription mode: **batch after finish** -- all audio processed after the user ends recording, not real-time streaming.
- English-only is sufficient for v1.
- Spacebar ends the active recording and triggers transcription.
- Hotkey also ends recording (both spacebar and hotkey serve as finish keys).
- Spacebar intercepted via the **same CGEventTap** used by HotkeyService, only active when RecordingState == .recording.
- Spacebar is **consumed** (swallowed) -- not passed through to the active application.
- Audio capture **stops immediately** on finish -- no trailing buffer.
- Always attempt transcription regardless of recording duration (no minimum length gate).
- On successful transcription, write text to the system clipboard via NSPasteboard.
- **Auto-paste enabled by default** -- after clipboard write, simulate Cmd+V with a ~50-100ms delay.
- Auto-paste is toggleable in settings (user can disable).
- On failure, clipboard is **left unchanged** (preserves user's previous clipboard content).
- If **60 seconds** of continuous silence (no speech input), auto-stop recording.
- Still attempt transcription on whatever audio was captured (may succeed if speech occurred earlier).
- **Visual warning at ~45s** -- pill color shifts or subtle indicator before auto-stop fires.
- Timeout duration is **fixed at 60s** (not user-configurable in v1).
- During transcription: pill shows a **pulsing animation** (replaces waveform). No text change, no spinner.
- On success: pill flashes a **checkmark / "Copied!"** for ~1.5s, then auto-dismisses.
- On failure: pill turns **red** with a **specific failure message** for ~2s, then auto-dismisses.
- Failure messages distinguish between types: no speech, model error, audio too short, timeout.
- The visibility toggle **hides the pill entirely** across all states.
- When pill is hidden, the **menu bar icon still changes** to reflect state.
- Toggle lives in existing settings alongside other preferences.

### Claude's Discretion
- Exact pulsing animation style and timing for the processing state.
- Exact red color treatment for failure pill.
- Exact checkmark/success visual treatment.
- Audio buffer accumulation strategy (in-memory vs temp file) and format conversion to whisper-compatible PCM.
- RecordingState enum expansion (adding processing, success, failure cases) and transition timing.
- How the ~45s silence warning manifests visually (color shift, subtle countdown, etc.).
- Whisper model storage location and initialization strategy.
- Auto-paste implementation details (CGEvent posting vs accessibility API).

### Deferred Ideas (OUT OF SCOPE)
- Silence timeout as user-configurable duration -- keep fixed at 60s for v1, revisit if users need adjustment.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SESS-01 | User can finish the active recording with the spacebar while remaining in the current application. | CGEventTap spacebar interception pattern; consumed (swallowed) via returning nil from tap callback |
| TRNS-01 | User receives local-first speech transcription for captured audio. | whisper.cpp via whisper.spm SPM package; batch transcription after finish using whisper_full C API |
| TRNS-02 | User receives punctuation in the transcribed text without manual cleanup for normal dictation. | whisper small.en model produces punctuation natively; no post-processing needed |
| TRNS-06 | User receives a clear failure state instead of a silent or misleading success when transcription cannot produce usable text. | RecordingState expansion with typed failure cases; empty-transcript detection; model-error catching |
| CLIP-01 | User receives the final transcription in the system clipboard after a successful session. | NSPasteboard.general.clearContents() + setString(_:forType:.string) pattern |
| FEED-01 | User can distinguish idle, recording, and processing states from visual indicators. | RecordingState enum expansion; pill pulsing animation; menu bar icon changes per state |
| FEED-03 | User can choose whether the recording indicator is visible. | ShellPreferences toggle; pill hidden entirely; menu bar icon still reflects state |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| whisper.spm | master branch | whisper.cpp SPM wrapper for local transcription | Official SPM package by whisper.cpp author; compiles C/C++ directly into app binary |
| whisper.cpp | v1.8.1 (bundled) | Speech-to-text inference engine | Industry-standard local Whisper implementation; Metal/Accelerate optimized for Apple Silicon |
| AVAudioConverter | macOS SDK | Resample captured audio to 16kHz mono Float32 | Apple's built-in audio format converter; handles sample rate and channel conversion correctly |
| NSPasteboard | macOS SDK | Write transcription text to system clipboard | Standard macOS clipboard API |
| CGEventTap | macOS SDK | Intercept spacebar during recording state | Only mechanism that can swallow (consume) global key events from other apps |
| CGEvent | macOS SDK | Simulate Cmd+V for auto-paste | Standard approach for posting synthetic keyboard events |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Accelerate (vDSP) | macOS SDK | Audio level RMS calculation (already in use) | Silence detection for 60s timeout |
| SwiftUI animation | macOS SDK | Pulsing processing animation, success/failure pill states | All new pill visual states |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| whisper.spm | SwiftWhisper (exPHAT) | Higher-level async API but last updated Aug 2023; whisper.spm is closer to upstream |
| whisper.spm | whisper.cpp XCFramework | Precompiled binary but less control over build flags; SPM source build preferred |
| CGEventTap for spacebar | NSEvent.addGlobalMonitorForEvents | Cannot swallow/consume events -- spacebar would still reach the active app |
| CGEvent for auto-paste | Accessibility API (AXUIElement) | More complex, less reliable across apps; CGEvent is the standard approach (used by Maccy) |

### Installation

Add to Xcode project: File -> Add Packages -> `https://github.com/ggerganov/whisper.spm` with dependency rule set to **branch: master** (required to avoid unsafe build flag errors).

**Model download:** The `ggml-small.en.bin` model (~466 MB) must be bundled with the app or downloaded on first launch from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin`.

## Architecture Patterns

### Recommended Project Structure
```
Speech2Test/
  Activation/
    RecordingState.swift          # Expand enum: idle, recording, processing, success, failure
    ActivationStore.swift         # Add finish() method, orchestrate post-recording flow
    HotkeyService.swift           # Existing (no changes needed for hotkey finish)
    SpacebarInterceptor.swift     # NEW: CGEventTap for spacebar during recording
  Audio/
    AudioCaptureService.swift     # Add buffer accumulation alongside level monitoring
    AudioLevelMonitor.swift       # Extend for silence detection (60s timeout)
    AudioBufferAccumulator.swift  # NEW: Collects AVAudioPCMBuffer chunks in memory
  Transcription/
    WhisperService.swift          # NEW: Actor wrapping whisper.cpp C API
    TranscriptionResult.swift     # NEW: Success(text) | Failure(reason) enum
  Clipboard/
    ClipboardService.swift        # NEW: NSPasteboard write + optional auto-paste
  Shell/
    RecordingPillView.swift       # Expand for processing/success/failure visual states
    RecordingPillPanel.swift      # Support dynamic size changes for failure messages
  Persistence/
    ShellPreferences.swift        # Add keys: autoPasteEnabled, indicatorVisible
```

### Pattern 1: Actor-Isolated Whisper Context
**What:** Wrap whisper.cpp context in a Swift actor to ensure thread-safe, off-main-thread transcription.
**When to use:** Always -- whisper_full is CPU-intensive and must not block the main thread.
**Example:**
```swift
// Source: whisper.cpp examples/whisper.swiftui LibWhisper.swift
actor WhisperService {
    private var context: OpaquePointer?

    func loadModel(at path: String) throws {
        var params = whisper_context_default_params()
        params.flash_attn = true  // Metal acceleration
        guard let ctx = whisper_init_from_file_with_params(path, params) else {
            throw TranscriptionError.modelLoadFailed
        }
        self.context = ctx
    }

    func transcribe(samples: [Float]) throws -> String {
        guard let context else { throw TranscriptionError.noModel }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        params.n_threads = Int32(maxThreads)
        params.language = "en".withCString { strdup($0) }
        params.translate = false
        params.no_context = true

        let result = samples.withUnsafeBufferPointer { buf in
            whisper_full(context, params, buf.baseAddress, Int32(buf.count))
        }
        guard result == 0 else { throw TranscriptionError.inferenceFailed }

        var text = ""
        for i in 0..<whisper_full_n_segments(context) {
            if let segment = whisper_full_get_segment_text(context, i) {
                text += String(cString: segment)
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.noSpeechDetected }
        return trimmed
    }

    deinit {
        if let context { whisper_free(context) }
    }
}
```

### Pattern 2: Audio Buffer Accumulation with Format Conversion
**What:** Capture audio in the hardware's native format, accumulate buffers in memory, then convert to 16kHz mono Float32 on finish.
**When to use:** For batch-after-finish transcription mode.
**Example:**
```swift
// Source: Apple TN3136 AVAudioConverter
final class AudioBufferAccumulator {
    private var buffers: [AVAudioPCMBuffer] = []
    private let inputFormat: AVAudioFormat

    init(format: AVAudioFormat) {
        self.inputFormat = format
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        buffers.append(buffer)
    }

    func convertToWhisperFormat() throws -> [Float] {
        let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        )!
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)!

        // Concatenate all buffers, then convert
        let totalFrames = buffers.reduce(0) { $0 + $1.frameLength }
        let combined = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                         frameCapacity: totalFrames)!
        // ... copy frames into combined buffer ...

        let ratio = 16000.0 / inputFormat.sampleRate
        let outFrameCount = AVAudioFrameCount(Double(totalFrames) * ratio)
        let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                          frameCapacity: outFrameCount)!

        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            status.pointee = .haveData
            return combined
        }

        guard error == nil else { throw error! }
        let ptr = outBuffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ptr,
                                          count: Int(outBuffer.frameLength)))
    }

    func reset() { buffers.removeAll() }
}
```

### Pattern 3: CGEventTap for Spacebar Interception
**What:** Create a CGEventTap that intercepts spacebar keyDown only when recording is active, swallowing the event.
**When to use:** Spacebar finish trigger during recording state.
**Example:**
```swift
// Source: Apple Developer docs, usagimaru/EventTapper pattern
final class SpacebarInterceptor {
    private var eventTap: CFMachPort?
    var isActive: Bool = false  // Set true only during .recording state
    var onSpacebarPressed: (() -> Void)?

    func start() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // Can modify/swallow events
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                let self_ = Unmanaged<SpacebarInterceptor>
                    .fromOpaque(refcon!).takeUnretainedValue()
                guard self_.isActive else { return Unmanaged.passRetained(event) }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 49 { // kVK_Space
                    DispatchQueue.main.async { self_.onSpacebarPressed?() }
                    return nil  // Swallow the event
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
}
```

### Pattern 4: Auto-Paste via CGEvent
**What:** After writing to clipboard, simulate Cmd+V keyDown/keyUp to paste into the active application.
**When to use:** When autoPasteEnabled preference is true.
**Example:**
```swift
// Source: Maccy Clipboard.swift pattern
func autoPaste() {
    let source = CGEventSource(stateID: .combinedSessionState)
    source?.setLocalEventsFilterDuringSuppressionState(
        [.permitLocalMouseEvents, .permitSystemDefinedEvents],
        state: .eventSuppressionStateSuppressionInterval
    )

    let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V
    guard let keyDown = CGEvent(keyboardEventSource: source,
                                 virtualKey: vKeyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source,
                               virtualKey: vKeyCode, keyDown: false)
    else { return }

    let cmdFlag = CGEventFlags.maskCommand
    keyDown.flags = cmdFlag
    keyUp.flags = cmdFlag
    keyDown.post(tap: .cgAnnotatedSessionEventTap)
    keyUp.post(tap: .cgAnnotatedSessionEventTap)
}
```

### Anti-Patterns to Avoid
- **Blocking the main thread during transcription:** whisper_full on the small model can take 1-5+ seconds. Always run on a background actor/thread.
- **Using NSEvent.addGlobalMonitorForEvents for spacebar:** Cannot swallow events -- spacebar would still type a space in the active app.
- **Converting audio format inside the tap callback:** The installTap callback runs on the audio thread; do only lightweight work (append buffer, compute RMS).
- **Initializing whisper context per transcription:** Model loading is expensive (~1-2s). Load once at app startup or lazily on first use, then reuse.
- **Retaining AVAudioPCMBuffer references without copying:** Buffers from installTap may be reused by the system. Copy data or use buffer.copy() if needed.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Audio format conversion (sample rate, channels) | Manual sample-by-sample resampling | AVAudioConverter | Resampling is numerically complex; Apple's implementation handles edge cases, anti-aliasing filters |
| Speech recognition | Custom ML model | whisper.cpp via whisper.spm | Proven, optimized, Metal-accelerated; training your own model is absurd |
| Clipboard write | Direct pasteboard data manipulation | NSPasteboard.general.setString | Three-line API; handles UTI types correctly |
| Synthetic keyboard events | AppleScript or shell `osascript` | CGEvent keyDown/keyUp posting | Lower latency, no process spawning, standard macOS approach |
| Global key interception with swallow | NSEvent monitors or Carbon hot keys | CGEventTap | Only CGEventTap supports event consumption (returning nil to swallow) |

**Key insight:** Every component in this phase has a well-established macOS API or library. The complexity is in orchestrating them correctly, not in building any individual piece.

## Common Pitfalls

### Pitfall 1: Spacebar Interception Requires Accessibility Permission
**What goes wrong:** CGEventTap creation fails silently without Accessibility permission in System Settings > Privacy & Security.
**Why it happens:** CGEventTap with `.defaultTap` (event modification) requires the app to be trusted for Accessibility.
**How to avoid:** The app already requests Accessibility permission in Phase 1. Verify `AXIsProcessTrusted()` before creating the tap. If denied, fall back to hotkey-only finish.
**Warning signs:** `CGEvent.tapCreate` returns nil.

### Pitfall 2: AVAudioPCMBuffer Format Mismatch
**What goes wrong:** AudioCaptureService uses `nil` format for the tap (native hardware format), which varies per device (44.1kHz, 48kHz, etc.). Passing these buffers directly to whisper produces garbage.
**Why it happens:** Whisper requires exactly 16kHz mono Float32. Hardware formats are typically 44.1/48kHz stereo or mono at various bit depths.
**How to avoid:** Always run accumulated buffers through AVAudioConverter before passing to whisper. Store the input format from the first buffer received.
**Warning signs:** Transcription returns nonsense text or empty results despite clear speech.

### Pitfall 3: whisper.spm Unsafe Build Flags
**What goes wrong:** SPM dependency resolution fails with "unsafe build flags" error.
**Why it happens:** whisper.spm uses C compiler flags that SPM considers unsafe by default.
**How to avoid:** Set dependency rule to **branch: master** (not a version tag) in Xcode's package manager.
**Warning signs:** Build errors mentioning "unsafe flags" during package resolution.

### Pitfall 4: CGEventTap Disabling Itself
**What goes wrong:** After a few seconds, the CGEventTap stops receiving events.
**Why it happens:** macOS disables event taps that take too long to process events (timeout mechanism).
**How to avoid:** Keep the tap callback fast (nanosecond-level). Never do transcription or heavy work inside the callback. Just set a flag and dispatch to main queue. If the tap gets disabled, re-enable it with `CGEvent.tapEnable(tap:, enable: true)`.
**Warning signs:** Spacebar stops being intercepted after working initially.

### Pitfall 5: Memory Pressure from Audio Buffer Accumulation
**What goes wrong:** Long recordings accumulate large amounts of audio data in memory.
**Why it happens:** At 48kHz stereo Float32, audio is ~384 KB/sec (~23 MB/min).
**How to avoid:** For the 60-second silence timeout, worst case is ~23 MB which is acceptable. If longer recordings are needed later (Phase 5 segmentation), switch to temp-file storage. For now, in-memory is fine.
**Warning signs:** Memory warnings on very long recordings (not an issue with 60s timeout).

### Pitfall 6: Auto-Paste Race Condition
**What goes wrong:** Cmd+V paste fires before the clipboard write completes, pasting the previous clipboard content.
**Why it happens:** NSPasteboard.setString is synchronous but the CGEvent post is also near-instant.
**How to avoid:** Ensure clipboard write completes before posting the CGEvent. Add the 50-100ms delay specified in the user decisions between clipboard write and paste simulation.
**Warning signs:** Previous clipboard content appears instead of transcription.

### Pitfall 7: Whisper Model Not Found at Runtime
**What goes wrong:** App crashes or fails silently when the model file is missing.
**Why it happens:** Model is ~466 MB and may not be bundled correctly, or download fails.
**How to avoid:** Check for model file existence at startup. Show clear error state if missing. Consider bundling in the app bundle for v1 simplicity (increases app size but eliminates download complexity).
**Warning signs:** whisper_init_from_file_with_params returns nil.

## Code Examples

### Clipboard Write (Verified Pattern)
```swift
// Source: Apple NSPasteboard documentation
func writeToClipboard(_ text: String) -> Bool {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.setString(text, forType: .string)
}
```

### RecordingState Enum Expansion
```swift
// Expanding existing RecordingState.swift
enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case success(text: String)
    case failure(reason: FailureReason)

    enum FailureReason: Equatable {
        case noSpeechDetected
        case modelError(String)
        case silenceTimeout
    }

    var isTerminal: Bool {
        switch self {
        case .success, .failure: return true
        default: return false
        }
    }
}
```

### Silence Detection Extension
```swift
// Extend AudioLevelMonitor for silence tracking
extension AudioLevelMonitor {
    // Track consecutive silence duration
    // RMS level below threshold (e.g., normalized level < 0.01) counts as silence
    // Timer fires every ~1s to check accumulated silence
    // At 45s: trigger warning callback
    // At 60s: trigger auto-stop callback
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Apple SFSpeechRecognizer | whisper.cpp local inference | 2023+ | Full offline, better punctuation, no Apple API limits |
| whisper.spm (ggerganov) | whisper.cpp native Package.swift (partial) | 2024-2025 | whisper.spm still works but will be archived; native SPM is incomplete |
| NSAppleScript for paste | CGEvent posting | Long-standing | Lower latency, no shell process, direct HID event injection |
| SwiftWhisper wrapper | Direct whisper.cpp C API | 2024+ | SwiftWhisper last updated Aug 2023; direct C API is more current and controllable |

**Deprecated/outdated:**
- `ggerganov/whisper.spm`: Will be archived soon. Still functional for now via branch: master. Plan to migrate to whisper.cpp native Package.swift when available.
- `exPHAT/SwiftWhisper`: Last updated August 2023, v1.2.0. Bundles an old whisper.cpp commit. Not recommended for new projects.

## Open Questions

1. **Model Bundling Strategy**
   - What we know: ggml-small.en.bin is ~466 MB. Can be bundled in app or downloaded on first launch.
   - What's unclear: Whether Xcode/App Store allows a ~500 MB bundled resource without complaints. For a single-user utility not going to the App Store, bundling is simplest.
   - Recommendation: Bundle the model in the app's Resources folder for v1. Add a download fallback later if distribution size becomes a concern.

2. **CGEventTap vs Existing KeyboardShortcuts Library**
   - What we know: HotkeyService uses KeyboardShortcuts (Carbon hot key API). Spacebar cannot be registered as a Carbon hot key alone. CGEventTap is needed for spacebar interception.
   - What's unclear: Whether having both a Carbon hot key listener AND a CGEventTap active simultaneously causes conflicts.
   - Recommendation: Keep KeyboardShortcuts for the activation hotkey. Add a separate CGEventTap solely for spacebar interception, activated only during .recording state. The two mechanisms operate at different levels and should not conflict.

3. **whisper.spm Archival Timeline**
   - What we know: The repo states it "will soon be archived." The direct whisper.cpp Package.swift is incomplete.
   - What's unclear: Exact archival date. Whether whisper.cpp will have full SPM support before whisper.spm is archived.
   - Recommendation: Use whisper.spm now. When it is archived, the existing dependency will still compile from the pinned commit. Migration to native whisper.cpp SPM can happen in a future phase.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (bundled with Xcode) |
| Config file | Speech2Test.xcodeproj (Xcode-managed) |
| Quick run command | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -only-testing Speech2TestTests -destination 'platform=macOS'` |
| Full suite command | `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -destination 'platform=macOS'` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SESS-01 | Spacebar during recording triggers finish flow | unit | `xcodebuild test -only-testing Speech2TestTests/SpacebarInterceptorTests -destination 'platform=macOS'` | Wave 0 |
| TRNS-01 | WhisperService transcribes Float32 audio samples | unit | `xcodebuild test -only-testing Speech2TestTests/WhisperServiceTests -destination 'platform=macOS'` | Wave 0 |
| TRNS-02 | Transcription output includes punctuation | unit | `xcodebuild test -only-testing Speech2TestTests/WhisperServiceTests -destination 'platform=macOS'` | Wave 0 |
| TRNS-06 | Empty transcription produces failure state, not success | unit | `xcodebuild test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | Existing (needs expansion) |
| CLIP-01 | Successful transcription writes to NSPasteboard | unit | `xcodebuild test -only-testing Speech2TestTests/ClipboardServiceTests -destination 'platform=macOS'` | Wave 0 |
| FEED-01 | State transitions produce correct RecordingState values | unit | `xcodebuild test -only-testing Speech2TestTests/ActivationStoreTests -destination 'platform=macOS'` | Existing (needs expansion) |
| FEED-03 | Indicator visibility toggle hides pill but menu bar icon still updates | unit | `xcodebuild test -only-testing Speech2TestTests/ShellPreferencesPhase3Tests -destination 'platform=macOS'` | Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -only-testing Speech2TestTests -destination 'platform=macOS'`
- **Per wave merge:** `xcodebuild test -project Speech2Test.xcodeproj -scheme Speech2Test -destination 'platform=macOS'`
- **Phase gate:** Full suite green before `$gsd-verify-work`

### Wave 0 Gaps
- [ ] `Speech2TestTests/SpacebarInterceptorTests.swift` -- covers SESS-01 (spacebar interception logic, not actual CGEventTap in CI)
- [ ] `Speech2TestTests/WhisperServiceTests.swift` -- covers TRNS-01, TRNS-02 (mock-based; real model tests require bundled model)
- [ ] `Speech2TestTests/ClipboardServiceTests.swift` -- covers CLIP-01 (NSPasteboard write verification)
- [ ] `Speech2TestTests/ShellPreferencesPhase3Tests.swift` -- covers FEED-03 (new preference keys)
- [ ] `Speech2TestTests/AudioBufferAccumulatorTests.swift` -- covers buffer accumulation and format conversion logic
- [ ] Expand `ActivationStoreTests.swift` -- covers TRNS-06, FEED-01 (new state transitions: processing, success, failure)

**Note:** CGEventTap and real whisper model tests require hardware/permissions and cannot run in headless CI. Unit tests should use protocol abstractions and mocks for these components.

## Sources

### Primary (HIGH confidence)
- [whisper.cpp repository](https://github.com/ggml-org/whisper.cpp) - v1.8.1, C API, model format, Metal/CoreML support
- [whisper.cpp LibWhisper.swift example](https://github.com/ggml-org/whisper.cpp/blob/master/examples/whisper.swiftui/whisper.cpp.swift/LibWhisper.swift) - Official Swift integration pattern using actor isolation
- [Apple NSPasteboard documentation](https://developer.apple.com/documentation/appkit/nspasteboard) - Clipboard write API
- [Apple TN3136 AVAudioConverter](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions) - Sample rate conversion patterns
- [Apple CGEvent.tapCreate documentation](https://developer.apple.com/documentation/coregraphics/cgevent/1454426-tapcreate) - Event tap creation and swallowing
- [Apple addGlobalMonitorForEvents documentation](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)) - Confirms global monitors cannot swallow events

### Secondary (MEDIUM confidence)
- [ggerganov/whisper.spm](https://github.com/ggerganov/whisper.spm) - SPM wrapper, will be archived, use branch: master
- [Maccy Clipboard.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift) - CGEvent paste simulation pattern (open source clipboard manager)
- [Hugging Face whisper.cpp models](https://huggingface.co/ggerganov/whisper.cpp) - Model download URLs, ggml-small.en.bin ~466 MB
- [Apple Developer Forums - CGEvent paste](https://developer.apple.com/forums/thread/659804) - Cmd+V simulation patterns and gotchas

### Tertiary (LOW confidence)
- whisper.spm archival timeline - stated "soon" but no date given; could be weeks or months

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - whisper.cpp, NSPasteboard, CGEventTap are well-documented, stable APIs
- Architecture: HIGH - patterns drawn from official whisper.cpp Swift example and established macOS patterns
- Pitfalls: MEDIUM-HIGH - most verified via official docs; CGEventTap edge cases from community reports
- whisper.spm longevity: LOW - archival notice without timeline; functional today

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (30 days; whisper.spm status should be rechecked if starting later)
