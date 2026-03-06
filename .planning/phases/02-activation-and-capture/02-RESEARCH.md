# Phase 2: Activation and Capture - Research

**Researched:** 2026-03-05
**Domain:** macOS system-wide hotkey registration, CGEventTap, AVAudioEngine microphone capture, NSPanel floating UI
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Hotkey configuration lives in the existing setup window (Phase 1) as a new section — not a separate Preferences window.
- Interaction pattern: click-to-record field (user clicks the field, presses desired key combo, field captures it — like Raycast/Alfred).
- The hotkey field is always editable, not locked to the initial setup flow. User can re-record a new combo at any time.
- Default hotkey: **Cmd+Shift+Z**, pre-filled. User can change it but is not required to.
- Default tap mode on first launch: **double-tap**.
- Single-tap vs double-tap toggle lives in the setup/settings window alongside the hotkey field.
- In double-tap mode, a stray single tap is silently ignored — no feedback, no action.
- The inter-tap detection window is a fixed sensible default (not user-configurable in v1).
- Device picker: user can choose a specific input device from a list of available mics.
- Picker lives in the setup/settings window (alongside hotkey and tap mode).
- Default selection: "System Default" option at the top of the picker — follows whatever the OS default input is.
- If the selected mic disconnects during use, fall back to the system default silently (no error, no interruption).
- Menu bar icon changes to a recording variant when activation fires and recording is armed.
- Optional activation sound (a brief, subtle tone to confirm recording started), toggleable in the setup/settings window.
- Sound is **on by default**. User can disable in settings.
- A small pill/capsule floating at the **bottom center of the screen**, above all windows.
- Shows: mic icon + live audio waveform animation reflecting input levels.
- Appears on all Spaces/desktops (not just the active Space).
- Floats above all other windows including full-screen apps (NSPanel or high window level).
- **Read-only in Phase 2** — no interactive controls. Cancel/finish interactions are Phase 3.

### Claude's Discretion

- Exact visual design of the pill indicator (size, corner radius, blur backdrop, colors).
- Exact waveform animation style (bars vs line vs dots — as long as it reflects actual input levels).
- Exact recording-state menu bar icon variant.
- Exact sound clip used for the activation tone.
- Specific inter-tap window duration (suggested: 350ms).
- How hotkey conflicts with system shortcuts are reported to the user.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ACTV-01 | User can configure a system-wide activation hotkey | KeyboardShortcuts library provides Recorder UI + CGEventTap-based global monitoring; ShellPreferences extended with hotkey/tapMode keys |
| ACTV-02 | User can start recording with single tap when single-tap mode is enabled | CGEventTap event loop in HotkeyService detects keyDown + checks `tapMode == .single`; arms ActivationStore |
| ACTV-03 | User can start recording with double tap when double-tap mode is enabled | HotkeyService tracks first-tap timestamp; `DispatchWorkItem` fires at 350ms; second arrival within window triggers recording |
| ACTV-04 | User can begin speaking immediately after activation without a second confirmation step | AVAudioEngine.prepare() called at startup so start() latency is < 50ms; engine is kept prepared, not torn down between sessions |
| AUDI-01 | User can record speech from the system microphone through a continuous audio stream | AVAudioEngine inputNode.installTap delivers PCM buffers; engine started on arm, stopped on finish |
| AUDI-02 | User can choose which microphone input device is used for dictation | CoreAudio enumeration via AudioObjectGetPropertyData + kAudioHardwarePropertyDevices; set device via kAudioOutputUnitProperty_CurrentDevice on inputNode.audioUnit |
| AUDI-03 | User can keep system audio playback uninterrupted while dictating | installTap on inputNode only (no connection to outputNode/mixer); correct AVAudioSession category on macOS avoids output interruption |
| CONF-03 | User can choose whether activation uses single-tap or double-tap mode | Toggle in SetupWindowView Activation section; persisted in ShellPreferences |
</phase_requirements>

---

## Summary

Phase 2 requires three distinct technical capabilities: (1) global hotkey registration with tap-mode detection, (2) microphone capture via AVAudioEngine with per-device selection, and (3) a floating overlay panel that appears on all Spaces including full-screen mode. Each has a clear idiomatic Apple-platform solution; none requires building from scratch.

For hotkey registration, `CGEventTap` is the correct low-level mechanism: it can consume events (preventing system beep), works when the app is in the background, and integrates cleanly with the `AXIsProcessTrusted()` / `CGPreflightListenEventAccess()` that Phase 1 already gates on. The existing `KeyboardPermissionService` already calls `CGPreflightListenEventAccess()` and `CGRequestListenEventAccess()`, so the permission side is already handled. For the recorder UI field (click-to-record), **`KeyboardShortcuts`** (sindresorhus) provides a drop-in `KeyboardShortcuts.Recorder` SwiftUI view that handles the UI, storage, and conflict detection — avoiding hand-rolling a custom NSViewRepresentable.

For audio, `AVAudioEngine` with `inputNode.installTap` is the correct pattern. Keeping the tap on the inputNode only (never connecting input to the output node/mixer) preserves system audio playback. Device selection for named microphones requires dropping down to CoreAudio's `AudioObjectGetPropertyData` / `kAudioOutputUnitProperty_CurrentDevice` APIs; `AVAudioEngine` does not expose device selection at a higher level on macOS.

**Primary recommendation:** Use `KeyboardShortcuts` for hotkey recording UI, hand-written `CGEventTap` for global event monitoring + double-tap detection, `AVAudioEngine` + `installTap` for audio capture, and an `NSPanel` subclass with `[.canJoinAllSpaces, .fullScreenAuxiliary]` and `.floating` window level for the recording indicator.

---

## Standard Stack

### Core

| Library / API | Version | Purpose | Why Standard |
|---|---|---|---|
| `CGEventTap` (CoreGraphics) | macOS 10.4+ | Global keyboard event interception | Only API that can consume events (no system beep); works background; permission model matches Phase 1 setup |
| `AVAudioEngine` (AVFoundation) | macOS 10.10+ | Microphone stream capture | Apple's current high-level audio graph API; supports installTap for real-time buffer access |
| `CoreAudio` (AudioToolbox) | macOS 10.0+ | Device enumeration + device selection | Required for non-default input device selection; no higher-level API exists on macOS |
| `NSPanel` (AppKit) | macOS | Floating recording indicator window | Subclass of NSWindow with key-without-main semantics; correct type for auxiliary overlays |
| `AudioToolbox` | macOS | Activation sound playback | `AudioServicesCreateSystemSoundID` + `AudioServicesPlaySystemSound` — simplest API for short one-shot sounds |

### Supporting

| Library | Version | Purpose | When to Use |
|---|---|---|---|
| `KeyboardShortcuts` (sindresorhus) | Latest (Swift Package) | Recorder UI field (click-to-record) | Provides `KeyboardShortcuts.Recorder` SwiftUI view with built-in conflict detection and UserDefaults storage |
| `Combine` / `async/await` | macOS 12+ | Reactive state propagation for recording state | Already used in project; `@Published` + `@MainActor` pattern established |
| `Accelerate` (vDSP) | macOS | RMS level computation for waveform animation | Efficient magnitude calculation from PCM buffer data |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| `CGEventTap` | `NSEvent.addGlobalMonitorForEvents` | NSEvent cannot consume/swallow events — causes system beep when app is background. NSEvent is simpler but incorrect for this use case. |
| `KeyboardShortcuts` library | Custom NSViewRepresentable key recorder | Hand-rolling requires reimplementing conflict detection, key display, UserDefaults serialization, and edge cases (modifier-only, media keys). KeyboardShortcuts has maintained this for years. |
| `CoreAudio` device selection | `AVAudioSession.setPreferredInput` | `AVAudioSession` is iOS API. On macOS, input node device must be set via `AudioUnitSetProperty` on the underlying AudioUnit. |
| `NSPanel` | SwiftUI `.windowLevel(.floating)` modifier | SwiftUI 2024 introduced window level modifiers but the project uses AppKit window management via AppDelegate; NSPanel subclass fits the existing pattern. |

### Installation

```bash
# Via Xcode: File > Add Package Dependencies
# URL: https://github.com/sindresorhus/KeyboardShortcuts
# Version: latest (1.x)
```

No other external dependencies are needed — all other APIs are system frameworks.

---

## Architecture Patterns

### Recommended Project Structure

```
Speech2Test/
├── Activation/
│   ├── ActivationStore.swift          # @MainActor ObservableObject — recording state machine
│   ├── HotkeyService.swift            # CGEventTap lifecycle, double-tap timer logic
│   └── RecordingState.swift           # enum: idle / armed / recording
├── Audio/
│   ├── AudioCaptureService.swift      # AVAudioEngine wrapper — start/stop/tap
│   ├── AudioDeviceService.swift       # CoreAudio device enumeration + selection
│   └── AudioLevelMonitor.swift        # RMS level publisher for waveform view
├── Persistence/
│   └── ShellPreferences.swift         # EXTEND — add hotkey, tapMode, micDevice, activationSound keys
├── Shell/
│   ├── SetupWindowView.swift          # EXTEND — add Activation settings section
│   ├── RecordingPillView.swift        # SwiftUI content for pill indicator
│   └── RecordingPillPanel.swift       # NSPanel subclass, floating, all Spaces
└── App/
    └── AppDelegate.swift              # EXTEND — create/show/hide RecordingPillPanel
```

### Pattern 1: ActivationStore — State Machine

**What:** `@MainActor ObservableObject` that owns `RecordingState` and coordinates between `HotkeyService` and `AudioCaptureService`. Follows the established `ReadinessStore` pattern.

**When to use:** Any component that needs to react to recording state (menu bar icon, pill panel, audio engine start/stop).

```swift
// Pattern — follows ReadinessStore convention
@MainActor
final class ActivationStore: ObservableObject {
    static let shared = ActivationStore(...)

    @Published private(set) var state: RecordingState = .idle

    func arm() { ... }    // called by HotkeyService on valid tap
    func stop() { ... }   // called by session finish (Phase 3)
}

enum RecordingState {
    case idle
    case recording
}
```

### Pattern 2: CGEventTap with Double-Tap Detection

**What:** A `HotkeyService` struct/class that creates a `CGEventTap`, runs it on a dedicated run loop, detects the registered key combo, and applies single/double-tap logic with a `DispatchWorkItem` timer.

**When to use:** All activation signal routing goes through here.

```swift
// Source: CGEventTap C API (CoreGraphics)
// Pattern for double-tap detection

private var lastTapTime: CFAbsoluteTime = 0
private var pendingTapWork: DispatchWorkItem?
private let doubleTapWindow: CFAbsoluteTime = 0.350  // 350ms

func handleKeyDown(event: CGEvent) -> Bool {
    let now = CFAbsoluteTimeGetCurrent()
    let elapsed = now - lastTapTime
    lastTapTime = now

    if tapMode == .single {
        activationStore.arm()
        return true
    }

    // double-tap mode
    if elapsed < doubleTapWindow {
        pendingTapWork?.cancel()
        pendingTapWork = nil
        activationStore.arm()
        return true
    }

    // first tap — schedule silent timeout
    pendingTapWork?.cancel()
    let work = DispatchWorkItem { /* silently discard */ }
    pendingTapWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
    return true  // consume event — no beep, no pass-through
}
```

**CGEventTap lifecycle (C callback pattern):**

```swift
// Source: CGEventTap documentation (CoreGraphics)
private static var tap: CFMachPort?

static func install(handler: HotkeyService) -> Bool {
    guard CGPreflightListenEventAccess() else { return false }

    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    // Pass handler via userInfo (Unmanaged) — required for C callback
    let ptr = Unmanaged.passRetained(handler).toOpaque()

    tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
            guard type == .keyDown else {
                if type == .tapDisabledByTimeout {
                    // Re-enable tap
                    CGEvent.tapEnable(tap: proxy, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            let service = Unmanaged<HotkeyService>.fromOpaque(userInfo!).takeUnretainedValue()
            let consumed = service.handleKeyDown(event: event)
            return consumed ? nil : Unmanaged.passUnretained(event)
        },
        userInfo: ptr
    )

    guard let tap else { return false }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
}
```

**CRITICAL:** Always handle `kCGEventTapDisabledByTimeout` — macOS disables taps that are slow. Re-enable immediately.

### Pattern 3: AVAudioEngine Microphone Tap

**What:** `AudioCaptureService` wraps `AVAudioEngine`. On `start()`, install tap on `inputNode`, prepare, and start engine. On `stop()`, remove tap and stop engine.

**When to use:** Called by `ActivationStore` when state transitions to `.recording`.

```swift
// Source: AVAudioEngine documentation + Apple Developer Forums
// Key: tap inputNode ONLY — do not connect input to outputNode

final class AudioCaptureService {
    private let engine = AVAudioEngine()

    func start(onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            onBuffer(buffer, time)
        }

        try engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
```

### Pattern 4: CoreAudio Device Enumeration + Selection

**What:** `AudioDeviceService` uses `AudioObjectGetPropertyData` to list all devices with input channels, then sets the chosen device on the engine's input AudioUnit.

**When to use:** Populating the mic picker in SetupWindowView; applying selection when recording starts.

```swift
// Source: CoreAudio HAL, gist by SteveTrewick, AudioKit source
import CoreAudio

struct AudioInputDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

func enumerateInputDevices() -> [AudioInputDevice] {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)

    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)

    return deviceIDs.compactMap { deviceID in
        // Filter to devices with input channels
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var inputSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize)
        guard inputSize > 0 else { return nil }

        // Get name
        var nameRef: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef)
        return AudioInputDevice(id: deviceID, name: nameRef as String, uid: "")
    }
}

// Apply device to engine (call before engine.start())
func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) throws {
    var deviceID = deviceID
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let err = AudioUnitSetProperty(
        engine.inputNode.audioUnit!,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        size
    )
    if err != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(err)) }
}
```

### Pattern 5: Floating NSPanel on All Spaces

**What:** An `NSPanel` subclass hosted with `NSHostingView<RecordingPillView>`. Configured with `.floating` level and `[.canJoinAllSpaces, .fullScreenAuxiliary]` collection behavior.

**When to use:** Created once in `AppDelegate`; shown/hidden in response to `ActivationStore.state`.

```swift
// Source: Cindori floating panel guide, Apple docs NSWindow.CollectionBehavior
final class RecordingPillPanel: NSPanel {
    init(content: RecordingPillView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = false
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        contentView = NSHostingView(rootView: content)

        // Position: bottom center of main screen
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.minY + 40   // 40pt above dock
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

**Show/hide from AppDelegate:**

```swift
// In AppDelegate, observing activationStore.$state
private var pillPanel: RecordingPillPanel?

private func updatePillVisibility(for state: RecordingState) {
    switch state {
    case .idle:
        pillPanel?.orderOut(nil)
    case .recording:
        pillPanel?.orderFrontRegardless()
    }
}
```

### Pattern 6: Live Level Metering for Waveform

**What:** In the `installTap` callback, compute RMS using `vDSP_rmsqv` from the PCM buffer, publish via `@Published` on main thread.

**When to use:** `RecordingPillView` reads the level to drive bar/dot animation.

```swift
// Source: Accelerate framework vDSP
import Accelerate

func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData?[0] else { return 0 }
    let frameLength = vDSP_Length(buffer.frameLength)
    var rms: Float = 0
    vDSP_rmsqv(channelData, 1, &rms, frameLength)
    return rms
}
```

### Pattern 7: Activation Sound

**What:** A short custom audio file (`.aiff` or `.caf`, ≤ 30s) bundled in the app and played via `AudioServicesPlaySystemSound`.

**When to use:** Called in `ActivationStore.arm()` when `preferences.activationSoundEnabled == true`.

```swift
// Source: AudioToolbox AudioServices
import AudioToolbox

final class ActivationSoundPlayer {
    private var soundID: SystemSoundID = 0

    init() {
        if let url = Bundle.main.url(forResource: "activation", withExtension: "aiff") {
            AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        }
    }

    func play() {
        guard soundID != 0 else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}
```

### Anti-Patterns to Avoid

- **Do not connect `inputNode` to `outputNode`**: This routes microphone audio to system output and interrupts playback. Use `installTap` only.
- **Do not use `NSEvent.addGlobalMonitorForEvents` for hotkeys**: Cannot consume events — causes system beep when a modifier+key combo fires while app is background.
- **Do not use Carbon `RegisterEventHotKey`**: Deprecated API; avoid new dependency on Carbon framework.
- **Do not call `engine.prepare()` inside the tap callback**: Prepare once at startup or before first arm. Starting the engine on the hotkey path must be fast.
- **Do not set the CoreAudio device after `engine.start()`**: Set `kAudioOutputUnitProperty_CurrentDevice` before `engine.start()`. The engine must be stopped and restarted if the device changes mid-session.
- **Do not skip `kCGEventTapDisabledByTimeout` handling**: The OS disables slow taps silently. The callback receives a synthetic event with type `.tapDisabledByTimeout` — re-enable the tap or hotkeys stop working after first slow response.
- **Do not create the pill panel on every activation**: Create once in `AppDelegate.applicationDidFinishLaunching`, show/hide reactively.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Hotkey recorder UI (click-to-record field) | Custom NSViewRepresentable with keyDown override | `KeyboardShortcuts.Recorder` (sindresorhus) | Handles modifier-only keys, conflict detection, display formatting, UserDefaults serialization, accessibility — years of edge cases |
| Audio device enumeration | Custom AVFoundation-only approach | CoreAudio `AudioObjectGetPropertyData` | AVFoundation's `AVCaptureDevice.DiscoverySession` returns incomplete lists on macOS (misses external mics, Bluetooth, virtual devices) |
| Floating window above full-screen | Custom override of window ordering | `NSPanel` + `.fullScreenAuxiliary` + `.canJoinAllSpaces` | The collection behavior combination is the correct documented API; override approaches are fragile across OS versions |

**Key insight:** The hotkey recording UI has many subtle edge cases (Fn key, media keys, modifier-only combos, system reserved combos). KeyboardShortcuts has handled these for 5+ years; using it saves 2-3 days of edge-case work.

---

## Common Pitfalls

### Pitfall 1: CGEventTap Silently Disabled by Timeout

**What goes wrong:** After the app has been running a while or is under load, macOS disables the CGEventTap. Hotkeys stop working entirely with no error.

**Why it happens:** Apple's event tap watchdog disables taps that take too long to respond. The callback receives a synthetic event of type `kCGEventTapDisabledByTimeout`.

**How to avoid:** Always check for `kCGEventTapDisabledByTimeout` at the top of the callback and call `CGEvent.tapEnable(tap: proxy, enable: true)` immediately. Never do blocking work inside the callback.

**Warning signs:** Hotkey works at first but stops responding after a few minutes or after heavy CPU load.

### Pitfall 2: AVAudioEngine Device Selection Must Precede engine.start()

**What goes wrong:** Setting `kAudioOutputUnitProperty_CurrentDevice` on a running engine fails silently or has no effect.

**Why it happens:** The HAL audio unit locks device configuration when the engine is running.

**How to avoid:** Always stop → set device → prepare → start when switching microphones. For the "System Default" option, do not set the property at all (let the engine use its default).

**Warning signs:** User picks a different microphone but recording continues from old device.

### Pitfall 3: AVAudioEngine installTap Format Mismatch

**What goes wrong:** `EXC_BAD_ACCESS` crash or `AVAudioEngineConfigurationChange` when installing a tap with a mismatched format.

**Why it happens:** The format passed to `installTap(onBus:bufferSize:format:)` must match `inputNode.outputFormat(forBus: 0)` or be `nil`.

**How to avoid:** Always obtain the format from the node at install time: `let format = inputNode.outputFormat(forBus: 0)`.

**Warning signs:** Crash on engine start immediately after installing tap.

### Pitfall 4: CGEventTap and Swift Closure Capture (Memory)

**What goes wrong:** Crash or use-after-free when the event tap fires after the service is deallocated.

**Why it happens:** CGEventTap uses a C callback with `UnsafeMutableRawPointer` userInfo. The object must remain alive for the tap lifetime.

**How to avoid:** Use `Unmanaged.passRetained` when creating the tap, and explicitly `release()` in `deinit` when tearing down the tap.

### Pitfall 5: NSPanel and Full-Screen Apps — Both Behaviors Required

**What goes wrong:** Panel appears on all normal Spaces but disappears behind full-screen apps.

**Why it happens:** `.canJoinAllSpaces` alone does not grant auxiliary status on a Space occupied by a full-screen app. You need `.fullScreenAuxiliary` as well.

**How to avoid:** Set `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. Additionally, `level = .floating` must be set — collection behavior alone does not control z-order.

**Warning signs:** Pill indicator works on desktop but vanishes when user is in a full-screen app.

### Pitfall 6: ShellPreferences Hotkey Persistence Format

**What goes wrong:** Hotkey combo cannot be restored on relaunch because key code + modifier flags are not serialized atomically.

**Why it happens:** `KeyboardShortcuts` already handles UserDefaults serialization if you use its `Name`-based API. If you bypass this and store raw key codes manually, the format must be well-defined.

**How to avoid:** Let `KeyboardShortcuts` own the stored shortcut. Do NOT store duplicate copies in `ShellPreferences`. Phase 2 preferences (`tapMode`, `micDeviceUID`, `activationSoundEnabled`) go in `ShellPreferences`; the shortcut itself stays in `KeyboardShortcuts`' storage.

---

## Code Examples

Verified patterns from official sources and well-maintained libraries:

### Installing a CGEventTap (CoreGraphics)

```swift
// Source: CoreGraphics CGEventTap documentation
let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
guard let tap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: myCallback,
    userInfo: userInfoPtr
) else { /* permission denied or failed */ return }

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
```

### AVAudioEngine Tap (AVFoundation)

```swift
// Source: AVAudioEngine documentation
let inputNode = engine.inputNode
let format = inputNode.outputFormat(forBus: 0)
inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
    // process buffer — runs on audio thread, dispatch to main if needed
}
engine.prepare()
try engine.start()
```

### KeyboardShortcuts Recorder (SwiftUI)

```swift
// Source: sindresorhus/KeyboardShortcuts README
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let activate = Self("activate", default: .init(.z, modifiers: [.command, .shift]))
}

// In SetupWindowView:
KeyboardShortcuts.Recorder("Activation Hotkey:", name: .activate)

// In HotkeyService:
KeyboardShortcuts.onKeyDown(for: .activate) { [weak self] in
    self?.handleActivation()
}
```

**Note on KeyboardShortcuts:** While this library uses Carbon APIs internally, it is Mac App Store compatible, actively maintained, and is the de-facto standard used by Raycast, Alfred, and many others. It eliminates the need to hand-roll a custom Recorder UI.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| Carbon `RegisterEventHotKey` | `CGEventTap` + `KeyboardShortcuts` library | ~2015 | Carbon is not recommended for new code; CGEventTap is the modern low-level approach |
| `NSEvent.addGlobalMonitorForEvents` | `CGEventTap` | Always was different | NSEvent cannot consume — use CGEventTap for non-passthrough |
| `AVAudioSession` (iOS API) for device selection | `CoreAudio AudioObjectGetPropertyData` | N/A (macOS-specific) | AVAudioSession is iOS-only; macOS requires CoreAudio HAL |
| `AVCaptureDevice.DiscoverySession` for mic list | CoreAudio enumeration | Always incomplete on macOS | AVCaptureDevice misses external and virtual devices on macOS |
| SwiftUI `.windowLevel` modifier | NSPanel subclass (still valid pattern) | macOS 15 / WWDC24 | New SwiftUI API exists but project uses AppDelegate window management — NSPanel fits established pattern |

**Deprecated/outdated:**
- Carbon `RegisterEventHotKey`: Avoid in all new code. Still technically works but creates Carbon framework dependency.
- `AVAudioSession.setPreferredInput`: iOS-only. Do not use on macOS.

---

## Open Questions

1. **KeyboardShortcuts vs. raw CGEventTap for hotkey activation**
   - What we know: `KeyboardShortcuts` provides a recorder UI and stores the shortcut. Its event delivery uses Carbon internally. Raw `CGEventTap` is the clean modern path for the listening side.
   - What's unclear: Whether to use `KeyboardShortcuts.onKeyDown(for:)` for the firing side (which removes the need to write a raw CGEventTap) or write the tap ourselves for full double-tap control.
   - Recommendation: Use `KeyboardShortcuts.Recorder` for the UI only. Implement a custom `CGEventTap` for the activation monitoring side to get full double-tap timing control and explicit event consumption.

2. **AVAudioEngine "keep warm" vs. start-on-demand**
   - What we know: `engine.prepare()` pre-allocates resources; `engine.start()` after prepare is fast (< 50ms empirically). Keeping engine running continuously uses battery.
   - What's unclear: Whether the latency of cold-start (without pre-prepare) is acceptable for ACTV-04 ("speak immediately after activation").
   - Recommendation: Call `engine.prepare()` at app launch (after permissions confirmed ready). On arm, call `engine.start()` — this should be fast enough. Tear down on `stop()` to release resources between sessions.

3. **Mic device fallback on disconnect**
   - What we know: Decision states "fall back to system default silently." CoreAudio sends `kAudioDevicePropertyDeviceIsAlive` property change notifications when a device disconnects.
   - What's unclear: Whether AVAudioEngine automatically handles this or requires explicit re-start with default device.
   - Recommendation: Register `kAudioDevicePropertyDeviceIsAlive` listener in `AudioDeviceService`. On disconnect, call `stop()` + set deviceID to system default + `start()` without surfacing any error to the UI.

---

## Validation Architecture

Nyquist validation is enabled. Framework in use: **XCTest** (existing, 9 tests passing in Phase 1).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (no config file — standard Xcode test target) |
| Config file | None — Xcode test scheme |
| Quick run command | `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' -testPlan Speech2Test 2>&1 \| tail -20` |
| Full suite command | `xcodebuild test -scheme Speech2Test -destination 'platform=macOS' 2>&1 \| tail -30` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ACTV-01 | Hotkey name default is Cmd+Shift+Z | unit | `xcodebuild test ... -only-testing:Speech2TestTests/HotkeyServiceTests` | ❌ Wave 0 |
| ACTV-02 | Single-tap mode arms activation on first press | unit | `xcodebuild test ... -only-testing:Speech2TestTests/ActivationStoreTests` | ❌ Wave 0 |
| ACTV-03 | Double-tap within 350ms window arms activation | unit | `xcodebuild test ... -only-testing:Speech2TestTests/ActivationStoreTests` | ❌ Wave 0 |
| ACTV-03 | Single tap in double-tap mode is silently ignored | unit | `xcodebuild test ... -only-testing:Speech2TestTests/ActivationStoreTests` | ❌ Wave 0 |
| ACTV-04 | Recording state transitions to `.recording` synchronously on arm | unit | `xcodebuild test ... -only-testing:Speech2TestTests/ActivationStoreTests` | ❌ Wave 0 |
| AUDI-01 | AudioCaptureService starts engine and receives buffers | integration | manual / simulator limited | manual-only (requires mic hardware) |
| AUDI-02 | AudioDeviceService enumerates devices with input channels | unit | `xcodebuild test ... -only-testing:Speech2TestTests/AudioDeviceServiceTests` | ❌ Wave 0 |
| AUDI-02 | Setting a specific device ID updates the engine's input | integration | manual-only | manual-only (requires hardware) |
| AUDI-03 | installTap on inputNode does not connect to outputNode | unit | inspect engine graph in test | ❌ Wave 0 |
| CONF-03 | ShellPreferences persists tapMode toggle | unit | `xcodebuild test ... -only-testing:Speech2TestTests/ShellPreferencesTests` | ❌ Wave 0 |
| CONF-03 | ShellPreferences persists activationSoundEnabled | unit | same as above | ❌ Wave 0 |

**Manual-only justifications:**
- AUDI-01 (microphone stream): Requires real hardware; cannot be exercised in headless CI without a physical mic.
- AUDI-02 (device selection): Requires real CoreAudio devices to set properties on; stub testing verifies the call pattern only.

### Sampling Rate

- **Per task commit:** Run affected test class only (e.g., `ActivationStoreTests`, `ShellPreferencesTests`)
- **Per wave merge:** Full suite — `xcodebuild test -scheme Speech2Test -destination 'platform=macOS'`
- **Phase gate:** Full suite green + manual smoke (hotkey fires, pill appears, mic records) before `$gsd-verify-work`

### Wave 0 Gaps

- [ ] `Speech2TestTests/ActivationStoreTests.swift` — covers ACTV-02, ACTV-03, ACTV-04
- [ ] `Speech2TestTests/HotkeyServiceTests.swift` — covers ACTV-01, double-tap timer logic (injectable clock)
- [ ] `Speech2TestTests/AudioDeviceServiceTests.swift` — covers AUDI-02 enumeration (mockable CoreAudio adapter)
- [ ] `Speech2TestTests/ShellPreferencesPhase2Tests.swift` — covers CONF-03, micDeviceUID, activationSoundEnabled persistence
- [ ] `Speech2TestTests/AudioCaptureServiceTests.swift` — covers AUDI-03 (engine graph inspection, no actual mic needed)

---

## Sources

### Primary (HIGH confidence)
- CoreGraphics `CGEventTap` documentation — event tap creation, callback pattern, timeout handling
- AVAudioEngine Apple Developer Documentation — `installTap`, `inputNode`, `prepare`, `start`
- `NSWindow.CollectionBehavior` Apple Developer Documentation — `.canJoinAllSpaces`, `.fullScreenAuxiliary`
- `NSPanel` Apple Developer Documentation — auxiliary window type, key/main behavior
- AudioToolbox `AudioServicesPlaySystemSound` Apple Developer Documentation
- CoreAudio HAL `kAudioHardwarePropertyDevices`, `kAudioOutputUnitProperty_CurrentDevice` documentation

### Secondary (MEDIUM confidence)
- [sindresorhus/KeyboardShortcuts GitHub README](https://github.com/sindresorhus/KeyboardShortcuts) — SwiftUI Recorder API, SPM URL, Mac App Store compatibility confirmed
- [Cindori floating panel guide](https://cindori.com/developer/floating-panel) — NSPanel subclass pattern with SwiftUI, `.fullScreenAuxiliary` collection behavior confirmed
- [Level Up Coding: CGEventTap vs NSEvent comparison](https://levelup.gitconnected.com/swiftui-macos-detect-listen-to-global-key-events-two-ways-df19e565793d) — event consumption differences confirmed
- [SteveTrewick CoreAudio gist](https://gist.github.com/SteveTrewick/c0668ee438eb784cbc5fb4674f0c2cd1) — `AudioObjectGetPropertyData` device enumeration pattern

### Tertiary (LOW confidence)
- General AVAudioEngine device selection via `kAudioOutputUnitProperty_CurrentDevice` — multiple forum threads confirm the pattern but authoritative Apple docs do not have a clean example; real-device validation recommended

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all primary APIs are Apple system frameworks with decades of stability; KeyboardShortcuts is widely deployed
- Architecture: HIGH — follows established project patterns (ReadinessStore, AppDelegate, ShellPreferences); adapts verified patterns from reputable sources
- Pitfalls: HIGH — all pitfalls verified against multiple sources (CGEventTap timeout, AVAudioEngine device format, NSPanel collection behavior)
- Device selection (CoreAudio): MEDIUM — correct API is confirmed but exact error handling for all device states should be validated on real hardware

**Research date:** 2026-03-05
**Valid until:** 2026-09-05 (stable Apple platform APIs; KeyboardShortcuts may have minor API changes — recheck if > 6 months)
