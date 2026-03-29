# Menu Bar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand `StatusMenuView` with a Start Recording button (dual hotkey hints), microphone quick-switch submenu, auto-paste toggle, renamed labels, and keyboard shortcut hints — all without touching any other part of the system.

**Architecture:** All view changes live in `StatusMenuView`. A new `HoldKeyDisplayFormatter` utility handles the Carbon keyCode → symbol conversion needed for the hold hint. `Speech2TextApp` gets one new `@StateObject` (`AudioDeviceService`) and three new closure arguments passed to `StatusMenuView`. No new services, no new stores.

**Tech Stack:** SwiftUI, KeyboardShortcuts library (`KeyboardShortcuts.Name`, `KeyboardShortcuts.getShortcut(for:)`), `AudioDeviceService` (CoreAudio), `ShellPreferences` (UserDefaults), `ActivationStore.arm()`

---

## Files

| Action | Path | Responsibility |
|---|---|---|
| Modify | `Speech2Text/Shell/StatusMenuView.swift` | All new rows, renamed labels, restructured states, hotkey hints |
| Modify | `Speech2Text/App/Speech2TextApp.swift` | Wire `startRecording`, `audioDeviceService`, `setMicDevice` |
| Create | `Speech2Text/Shell/HoldKeyDisplayFormatter.swift` | Convert Carbon keyCode + NSEvent.ModifierFlags bitmask → symbol string |
| Create | `Speech2TextTests/HoldKeyDisplayFormatterTests.swift` | Unit tests for the formatter |

---

## Key Wiring Reference

Before any task touches code, here is the exact chain for each new menu feature:

| Feature | Data source | Action target |
|---|---|---|
| Start Recording | — | `ActivationStore.arm()` via new `startRecording: () -> Void` closure |
| Hold key hint | `ShellPreferences.holdShortcutKeyCode: Int` + `holdShortcutModifiers: UInt` → `HoldKeyDisplayFormatter.symbol(keyCode:modifiers:)` | — |
| Tap key hint | `KeyboardShortcuts.getShortcut(for: .activate)` → `.key.rawValue: Int` + `.modifiers: NSEvent.ModifierFlags` | — |
| Cancel hint `⌃⇧V` | `.keyboardShortcut("v", modifiers: [.control, .shift])` | existing `cancelSession` closure |
| Microphone list | `AudioDeviceService.availableDevices: [AudioInputDevice]` (each has `.uid: String`, `.name: String`) | `preferences.micDeviceUID = uid` via new `setMicDevice: (String?) -> Void` closure |
| Selected mic | `preferences.micDeviceUID: String?` (nil = system default) | — |
| Auto-paste toggle | `preferences.alwaysAutoPaste: Bool` (@Published, persists in didSet) | `preferences.alwaysAutoPaste.toggle()` — no new closure needed, `preferences` already in the view |
| Settings hint `⌘,` | `.keyboardShortcut(",", modifiers: .command)` | existing `openSetup` closure |
| Quit hint `⌘Q` | `.keyboardShortcut("q", modifiers: .command)` | existing `quitApp` closure |

---

## Task 1: Rename Labels + Restructure Needs Setup State

**Files:**
- Modify: `Speech2Text/Shell/StatusMenuView.swift`

The current body has the Divider + copy buttons + Quit outside the `if needsSetup / else` block, so they always appear. Move the Divider and copy buttons inside the `else` (ready) branch so the Needs Setup state only shows the setup button and Quit.

Also rename:
- `"Settings — Setup Required"` → `"Setup — Permissions Required"`
- `"Settings…"` → `"Hotkeys & Settings…"` (appears in the ready branch)

- [ ] **Step 1: Replace the entire `body` in `StatusMenuView`**

Open `Speech2Text/Shell/StatusMenuView.swift` and replace the `body` computed property (lines 95–161) with:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 14) {
        if needsSetup {
            Button(action: openSetup) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Setup — Permissions Required")
                }
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityIdentifier("statusMenu.primaryAction")
        } else {
            if canCancelSession {
                Button("Cancel Session", action: cancelSession)
                    .accessibilityIdentifier("statusMenu.cancelSession")
            }

            if canRestartSession {
                Button("Restart Recording", action: restartSession)
                    .accessibilityIdentifier("statusMenu.restartSession")
            }

            if let recoveryStatusText {
                Text(recoveryStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(recoveryStatusText)
                    .accessibilityIdentifier("statusMenu.recoveryMessage")
            }

            if showsMicrophoneRecoveryAction {
                Button("Open Microphone Recovery", action: openSetup)
                    .accessibilityIdentifier("statusMenu.openMicrophoneRecovery")
            }

            if showsMicrophoneSettingsAction {
                Button("Open Microphone Settings") {
                    recoveryActionPerformer.openMicrophoneSettings()
                }
                .accessibilityIdentifier("statusMenu.openMicrophoneSettings")
            }

            Button("Hotkeys & Settings…", action: openSetup)
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityIdentifier("statusMenu.primaryAction")

            Divider()

            if lastTranscription != nil {
                Button("Copy Last Transcription", action: copyLastTranscription)
                    .accessibilityIdentifier("statusMenu.copyLastTranscription")
            }

            Button("Copy Last AI Converted Transcription",
                   action: copyLastConvertedTranscription)
                .disabled(lastConvertedTranscription == nil)
                .accessibilityIdentifier("statusMenu.copyLastConvertedTranscription")
        }

        Divider()

        Button("Quit Speech2Text", action: quitApp)
            .keyboardShortcut("q", modifiers: .command)
    }
    .padding(14)
    .frame(width: 280)
    .onAppear {
        readinessStore.refresh()
    }
}
```

- [ ] **Step 2: Build**

```
xcodebuild -scheme Speech2Text -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Speech2Text/Shell/StatusMenuView.swift
git commit -m "feat(menu): rename Settings labels and strip copy rows from needs-setup state"
```

---

## Task 2: Create HoldKeyDisplayFormatter

The hold-to-transcribe key is stored as a raw Carbon key code (`Int`) in `ShellPreferences.holdShortcutKeyCode` and an `NSEvent.ModifierFlags` bitmask (`UInt`) in `holdShortcutModifiers`. The default is keyCode `61` (right Option / ⌥), modifiers `0`.

This utility converts that pair into a display symbol string. It also exposes `keyCharacter(for:)` as an internal method so `StatusMenuView` can reuse it when rendering the tap shortcut hint from `KeyboardShortcuts.Key.rawValue`.

**Files:**
- Create: `Speech2Text/Shell/HoldKeyDisplayFormatter.swift`
- Create: `Speech2TextTests/HoldKeyDisplayFormatterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Speech2TextTests/HoldKeyDisplayFormatterTests.swift`:

```swift
import XCTest
@testable import Speech2Text

@MainActor
final class HoldKeyDisplayFormatterTests: XCTestCase {
    // Modifier-only keys
    func testRightOptionKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 61, modifiers: 0), "⌥")
    }

    func testLeftOptionKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 58, modifiers: 0), "⌥")
    }

    func testLeftCommandKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 55, modifiers: 0), "⌘")
    }

    func testRightCommandKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 54, modifiers: 0), "⌘")
    }

    func testLeftShiftKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 56, modifiers: 0), "⇧")
    }

    func testRightShiftKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 60, modifiers: 0), "⇧")
    }

    func testLeftControlKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 59, modifiers: 0), "⌃")
    }

    func testRightControlKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 62, modifiers: 0), "⌃")
    }

    func testFnKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 63, modifiers: 0), "fn")
    }

    // Regular key with modifier
    func testControlV() {
        // keyCode 9 = V, modifiers bit 18 = .control
        let controlBit: UInt = 1 << 18
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 9, modifiers: controlBit), "⌃V")
    }

    func testCommandShiftS() {
        // keyCode 1 = S, modifiers bit 20 = .command, bit 17 = .shift
        let mods: UInt = (1 << 20) | (1 << 17)
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 1, modifiers: mods), "⇧⌘S")
    }

    // Unknown key code should not crash and return non-empty string
    func testUnknownKeyCodeFallsBack() {
        let result = HoldKeyDisplayFormatter.symbol(keyCode: 999, modifiers: 0)
        XCTAssertFalse(result.isEmpty)
    }

    // keyCharacter is used by StatusMenuView for tap shortcut hints
    func testKeyCharacterForV() {
        XCTAssertEqual(HoldKeyDisplayFormatter.keyCharacter(for: 9), "V")
    }

    func testKeyCharacterForSpace() {
        XCTAssertEqual(HoldKeyDisplayFormatter.keyCharacter(for: 49), "Space")
    }

    func testKeyCharacterForUnknown() {
        XCTAssertFalse(HoldKeyDisplayFormatter.keyCharacter(for: 999).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail with compile error**

```
xcodebuild test -scheme Speech2Text -destination 'platform=macOS' \
  -only-testing:Speech2TextTests/HoldKeyDisplayFormatterTests 2>&1 | tail -20
```

Expected: compile error — `HoldKeyDisplayFormatter` not defined.

- [ ] **Step 3: Create `Speech2Text/Shell/HoldKeyDisplayFormatter.swift`**

```swift
import Foundation

enum HoldKeyDisplayFormatter {
    /// Converts a hold-to-transcribe key config into a displayable symbol string.
    /// `keyCode` is a Carbon key code (same value stored in `ShellPreferences.holdShortcutKeyCode`).
    /// `modifiers` is an NSEvent.ModifierFlags bitmask (same value stored in `holdShortcutModifiers`).
    static func symbol(keyCode: Int, modifiers: UInt) -> String {
        // Modifier-only keys: return just the modifier symbol — no prefix needed.
        switch keyCode {
        case 54, 55: return "⌘"   // right/left Command
        case 56, 60: return "⇧"   // left/right Shift
        case 58, 61: return "⌥"   // left/right Option
        case 59, 62: return "⌃"   // left/right Control
        case 63:     return "fn"
        default:
            // Regular key held with optional modifiers.
            return modifierSymbols(from: modifiers) + keyCharacter(for: keyCode)
        }
    }

    /// Returns the display character for a Carbon key code.
    /// Exposed internally so StatusMenuView can reuse it for tap-shortcut hints
    /// derived from `KeyboardShortcuts.Key.rawValue`.
    static func keyCharacter(for keyCode: Int) -> String {
        let map: [Int: String] = [
            0: "A",  1: "S",  2: "D",  3: "F",  4: "H",  5: "G",
            6: "Z",  7: "X",  8: "C",  9: "V", 11: "B", 12: "Q",
           13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O",
           32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
           45: "N", 46: "M",
           18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
           24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
           36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
          123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "?"
    }

    private static func modifierSymbols(from modifiers: UInt) -> String {
        // Bit positions match NSEvent.ModifierFlags raw values.
        var result = ""
        if modifiers & (1 << 18) != 0 { result += "⌃" }  // .control
        if modifiers & (1 << 19) != 0 { result += "⌥" }  // .option
        if modifiers & (1 << 17) != 0 { result += "⇧" }  // .shift
        if modifiers & (1 << 20) != 0 { result += "⌘" }  // .command
        return result
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```
xcodebuild test -scheme Speech2Text -destination 'platform=macOS' \
  -only-testing:Speech2TextTests/HoldKeyDisplayFormatterTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Speech2Text/Shell/HoldKeyDisplayFormatter.swift \
        Speech2TextTests/HoldKeyDisplayFormatterTests.swift
git commit -m "feat(menu): add HoldKeyDisplayFormatter for hold-key symbol rendering"
```

---

## Task 3: Add Start Recording Row

**Files:**
- Modify: `Speech2Text/Shell/StatusMenuView.swift`

The row appears only when `recordingState == .idle` (inside the ready branch, before the cancel/restart rows). It calls `startRecording()` which in `Speech2TextApp` will be wired to `activationStore.arm()`. The label shows the hold key hint (from `ShellPreferences` + `HoldKeyDisplayFormatter`) and the tap shortcut hint (from `KeyboardShortcuts.getShortcut(for: .activate)`).

`KeyboardShortcuts.getShortcut(for:)` returns a `KeyboardShortcuts.Shortcut?`. Its `.key` property is `KeyboardShortcuts.Key?` whose `.rawValue` is an `Int` (Carbon key code). Its `.modifiers` is `NSEvent.ModifierFlags`. Reuse `HoldKeyDisplayFormatter.keyCharacter(for:)` to convert the key code to a display character.

- [ ] **Step 1: Add `startRecording` parameter and computed properties to `StatusMenuView`**

Add the new stored property **after `restartSession`** (so the memberwise init order matches the Task 6 wiring call):
```swift
let startRecording: () -> Void
```

Add these computed properties after `canRestartSession`:

```swift
private var canStartSession: Bool {
    recordingState == .idle
}

private var holdKeyHint: String {
    HoldKeyDisplayFormatter.symbol(
        keyCode: preferences.holdShortcutKeyCode,
        modifiers: preferences.holdShortcutModifiers
    )
}

private var tapKeyHint: String {
    guard let shortcut = KeyboardShortcuts.getShortcut(for: .activate) else { return "" }
    var result = ""
    if shortcut.modifiers.contains(.control) { result += "⌃" }
    if shortcut.modifiers.contains(.option)  { result += "⌥" }
    if shortcut.modifiers.contains(.shift)   { result += "⇧" }
    if shortcut.modifiers.contains(.command) { result += "⌘" }
    if let key = shortcut.key {
        result += HoldKeyDisplayFormatter.keyCharacter(for: key.rawValue)
    }
    return result
}
```

- [ ] **Step 2: Add the Start Recording row to `body`, at the top of the `else` block (before the `if canCancelSession` check)**

```swift
if canStartSession {
    Button(action: startRecording) {
        HStack {
            Text("Start Recording")
            Spacer()
            HStack(spacing: 4) {
                Text("Hold \(holdKeyHint)")
                if !tapKeyHint.isEmpty {
                    Text("·")
                    Text(tapKeyHint)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
    .accessibilityIdentifier("statusMenu.startRecording")
}
```

- [ ] **Step 3: Build**

```
xcodebuild -scheme Speech2Text -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **` — `Speech2TextApp` will fail with a missing-argument error until Task 7; that is expected.

- [ ] **Step 4: Commit**

```bash
git add Speech2Text/Shell/StatusMenuView.swift
git commit -m "feat(menu): add Start Recording row with dual hold/tap hotkey hints"
```

---

## Task 4: Add Microphone Quick-Switch Submenu

**Files:**
- Modify: `Speech2Text/Shell/StatusMenuView.swift`

The submenu uses SwiftUI `Menu {}` which renders as a native submenu in `.menu` style `MenuBarExtra`. It lists all `AudioDeviceService.availableDevices` plus a "System Default" option at the top. The currently selected device is identified by comparing `preferences.micDeviceUID` to `device.uid` (nil = System Default). The submenu is disabled when `canCancelSession` is true (active session).

`AudioDeviceService` is an `ObservableObject` with `@Published var availableDevices: [AudioInputDevice]`. `AudioInputDevice` has `id: AudioDeviceID`, `name: String`, `uid: String`, and conforms to `Identifiable`.

- [ ] **Step 1: Add `audioDeviceService` and `setMicDevice` parameters to `StatusMenuView`**

Add `audioDeviceService` **after `readinessStore`** (keeping `@ObservedObject` props grouped):
```swift
@ObservedObject var audioDeviceService: AudioDeviceService
```

Add `setMicDevice` **after `copyLastConvertedTranscription`**:
```swift
let setMicDevice: (String?) -> Void
```

- [ ] **Step 2: Add the Microphone submenu row to `body`, inside the `else` block, after `showsMicrophoneSettingsAction` and before `"Hotkeys & Settings…"`**

```swift
Menu {
    Button(action: { setMicDevice(nil) }) {
        HStack {
            if preferences.micDeviceUID == nil {
                Image(systemName: "checkmark")
            }
            Text("System Default")
        }
    }
    .accessibilityIdentifier("statusMenu.mic.systemDefault")

    if !audioDeviceService.availableDevices.isEmpty {
        Divider()
        ForEach(audioDeviceService.availableDevices) { device in
            Button(action: { setMicDevice(device.uid) }) {
                HStack {
                    if preferences.micDeviceUID == device.uid {
                        Image(systemName: "checkmark")
                    }
                    Text(device.name)
                }
            }
            .accessibilityIdentifier("statusMenu.mic.\(device.uid)")
        }
    }
} label: {
    HStack(spacing: 6) {
        Image(systemName: "mic")
        Text("Microphone")
    }
}
.disabled(canCancelSession)
.accessibilityIdentifier("statusMenu.microphoneMenu")
```

Also add `.onAppear { audioDeviceService.refresh() }` inside the `else` block (after the existing `.onAppear { readinessStore.refresh() }` at the VStack level — add it to the VStack's `.onAppear`):

Replace:
```swift
.onAppear {
    readinessStore.refresh()
}
```
With:
```swift
.onAppear {
    readinessStore.refresh()
    audioDeviceService.refresh()
}
```

- [ ] **Step 3: Build**

```
xcodebuild -scheme Speech2Text -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **` — `Speech2TextApp` still fails on missing args; expected until Task 7.

- [ ] **Step 4: Commit**

```bash
git add Speech2Text/Shell/StatusMenuView.swift
git commit -m "feat(menu): add microphone quick-switch submenu"
```

---

## Task 5: Add Auto-paste Toggle

**Files:**
- Modify: `Speech2Text/Shell/StatusMenuView.swift`

`preferences.alwaysAutoPaste` is `@Published` on the `@ObservedObject var preferences: ShellPreferences` that is already in the view. Toggling it calls `didSet`, which immediately persists the value to `UserDefaults`. No new parameter needed.

The row goes inside the `else` block, after the Microphone submenu and before `"Hotkeys & Settings…"`.

- [ ] **Step 1: Add the Auto-paste toggle row**

```swift
Button(action: { preferences.alwaysAutoPaste.toggle() }) {
    HStack {
        if preferences.alwaysAutoPaste {
            Image(systemName: "checkmark")
        }
        Text("Auto-paste")
    }
}
.accessibilityIdentifier("statusMenu.autoPaste")
```

- [ ] **Step 2: Add Cancel hotkey hint**

While in this task, also add `.keyboardShortcut` to the Cancel Session button (visible in the active/recording state):

```swift
Button("Cancel Session", action: cancelSession)
    .keyboardShortcut("v", modifiers: [.control, .shift])
    .accessibilityIdentifier("statusMenu.cancelSession")
```

- [ ] **Step 3: Build**

```
xcodebuild -scheme Speech2Text -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Speech2Text/Shell/StatusMenuView.swift
git commit -m "feat(menu): add auto-paste toggle and cancel session hotkey hint"
```

---

## Task 6: Wire New Parameters in Speech2TextApp

**Files:**
- Modify: `Speech2Text/App/Speech2TextApp.swift`

This is the final wiring task. It adds `AudioDeviceService` as a `@StateObject` and passes all three new closures to `StatusMenuView`.

- [ ] **Step 1: Add `@StateObject` for `AudioDeviceService`**

Add to the `@StateObject` declarations at the top of `Speech2TextApp`:

```swift
@StateObject private var audioDeviceService: AudioDeviceService
```

In `init()`, after the existing `@StateObject` wrapping:

```swift
let audioDeviceService = AudioDeviceService.shared
_audioDeviceService = StateObject(wrappedValue: audioDeviceService)
```

- [ ] **Step 2: Pass new parameters to `StatusMenuView` in `body`**

Replace the existing `StatusMenuView(...)` call with:

```swift
StatusMenuView(
    recordingState: activationStore.state,
    recoveryFeedback: activationStore.recoveryFeedback,
    lastTranscription: activationStore.lastTranscription,
    preferences: preferences,
    readinessStore: readinessStore,
    audioDeviceService: audioDeviceService,
    cancelSession: {
        activationStore.cancelCurrentSession()
    },
    restartSession: {
        activationStore.restartCurrentSession()
    },
    startRecording: {
        activationStore.arm()
    },
    copyLastTranscription: {
        activationStore.copyLastTranscription()
    },
    lastConvertedTranscription: activationStore.lastConvertedTranscription,
    copyLastConvertedTranscription: {
        activationStore.copyLastConvertedTranscription()
    },
    setMicDevice: { uid in
        preferences.micDeviceUID = uid
    },
    openSetup: {
        appDelegate.presentSetupWindow()
    },
    quitApp: {
        NSApp.terminate(nil)
    }
)
```

- [ ] **Step 3: Build clean**

```
xcodebuild -scheme Speech2Text -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run full unit test suite**

```
xcodebuild test -scheme Speech2Text -destination 'platform=macOS' \
  -only-testing:Speech2TextTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Speech2Text/App/Speech2TextApp.swift
git commit -m "feat(menu): wire startRecording, audioDeviceService, and setMicDevice into StatusMenuView"
```
