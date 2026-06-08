import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutRecorderField: View {
    let displayText: String
    let isRecording: Bool
    let isNonDefault: Bool
    let isEmpty: Bool
    let accessibilityID: String
    let recordingPrompt: String
    let onClear: () -> Void
    let onStartRecording: () -> Void
    var onReset: (() -> Void)? = nil

    init(
        displayText: String,
        isRecording: Bool,
        isNonDefault: Bool,
        isEmpty: Bool = false,
        accessibilityID: String,
        recordingPrompt: String = "Press key",
        onClear: @escaping () -> Void,
        onStartRecording: @escaping () -> Void,
        onReset: (() -> Void)? = nil
    ) {
        self.displayText = displayText
        self.isRecording = isRecording
        self.isNonDefault = isNonDefault
        self.isEmpty = isEmpty
        self.accessibilityID = accessibilityID
        self.recordingPrompt = recordingPrompt
        self.onClear = onClear
        self.onStartRecording = onStartRecording
        self.onReset = onReset
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(isRecording ? recordingPrompt : displayText)
                .font(.body)
                .foregroundStyle(isRecording ? .secondary : (isEmpty ? .secondary : .primary))
                .frame(
                    maxWidth: .infinity,
                    minHeight: 22,
                    alignment: isEmpty && !isRecording ? .center : .leading
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .accessibilityIdentifier(accessibilityID)
                .accessibilityLabel(displayText)

            if !isRecording {
                if isNonDefault, let onReset {
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                } else if onReset != nil {
                    // Invisible placeholder to keep width stable
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                        .hidden()
                }

                if !isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear shortcut")
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .frame(width: SettingsLayoutMetrics.shortcutRecorderWidth)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(SetupColorPalette.raisedControlBackground)
        )
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .onTapGesture {
            if isEmpty && !isRecording {
                onStartRecording()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
        )
    }
}

struct KeyComboRecorder: View {
    let name: KeyboardShortcuts.Name
    let preferences: ShellPreferences
    var onShortcutChanged: () -> Void = {}
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var clickMonitor: Any?
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?
    @State private var shortcutBeforeRecording: KeyboardShortcuts.Shortcut?
    @State private var lastCancelTime: Date = .distantPast

    private let emptyShortcutText = "Click to set Key"

    private var displayText: String {
        currentShortcut?.description ?? emptyShortcutText
    }

    private var isNonDefault: Bool {
        currentShortcut != name.defaultShortcut
    }

    var body: some View {
        ShortcutRecorderField(
            displayText: displayText,
            isRecording: isRecording,
            isNonDefault: isNonDefault,
            isEmpty: currentShortcut == nil,
            accessibilityID: "setupWindow.\(name.rawValue).recorder",
            onClear: {
                KeyboardShortcuts.setShortcut(nil, for: name)
                currentShortcut = nil
                onShortcutChanged()
            },
            onStartRecording: {
                guard Date().timeIntervalSince(lastCancelTime) > 0.3 else { return }
                startRecording()
            },
            onReset: {
                KeyboardShortcuts.reset(name)
                currentShortcut = KeyboardShortcuts.getShortcut(for: name)
                onShortcutChanged()
            }
        )
        .onAppear {
            currentShortcut = KeyboardShortcuts.getShortcut(for: name)
        }
        .onDisappear { cancelRecording() }
    }

    private func startRecording() {
        shortcutBeforeRecording = currentShortcut
        isRecording = true
        KeyboardShortcuts.disable(.activate, .activateAlt, .stopSession, .stopSessionAlt, .cancelSession)
        HotkeyService.shared.setMouseBindingsEnabled(false)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { // Escape — restore previous
                cancelRecording()
                return nil
            }

            let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
            let modifiers = event.modifierFlags.intersection(relevantModifiers)
            let isFunctionKey = (0x60...0x6F).contains(Int(event.keyCode))
                || (0x40...0x4F).contains(Int(event.keyCode))

            guard !modifiers.subtracting(.shift).isEmpty || isFunctionKey else {
                NSSound.beep()
                return nil
            }

            if let shortcut = KeyboardShortcuts.Shortcut(event: event) {
                let snapshot = ShortcutBindingSnapshot.current(preferences: preferences)
                if !ShortcutBindingPolicy.tapShortcutConflictsWithHold(shortcut, snapshot: snapshot) {
                    KeyboardShortcuts.setShortcut(shortcut, for: name)
                    currentShortcut = shortcut
                    onShortcutChanged()
                    finishRecording()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            cancelRecording()
            return event
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }
        if let previous = shortcutBeforeRecording {
            KeyboardShortcuts.setShortcut(previous, for: name)
            currentShortcut = previous
        }
        lastCancelTime = Date()
        finishRecording()
    }

    private func finishRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        eventMonitor = nil
        clickMonitor = nil
        shortcutBeforeRecording = nil
        isRecording = false
        KeyboardShortcuts.enable(.activate, .activateAlt, .stopSession, .stopSessionAlt, .cancelSession)
        HotkeyService.shared.setMouseBindingsEnabled(true)
    }
}

struct HoldShortcutRecorder: View {
    let slot: HoldShortcutSlot
    let preferences: ShellPreferences
    let keyCode: Int
    let modifiers: UInt
    let defaultKeyCode: Int
    let defaultModifiers: UInt
    let accessibilityID: String
    let onRecord: (Int, UInt) -> Void
    let onClear: () -> Void
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var clickMonitor: Any?
    @State private var pendingModifierKeyCode: Int?
    @State private var keyCodeBeforeRecording: Int?
    @State private var modifiersBeforeRecording: UInt?
    @State private var lastCancelTime: Date = .distantPast

    static func displayName(keyCode: Int, modifiers: UInt) -> String {
        let nsFlags = NSEvent.ModifierFlags(rawValue: modifiers)
        var symbols = ""
        if nsFlags.contains(.control) { symbols += "⌃" }
        if nsFlags.contains(.option) { symbols += "⌥" }
        if nsFlags.contains(.shift) { symbols += "⇧" }
        if nsFlags.contains(.command) { symbols += "⌘" }

        if let modName = HoldModifierKey.displayName(for: keyCode) {
            return symbols.isEmpty ? modName : symbols + " " + modName
        }

        let key = KeyboardShortcuts.Key(rawValue: keyCode)
        let shortcut = KeyboardShortcuts.Shortcut(key)
        let keyChar = shortcut.description.trimmingCharacters(in: .whitespaces)
        return symbols.isEmpty ? keyChar : symbols + keyChar
    }

    /// True when a binding is set (keyCode >= 0) and differs from the default.
    private var isNonDefault: Bool {
        guard keyCode >= 0 else { return false }
        return keyCode != defaultKeyCode || modifiers != defaultModifiers
    }

    private let emptyShortcutText = "Click to set Key"

    private var displayText: String {
        guard keyCode >= 0 else { return emptyShortcutText }
        return Self.displayName(keyCode: keyCode, modifiers: modifiers)
    }

    var body: some View {
        ShortcutRecorderField(
            displayText: displayText,
            isRecording: isRecording,
            isNonDefault: isNonDefault,
            isEmpty: keyCode < 0,
            accessibilityID: accessibilityID,
            onClear: {
                onClear()
            },
            onStartRecording: {
                guard Date().timeIntervalSince(lastCancelTime) > 0.3 else { return }
                startRecording()
            },
            onReset: {
                onReset()
            }
        )
        .onDisappear { cancelRecording() }
    }

    private func startRecording() {
        keyCodeBeforeRecording = keyCode
        modifiersBeforeRecording = modifiers
        isRecording = true
        KeyboardShortcuts.disable(.activate, .activateAlt, .stopSession, .stopSessionAlt, .cancelSession)
        HotkeyService.shared.setMouseBindingsEnabled(false)
        pendingModifierKeyCode = nil
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape — restore previous
                    cancelRecording()
                    return nil
                }
                pendingModifierKeyCode = nil
                let relevantModifiers = HoldModifierKey.relevantNSEventFlags
                let kc = Int(event.keyCode)
                let mods = event.modifierFlags.intersection(relevantModifiers).rawValue
                if !conflictsWithOtherBindings(keyCode: kc, modifiers: mods) {
                    recordKey(keyCode: kc, modifiers: mods)
                } else {
                    NSSound.beep()
                }
                return nil
            }

            if event.type == .flagsChanged {
                let kc = Int(event.keyCode)
                if HoldModifierKey.contains(kc) {
                    let flag = HoldModifierKey.nsEventFlag(for: kc)
                    if event.modifierFlags.contains(flag) {
                        pendingModifierKeyCode = kc
                    } else if pendingModifierKeyCode == kc {
                        let relevantModifiers = HoldModifierKey.relevantNSEventFlags
                        let remaining = event.modifierFlags.intersection(relevantModifiers)
                        if remaining.isEmpty {
                            recordKey(keyCode: kc, modifiers: 0)
                        }
                        pendingModifierKeyCode = nil
                    }
                }
            }
            return event
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            cancelRecording()
            return event
        }
    }

    private func conflictsWithOtherBindings(keyCode: Int, modifiers: UInt) -> Bool {
        let key = KeyboardShortcuts.Key(rawValue: keyCode)
        let candidate = KeyboardShortcuts.Shortcut(
            key,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiers)
        )
        let snapshot = ShortcutBindingSnapshot.current(preferences: preferences)
        return ShortcutBindingPolicy.holdShortcutConflicts(candidate, slot: slot, snapshot: snapshot)
    }

    private func recordKey(keyCode: Int, modifiers: UInt) {
        onRecord(keyCode, modifiers)
        finishRecording()
    }

    private func cancelRecording() {
        guard isRecording else { return }
        if let kc = keyCodeBeforeRecording, let mods = modifiersBeforeRecording {
            onRecord(kc, mods)
        }
        lastCancelTime = Date()
        finishRecording()
    }

    private func finishRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        eventMonitor = nil
        clickMonitor = nil
        pendingModifierKeyCode = nil
        keyCodeBeforeRecording = nil
        modifiersBeforeRecording = nil
        isRecording = false
        KeyboardShortcuts.enable(.activate, .activateAlt, .stopSession, .stopSessionAlt, .cancelSession)
        HotkeyService.shared.setMouseBindingsEnabled(true)
    }
}

struct MouseButtonRecorder: View {
    let action: MouseButtonShortcutAction
    let preferences: ShellPreferences
    let binding: MouseButtonBinding?
    let accessibilityID: String
    let onRecord: (MouseButtonBinding) -> Void
    let onClear: () -> Void

    @State private var isRecording = false
    @State private var mouseMonitor: Any?
    @State private var cancelMonitor: Any?
    @State private var previousBinding: MouseButtonBinding?
    @State private var lastCancelTime: Date = .distantPast

    private let emptyShortcutText = "Click to set Key"

    private var displayText: String {
        binding?.displayName ?? emptyShortcutText
    }

    var body: some View {
        ShortcutRecorderField(
            displayText: displayText,
            isRecording: isRecording,
            isNonDefault: binding != nil,
            isEmpty: binding == nil,
            accessibilityID: accessibilityID,
            recordingPrompt: "Click button",
            onClear: onClear,
            onStartRecording: {
                guard Date().timeIntervalSince(lastCancelTime) > 0.3 else { return }
                startRecording()
            }
        )
        .onDisappear { cancelRecording() }
    }

    private func startRecording() {
        previousBinding = binding
        isRecording = true
        KeyboardShortcuts.disable(.activate, .activateAlt, .stopSession, .stopSessionAlt, .cancelSession)
        HotkeyService.shared.setMouseBindingsEnabled(false)
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { event in
            let candidate = MouseButtonBinding(buttonNumber: Int(event.buttonNumber))
            let snapshot = ShortcutBindingSnapshot.current(preferences: preferences)
            if ShortcutBindingPolicy.mouseButtonConflicts(candidate, action: action, snapshot: snapshot) {
                NSSound.beep()
            } else {
                onRecord(candidate)
                finishRecording()
            }
            return nil
        }
        cancelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            cancelRecording()
            return event
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }
        if let previousBinding {
            onRecord(previousBinding)
        }
        lastCancelTime = Date()
        finishRecording()
    }

    private func finishRecording() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let cancelMonitor {
            NSEvent.removeMonitor(cancelMonitor)
        }
        mouseMonitor = nil
        cancelMonitor = nil
        previousBinding = nil
        isRecording = false
        KeyboardShortcuts.enable(.activate, .activateAlt, .stopSession, .stopSessionAlt, .cancelSession)
        HotkeyService.shared.setMouseBindingsEnabled(true)
    }
}
