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
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isRecording else { return }
                    onStartRecording()
                }

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
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
        )
    }
}

@MainActor
private enum ShortcutRecorderRuntime {
    static func disableManagedShortcuts() {
        KeyboardShortcuts.disable(.activate, .activateAlt, .activateTertiary)
        KeyboardShortcuts.disable(.stopSession, .stopSessionAlt, .stopSessionTertiary)
        KeyboardShortcuts.disable(.cancelSession)
        HotkeyService.shared.setMouseBindingsEnabled(false)
    }

    static func enableManagedShortcuts() {
        KeyboardShortcuts.enable(.activate, .activateAlt, .activateTertiary)
        KeyboardShortcuts.enable(.stopSession, .stopSessionAlt, .stopSessionTertiary)
        KeyboardShortcuts.enable(.cancelSession)
        HotkeyService.shared.setMouseBindingsEnabled(true)
    }
}

struct TapShortcutSlotRecorder: View {
    let slot: ShortcutBindingSlot
    let name: KeyboardShortcuts.Name
    @ObservedObject var preferences: ShellPreferences
    let mouseAction: MouseButtonShortcutAction
    let mouseBindings: MouseButtonBindingSet
    let accessibilityID: String
    var onShortcutChanged: () -> Void = {}

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var cancelMonitor: Any?
    @State private var shortcutBeforeRecording: KeyboardShortcuts.Shortcut?
    @State private var mouseBindingsBeforeRecording: MouseButtonBindingSet = .empty
    @State private var lastCancelTime: Date = .distantPast

    private let emptyShortcutText = "Click to set"

    private var currentShortcut: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name)
    }

    private var mouseBinding: MouseButtonBinding? {
        mouseBindings.binding(for: slot)
    }

    private var isMouseAssignedToSlot: Bool {
        mouseBinding != nil
    }

    private var displayText: String {
        if isMouseAssignedToSlot, let mouseBinding {
            return mouseBinding.displayName
        }
        return currentShortcut?.description ?? emptyShortcutText
    }

    private var isEmpty: Bool {
        !isMouseAssignedToSlot && currentShortcut == nil
    }

    private var isNonDefault: Bool {
        if isMouseAssignedToSlot {
            return true
        }
        return currentShortcut != name.defaultShortcut
    }

    var body: some View {
        ShortcutRecorderField(
            displayText: displayText,
            isRecording: isRecording,
            isNonDefault: isNonDefault,
            isEmpty: isEmpty,
            accessibilityID: accessibilityID,
            recordingPrompt: "Press key/button",
            onClear: clearCurrentBinding,
            onStartRecording: {
                guard Date().timeIntervalSince(lastCancelTime) > 0.3 else { return }
                startRecording()
            },
            onReset: resetToDefault
        )
        .onDisappear { cancelRecording() }
    }

    private func startRecording() {
        shortcutBeforeRecording = currentShortcut
        mouseBindingsBeforeRecording = mouseBindings
        isRecording = true
        ShortcutRecorderRuntime.disableManagedShortcuts()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
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

            guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
                NSSound.beep()
                return nil
            }

            let snapshot = ShortcutBindingSnapshot.current(preferences: preferences)
            guard !ShortcutBindingPolicy.tapShortcutConflictsWithHold(shortcut, snapshot: snapshot) else {
                NSSound.beep()
                return nil
            }

            KeyboardShortcuts.setShortcut(shortcut, for: name)
            clearMouseBindingIfAssignedToSlot()
            onShortcutChanged()
            finishRecording()
            return nil
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { event in
            let candidate = MouseButtonBinding(buttonNumber: Int(event.buttonNumber))
            KeyboardShortcuts.setShortcut(nil, for: name)
            ShortcutBindingPolicy.assignMouseButtonBinding(
                candidate,
                action: mouseAction,
                slot: slot,
                preferences: preferences
            )
            HotkeyService.shared.configureMouseBindings()
            onShortcutChanged()
            finishRecording()
            return nil
        }

        cancelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            cancelRecording()
            return event
        }
    }

    private func clearCurrentBinding() {
        if isMouseAssignedToSlot {
            setMouseBinding(nil, slot: slot)
            HotkeyService.shared.configureMouseBindings()
        } else {
            KeyboardShortcuts.setShortcut(nil, for: name)
        }
        onShortcutChanged()
    }

    private func resetToDefault() {
        KeyboardShortcuts.reset(name)
        if isMouseAssignedToSlot {
            setMouseBinding(nil, slot: slot)
            HotkeyService.shared.configureMouseBindings()
        }
        onShortcutChanged()
    }

    private func clearMouseBindingIfAssignedToSlot() {
        guard isMouseAssignedToSlot else { return }
        setMouseBinding(nil, slot: slot)
        HotkeyService.shared.configureMouseBindings()
    }

    private func cancelRecording() {
        guard isRecording else { return }
        KeyboardShortcuts.setShortcut(shortcutBeforeRecording, for: name)
        setMouseBindings(mouseBindingsBeforeRecording)
        HotkeyService.shared.configureMouseBindings()
        lastCancelTime = Date()
        finishRecording()
    }

    private func finishRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let cancelMonitor {
            NSEvent.removeMonitor(cancelMonitor)
        }
        keyMonitor = nil
        mouseMonitor = nil
        cancelMonitor = nil
        shortcutBeforeRecording = nil
        mouseBindingsBeforeRecording = .empty
        isRecording = false
        ShortcutRecorderRuntime.enableManagedShortcuts()
    }

    private func setMouseBinding(_ binding: MouseButtonBinding?, slot: ShortcutBindingSlot) {
        var bindings = mouseBindingsForAction()
        bindings.set(binding, for: slot)
        setMouseBindings(bindings)
    }

    private func setMouseBindings(_ bindings: MouseButtonBindingSet) {
        switch mouseAction {
        case .startRecording:
            preferences.startMouseButtonBindings = bindings
        case .stopRecording:
            preferences.stopMouseButtonBindings = bindings
        case .holdToRecord:
            preferences.holdMouseButtonBindings = bindings
        }
    }

    private func mouseBindingsForAction() -> MouseButtonBindingSet {
        switch mouseAction {
        case .startRecording:
            return preferences.startMouseButtonBindings
        case .stopRecording:
            return preferences.stopMouseButtonBindings
        case .holdToRecord:
            return preferences.holdMouseButtonBindings
        }
    }
}

private enum HoldShortcutDisplayName {
    static func format(keyCode: Int, modifiers: UInt) -> String {
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
}

struct HoldShortcutSlotRecorder: View {
    let slot: HoldShortcutSlot
    @ObservedObject var preferences: ShellPreferences
    let keyCode: Int
    let modifiers: UInt
    let defaultKeyCode: Int
    let defaultModifiers: UInt
    let mouseBindings: MouseButtonBindingSet
    let accessibilityID: String
    let onRecordKey: (Int, UInt) -> Void
    let onClearKey: () -> Void
    let onResetKey: () -> Void

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var cancelMonitor: Any?
    @State private var pendingModifierKeyCode: Int?
    @State private var keyCodeBeforeRecording: Int?
    @State private var modifiersBeforeRecording: UInt?
    @State private var mouseBindingsBeforeRecording: MouseButtonBindingSet = .empty
    @State private var lastCancelTime: Date = .distantPast

    private let emptyShortcutText = "Click to set"

    private var mouseBinding: MouseButtonBinding? {
        mouseBindings.binding(for: slot)
    }

    private var isMouseAssignedToSlot: Bool {
        mouseBinding != nil
    }

    private var displayText: String {
        if isMouseAssignedToSlot, let mouseBinding {
            return mouseBinding.displayName
        }
        guard keyCode >= 0 else { return emptyShortcutText }
        return HoldShortcutDisplayName.format(keyCode: keyCode, modifiers: modifiers)
    }

    private var isEmpty: Bool {
        !isMouseAssignedToSlot && keyCode < 0
    }

    private var isNonDefault: Bool {
        if isMouseAssignedToSlot {
            return true
        }
        return keyCode != defaultKeyCode || modifiers != defaultModifiers
    }

    var body: some View {
        ShortcutRecorderField(
            displayText: displayText,
            isRecording: isRecording,
            isNonDefault: isNonDefault,
            isEmpty: isEmpty,
            accessibilityID: accessibilityID,
            recordingPrompt: "Press key/button",
            onClear: clearCurrentBinding,
            onStartRecording: {
                guard Date().timeIntervalSince(lastCancelTime) > 0.3 else { return }
                startRecording()
            },
            onReset: resetToDefault
        )
        .onDisappear { cancelRecording() }
    }

    private func startRecording() {
        keyCodeBeforeRecording = keyCode
        modifiersBeforeRecording = modifiers
        mouseBindingsBeforeRecording = mouseBindings
        isRecording = true
        pendingModifierKeyCode = nil
        ShortcutRecorderRuntime.disableManagedShortcuts()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 {
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

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { event in
            let candidate = MouseButtonBinding(buttonNumber: Int(event.buttonNumber))
            onRecordKey(-1, 0)
            ShortcutBindingPolicy.assignMouseButtonBinding(
                candidate,
                action: .holdToRecord,
                slot: slot,
                preferences: preferences
            )
            HotkeyService.shared.configureMouseBindings()
            finishRecording()
            return nil
        }

        cancelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
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
        onRecordKey(keyCode, modifiers)
        clearMouseBindingIfAssignedToSlot()
        finishRecording()
    }

    private func clearCurrentBinding() {
        if isMouseAssignedToSlot {
            setMouseBinding(nil, slot: slot)
            HotkeyService.shared.configureMouseBindings()
        } else {
            onClearKey()
        }
    }

    private func resetToDefault() {
        onResetKey()
        if isMouseAssignedToSlot {
            setMouseBinding(nil, slot: slot)
            HotkeyService.shared.configureMouseBindings()
        }
    }

    private func clearMouseBindingIfAssignedToSlot() {
        guard isMouseAssignedToSlot else { return }
        setMouseBinding(nil, slot: slot)
        HotkeyService.shared.configureMouseBindings()
    }

    private func cancelRecording() {
        guard isRecording else { return }
        if let keyCodeBeforeRecording, let modifiersBeforeRecording {
            onRecordKey(keyCodeBeforeRecording, modifiersBeforeRecording)
        }
        preferences.holdMouseButtonBindings = mouseBindingsBeforeRecording
        HotkeyService.shared.configureMouseBindings()
        lastCancelTime = Date()
        finishRecording()
    }

    private func finishRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let cancelMonitor {
            NSEvent.removeMonitor(cancelMonitor)
        }
        keyMonitor = nil
        mouseMonitor = nil
        cancelMonitor = nil
        pendingModifierKeyCode = nil
        keyCodeBeforeRecording = nil
        modifiersBeforeRecording = nil
        mouseBindingsBeforeRecording = .empty
        isRecording = false
        ShortcutRecorderRuntime.enableManagedShortcuts()
    }

    private func setMouseBinding(_ binding: MouseButtonBinding?, slot: ShortcutBindingSlot) {
        var bindings = preferences.holdMouseButtonBindings
        bindings.set(binding, for: slot)
        preferences.holdMouseButtonBindings = bindings
    }
}
