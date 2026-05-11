import AppKit
import Carbon.HIToolbox
import Combine
import KeyboardShortcuts
import SwiftUI

enum SetupWindowMetrics {
    static let width: CGFloat = 920
    static let collapsedHeight: CGFloat = 780
}

enum CloudConnectionTestResult: Equatable {
    case success
    case failed(String)
}

private enum RewriteSystemPromptSectionMetrics {
    static let editorHeight: CGFloat = 150
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case setup
    case general
    case assistant
    case replacements
    case shortcuts
    case advanced

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .setup:
            return "Setup"
        case .general:
            return "General"
        case .assistant:
            return "Assistant"
        case .replacements:
            return "Word Replacements"
        case .shortcuts:
            return "Keyboard Shortcuts"
        case .advanced:
            return "Advanced"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .replacements:
            return "Replacements"
        case .shortcuts:
            return "Keyboard"
        default:
            return title
        }
    }
}

private enum SettingsLayoutMetrics {
    static let sidebarWidth: CGFloat = 172
    static let contentSpacing: CGFloat = 18
    static let cardCornerRadius: CGFloat = 18
}

private struct SectionOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [SettingsSection: CGFloat] = [:]

    static func reduce(value: inout [SettingsSection: CGFloat], nextValue: () -> [SettingsSection: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Shared shortcut recorder visual field

private struct ShortcutRecorderField: View {
    let displayText: String
    let isRecording: Bool
    let isNonDefault: Bool
    let isEmpty: Bool
    let accessibilityID: String
    let onClear: () -> Void
    let onStartRecording: () -> Void
    var onReset: (() -> Void)? = nil

    init(displayText: String, isRecording: Bool, isNonDefault: Bool, isEmpty: Bool = false, accessibilityID: String, onClear: @escaping () -> Void, onStartRecording: @escaping () -> Void, onReset: (() -> Void)? = nil) {
        self.displayText = displayText
        self.isRecording = isRecording
        self.isNonDefault = isNonDefault
        self.isEmpty = isEmpty
        self.accessibilityID = accessibilityID
        self.onClear = onClear
        self.onStartRecording = onStartRecording
        self.onReset = onReset
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(isRecording ? "Record Shortcut" : displayText)
                .font(.body)
                .foregroundStyle(isRecording ? .secondary : (isEmpty ? .secondary : .primary))
                .frame(minWidth: 60)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEmpty && !isRecording {
                        onStartRecording()
                    }
                }
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
        .frame(width: 170)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Key combo recorder (Start / Stop shortcuts)

private struct KeyComboRecorder: View {
    let name: KeyboardShortcuts.Name
    let preferences: ShellPreferences
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var clickMonitor: Any?
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?
    @State private var shortcutBeforeRecording: KeyboardShortcuts.Shortcut?
    @State private var lastCancelTime: Date = .distantPast

    private var displayText: String {
        currentShortcut?.description ?? "Click to set"
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
            },
            onStartRecording: {
                guard Date().timeIntervalSince(lastCancelTime) > 0.3 else { return }
                startRecording()
            },
            onReset: {
                KeyboardShortcuts.reset(name)
                currentShortcut = KeyboardShortcuts.getShortcut(for: name)
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
    }
}

// MARK: - Hold-key recorder (modifier-only keys allowed)

private struct HoldShortcutRecorder: View {
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

    private var displayText: String {
        guard keyCode >= 0 else { return "Not Set" }
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
    }
}

private enum SetupSectionMetrics {
    static let rowLabelWidth: CGFloat = 150
    static let rowIndent: CGFloat = 4
}

private struct SetupFieldRow<Content: View>: View {
    let title: String
    let alignment: VerticalAlignment
    let content: Content

    init(
        title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            Text(title)
                .font(.body)
                .frame(width: SetupSectionMetrics.rowLabelWidth, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, SetupSectionMetrics.rowIndent)
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let section: SettingsSection
    let flashTrigger: Int
    let content: Content

    init(section: SettingsSection, flashTrigger: Int = 0, @ViewBuilder content: () -> Content) {
        self.section = section
        self.flashTrigger = flashTrigger
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(section.title)
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("setupWindow.section.\(section.rawValue).title")

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(Color(white: 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .modifier(
            SettingsCardFlashModifier(
                cornerRadius: SettingsLayoutMetrics.cardCornerRadius,
                flashTrigger: flashTrigger
            )
        )
        .accessibilityIdentifier("setupWindow.section.\(section.rawValue)")
    }
}

private struct SettingsCardFlashModifier: ViewModifier {
    let cornerRadius: CGFloat
    let flashTrigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashOpacity: Double = 0
    @State private var flashTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10 * flashOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.70 * flashOpacity), lineWidth: 2)
            )
            .onChange(of: flashTrigger) { newValue in
                guard newValue > 0 else { return }
                runFlash()
            }
    }

    @MainActor
    private func runFlash() {
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            flashOpacity = 0

            let rampUp = reduceMotion ? 0 : 0.12
            let rampDown = reduceMotion ? 0 : 0.45

            withAnimation(.easeOut(duration: rampUp)) {
                flashOpacity = 1
            }

            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: rampDown)) {
                flashOpacity = 0
            }
        }
    }
}

private struct SettingsSidebarButton: View {
    let section: SettingsSection
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(section.sidebarTitle)
                    .font(.body.weight(isActive ? .semibold : .regular))
                Spacer(minLength: 8)
            }
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("setupWindow.sidebar.\(section.rawValue)")
        .accessibilityValue(isActive ? "Selected" : "Not Selected")
    }
}

private struct KeyboardShortcutsRow: View {
    @ObservedObject var preferences: ShellPreferences

    var body: some View {
        SetupFieldRow(title: "Hold to record") {
            HStack(spacing: 12) {
                HoldShortcutRecorder(
                    slot: .primary,
                    preferences: preferences,
                    keyCode: preferences.holdShortcutKeyCode,
                    modifiers: preferences.holdShortcutModifiers,
                    defaultKeyCode: 61,
                    defaultModifiers: 0,
                    accessibilityID: "setupWindow.holdShortcut.recorder",
                    onRecord: { kc, mods in
                        preferences.holdShortcutKeyCode = kc
                        preferences.holdShortcutModifiers = mods
                        HotkeyService.shared.configureHoldTarget()
                    },
                    onClear: {
                        preferences.holdShortcutKeyCode = -1
                        preferences.holdShortcutModifiers = 0
                        HotkeyService.shared.configureHoldTarget()
                    },
                    onReset: {
                        preferences.holdShortcutKeyCode = 61
                        preferences.holdShortcutModifiers = 0
                        HotkeyService.shared.configureHoldTarget()
                    }
                )

                HoldShortcutRecorder(
                    slot: .secondary,
                    preferences: preferences,
                    keyCode: preferences.holdShortcutKeyCodeAlt,
                    modifiers: preferences.holdShortcutModifiersAlt,
                    defaultKeyCode: -1,
                    defaultModifiers: 0,
                    accessibilityID: "setupWindow.holdShortcutAlt.recorder",
                    onRecord: { kc, mods in
                        preferences.holdShortcutKeyCodeAlt = kc
                        preferences.holdShortcutModifiersAlt = mods
                        HotkeyService.shared.configureHoldTarget()
                    },
                    onClear: {
                        preferences.holdShortcutKeyCodeAlt = -1
                        preferences.holdShortcutModifiersAlt = 0
                        HotkeyService.shared.configureHoldTarget()
                    },
                    onReset: {
                        preferences.holdShortcutKeyCodeAlt = -1
                        preferences.holdShortcutModifiersAlt = 0
                        HotkeyService.shared.configureHoldTarget()
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("setupWindow.keyboardShortcuts.row")
    }
}

private struct AlwaysAutoPasteRow: View {
    @Binding var isOn: Bool
    var helperText: String? = "Automatically pastes the result into the focused field each time a transcription completes. When this is off, finished transcriptions are copied to the clipboard instead."

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle("Auto Paste", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 22)
                .fixedSize()
                .accessibilityLabel("Auto Paste")
                .accessibilityIdentifier("setupWindow.alwaysAutoPaste.toggle")

            if let helperText {
                ImmediateHelpIcon(text: helperText)
                    .accessibilityIdentifier("setupWindow.alwaysAutoPaste.info")
            }
        }
        .frame(height: 22, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RestoreClipboardRow: View {
    @Binding var isOn: Bool
    let isAutoPasteEnabled: Bool
    var helperText: String? = "When auto-paste is enabled, restore what was on your clipboard after pasting. Turn this off to keep the new text copied as a fallback."

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle("Restore Clipboard", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 22)
                .fixedSize()
                .disabled(!isAutoPasteEnabled)
                .accessibilityLabel("Restore Clipboard")
                .accessibilityIdentifier("setupWindow.restorePreviousClipboard.toggle")

            if let helperText {
                ImmediateHelpIcon(text: helperText)
                    .accessibilityIdentifier("setupWindow.restorePreviousClipboard.info")
            }
        }
        .opacity(isAutoPasteEnabled ? 1 : 0.55)
        .frame(height: 22, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaySoundEffectsRow: View {
    @Binding var isOn: Bool
    var helperText: String? = "Keeps the start, success, and failure sound effects enabled for transcription sessions."

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle("Play sound effects", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 22)
                .fixedSize()
                .accessibilityLabel("Play sound effects")
                .accessibilityIdentifier("setupWindow.muteSoundEffects.toggle")

            if let helperText {
                ImmediateHelpIcon(text: helperText)
                    .accessibilityIdentifier("setupWindow.muteSoundEffects.info")
            }
        }
        .frame(height: 22, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PillPositionPickerRow: View {
    private struct GridCell: Identifiable {
        let id: String
        let position: RecordingPillPosition?
        let accessibilityIdentifier: String?
    }

    @Binding var selection: RecordingPillPosition
    let onHoverChange: (RecordingPillPosition?) -> Void

    private let tileSize: CGFloat = 40
    private let tileCornerRadius: CGFloat = 10
    private let gridDimension: CGFloat = 120
    private let columns = Array(repeating: GridItem(.fixed(40), spacing: 0), count: 3)
    private let cells: [GridCell] = [
        GridCell(id: "topLeft", position: .topLeft, accessibilityIdentifier: "setupWindow.pillPosition.topLeft"),
        GridCell(id: "topCenter", position: .topCenter, accessibilityIdentifier: "setupWindow.pillPosition.topCenter"),
        GridCell(id: "topRight", position: .topRight, accessibilityIdentifier: "setupWindow.pillPosition.topRight"),
        GridCell(id: "centerLeft", position: .centerLeft, accessibilityIdentifier: "setupWindow.pillPosition.centerLeft"),
        GridCell(id: "centerSpacer", position: nil, accessibilityIdentifier: nil),
        GridCell(id: "centerRight", position: .centerRight, accessibilityIdentifier: "setupWindow.pillPosition.centerRight"),
        GridCell(id: "bottomLeft", position: .bottomLeft, accessibilityIdentifier: "setupWindow.pillPosition.bottomLeft"),
        GridCell(id: "bottomCenter", position: .bottomCenter, accessibilityIdentifier: "setupWindow.pillPosition.bottomCenter"),
        GridCell(id: "bottomRight", position: .bottomRight, accessibilityIdentifier: "setupWindow.pillPosition.bottomRight"),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            ForEach(cells) { cell in
                cellView(for: cell)
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: tileCornerRadius,
                    bottomLeading: tileCornerRadius,
                    bottomTrailing: tileCornerRadius,
                    topTrailing: tileCornerRadius
                ),
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: tileCornerRadius,
                    bottomLeading: tileCornerRadius,
                    bottomTrailing: tileCornerRadius,
                    topTrailing: tileCornerRadius
                ),
                style: .continuous
            )
            .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(width: gridDimension, height: gridDimension, alignment: .topLeading)
        .onHover { isHovering in
            if !isHovering {
                onHoverChange(nil)
            }
        }
        .onDisappear {
            onHoverChange(nil)
        }
    }

    @ViewBuilder
    private func cellView(for cell: GridCell) -> some View {
        if let position = cell.position, let accessibilityIdentifier = cell.accessibilityIdentifier {
            positionButton(for: position, accessibilityIdentifier: accessibilityIdentifier)
        } else {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: tileSize, height: tileSize)
                .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                .accessibilityHidden(true)
        }
    }

    private func positionButton(
        for position: RecordingPillPosition,
        accessibilityIdentifier: String
    ) -> some View {
        let isSelected = selection == position

        return Button {
            selection = position
        } label: {
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                .overlay(Rectangle().stroke(
                    isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.06),
                    lineWidth: 0.5
                ))
                .frame(width: tileSize, height: tileSize)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                onHoverChange(position)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(position.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct ImmediateHelpIcon: View {
    let text: String
    @State private var isHovering = false
    private let tooltipWidth: CGFloat = 240

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.08)) {
                    isHovering = hovering
                }
            }
            .overlay(alignment: .topLeading) {
                if isHovering {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: tooltipWidth, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        }
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
                        .offset(x: 16, y: -12)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(text)
            .zIndex(isHovering ? 1 : 0)
    }
}

private struct CircularProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: progress)
        }
        .frame(width: 28, height: 28)
    }
}

private struct ModelDownloadStatusRow: View {
    let title: String
    let message: String
    let progress: Double?  // nil = indeterminate

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let progress {
                CircularProgressRing(progress: progress)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SetupWindowView: View {
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    @ObservedObject private var modelLoadState = RewriteModelLoadState.shared
    @ObservedObject private var whisperModelLoadState = WhisperModelLoadState.shared
    @ObservedObject private var activationStore = ActivationStore.shared
    @ObservedObject private var audioDeviceService = AudioDeviceService.shared
    @StateObject private var assistantSettingsViewModel: AIAssistantSettingsViewModel
    @State private var isAdvancedSettingsExpanded = false
    @State private var cloudAPIKey = ""
    @State private var cloudAPIKeyLoaded = false
    @State private var cloudModels: [CloudModelInfo] = []
    @State private var isLoadingCloudModels = false
    @State private var cloudModelFetchError: String?
    @State private var cloudConnectionTestResult: CloudConnectionTestResult?
    @State private var activeSection: SettingsSection = .setup
    @State private var flashedSection: SettingsSection?
    @State private var flashNonce: Int = 0
    @State private var scheduledFlashTask: Task<Void, Never>?
    let updatePillPositionPreview: (RecordingPillPosition?) -> Void
    let dismissWindow: () -> Void
    let openGuide: () -> Void

    private var rewriteSystemPromptBinding: Binding<String> {
        Binding(
            get: {
                preferences.rewriteSystemPromptPrefix
            },
            set: { newValue in
                preferences.rewriteSystemPromptPrefix = newValue
            }
        )
    }

    /// The effective mic UID: first entry in the priority list that is currently available.
    /// Returns nil when no priority device is connected (fall through to system default).
    private var effectiveMicDeviceUID: String? {
        for uid in preferences.micDeviceUIDs {
            if audioDeviceService.availableDevices.contains(where: { $0.uid == uid }) {
                return uid
            }
        }
        return nil
    }

    private var microphoneSelection: Binding<String?> {
        Binding(
            get: {
                effectiveMicDeviceUID
            },
            set: { newValue in
                if let uid = newValue {
                    preferences.promoteMicDevice(uid)
                } else {
                    preferences.micDeviceUIDs = []
                }
            }
        )
    }

    private var isAnyModelTransferInFlight: Bool {
        modelLoadState.phase.downloadProgress != nil || modelLoadState.deletingTier != nil
    }

    private var canManageConversionModels: Bool {
        activationStore.state.allowsRewriteModelManagement
    }

    private var isAnyWhisperTransferInFlight: Bool {
        whisperModelLoadState.phase.isTransferInFlight || whisperModelLoadState.deletingModel != nil
    }

    private var alwaysAutoPasteBinding: Binding<Bool> {
        Binding(
            get: {
                preferences.alwaysAutoPaste
            },
            set: { newValue in
                preferences.alwaysAutoPaste = newValue
            }
        )
    }

    private var restorePreviousClipboardBinding: Binding<Bool> {
        Binding(
            get: {
                preferences.restorePreviousClipboardAfterAutoPaste
            },
            set: { newValue in
                preferences.restorePreviousClipboardAfterAutoPaste = newValue
            }
        )
    }

    private var playSoundEffectsBinding: Binding<Bool> {
        Binding(
            get: {
                !preferences.muteSoundEffects
            },
            set: { newValue in
                preferences.muteSoundEffects = !newValue
            }
        )
    }

    private var recordingPillPositionBinding: Binding<RecordingPillPosition> {
        Binding(
            get: {
                preferences.recordingPillPosition
            },
            set: { newValue in
                preferences.recordingPillPosition = newValue
            }
        )
    }

    private func shortRamGuidance(for tier: RewriteModelTier) -> String {
        switch tier {
        case .standard2B:
            return "Any Mac"
        case .standard4B:
            return "8GB+"
        case .high9B:
            return "16GB+"
        }
    }

    private func conversionModelDetailText(
        for tier: RewriteModelTier,
        status: RewriteModelLoadState.TierStatus
    ) -> String {
        var details = [
            "\(String(format: "%.1f", tier.approximateDownloadSizeGB)) GB",
            shortRamGuidance(for: tier)
        ]

        if status.isDownloading {
            details.append("Downloading")
        } else if status.isDeleting {
            details.append("Deleting")
        } else if status.isWarm {
            details.append("Warm")
        } else if status.isDownloaded {
            details.append("Cold")
        } else {
            details.append("Not Downloaded")
        }

        return details.joined(separator: " · ")
    }

    @ViewBuilder
    private func conversionModelActionView(
        for tier: RewriteModelTier,
        status: RewriteModelLoadState.TierStatus
    ) -> some View {
        if status.isDownloading, modelLoadState.phase.activeTier == tier, let progress = modelLoadState.phase.downloadProgress {
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        } else if status.isDeleting {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else {
            let isDownloaded = status.isDownloaded
            Button {
                if isDownloaded {
                    modelLoadState.deleteModel(for: tier)
                } else {
                    modelLoadState.startDownload(for: tier)
                }
            } label: {
                Image(systemName: isDownloaded ? "trash" : "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isDownloaded ? Color.red : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(isAnyModelTransferInFlight || !canManageConversionModels)
            .help(
                canManageConversionModels
                    ? (isDownloaded ? "Delete downloaded model" : "Download model")
                    : "Wait for the current transcription to finish before changing conversion models"
            )
            .accessibilityIdentifier("conversionModel.\(tier.rawValue).action")
        }
    }

    @ViewBuilder
    private func conversionModelRow(for tier: RewriteModelTier) -> some View {
        let isSelected = preferences.rewriteModelTier == tier
        let status = modelLoadState.status(for: tier)
        let isSelectable = status.isDownloaded
        let rowOpacity = isSelectable ? 1.0 : 0.5

        HStack(alignment: .top, spacing: 12) {
            Button {
                preferences.rewriteModelTier = tier
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected && isSelectable ? Color.accentColor : .secondary)

                    Text(tier.displayName)
                        .foregroundStyle(isSelectable ? .primary : .secondary)

                    Spacer(minLength: 12)

                    Text(conversionModelDetailText(for: tier, status: status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
                .opacity(rowOpacity)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable || !canManageConversionModels || isAnyModelTransferInFlight)
            .help(
                canManageConversionModels
                    ? "Select this conversion model for future rewrites"
                    : "Wait for the current transcription to finish before changing conversion models"
            )
            .accessibilityIdentifier("conversionModel.\(tier.rawValue).select")

            conversionModelActionView(for: tier, status: status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelectable
                        ? (isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                        : Color.primary.opacity(0.025)
                )
        )
        .accessibilityIdentifier("conversionModel.\(tier.rawValue)")
    }

    private func whisperModelDetailText(
        for model: WhisperModelChoice,
        status: WhisperModelLoadState.ModelStatus
    ) -> String {
        var details = [model.detailSummary]

        if status.isDownloading {
            details.append("Downloading")
        } else if status.isPrewarming {
            details.append("Loading")
        } else if status.isDeleting {
            details.append("Deleting")
        } else if status.isLoading {
            details.append("Loading")
        } else if status.isWarm {
            details.append("Warm")
        } else if status.isDownloaded {
            details.append("Cold")
        } else {
            details.append("Not Downloaded")
        }

        return details.joined(separator: " · ")
    }

    @ViewBuilder
    private func whisperModelActionView(
        for model: WhisperModelChoice,
        status: WhisperModelLoadState.ModelStatus
    ) -> some View {
        if status.isDownloading,
           whisperModelLoadState.phase.activeModel == model,
           let progress = whisperModelLoadState.phase.downloadProgress {
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        } else if status.isDeleting || status.isLoading || status.isPrewarming {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else {
            let isDownloaded = status.isDownloaded
            Button {
                if isDownloaded {
                    whisperModelLoadState.deleteModel(for: model)
                } else {
                    whisperModelLoadState.startDownload(for: model)
                }
            } label: {
                Image(systemName: isDownloaded ? "trash" : "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isDownloaded ? Color.red : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(isAnyWhisperTransferInFlight)
            .help(isDownloaded ? "Delete downloaded model" : "Download model")
            .accessibilityIdentifier("whisperModel.\(model.rawValue).action")
        }
    }

    @ViewBuilder
    private func whisperModelRow(for model: WhisperModelChoice) -> some View {
        let isSelected = preferences.whisperModel == model
        let status = whisperModelLoadState.status(for: model)
        let isSelectable = status.isDownloaded
        let rowOpacity = isSelectable ? 1.0 : 0.5

        HStack(alignment: .top, spacing: 12) {
            Button {
                preferences.whisperModel = model
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected && isSelectable ? Color.accentColor : .secondary)

                    Text(model.displayName)
                        .foregroundStyle(isSelectable ? .primary : .secondary)

                    Spacer(minLength: 12)

                    Text(whisperModelDetailText(for: model, status: status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
                .opacity(rowOpacity)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)
            .accessibilityIdentifier("whisperModel.\(model.rawValue).select")

            whisperModelActionView(for: model, status: status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelectable
                        ? (isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                        : Color.primary.opacity(0.025)
                )
        )
        .accessibilityIdentifier("whisperModel.\(model.rawValue)")
    }

    init(
        preferences: ShellPreferences,
        readinessStore: ReadinessStore,
        updatePillPositionPreview: @escaping (RecordingPillPosition?) -> Void,
        dismissWindow: @escaping () -> Void,
        openGuide: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.readinessStore = readinessStore
        self.updatePillPositionPreview = updatePillPositionPreview
        self.dismissWindow = dismissWindow
        self.openGuide = openGuide
        _assistantSettingsViewModel = StateObject(
            wrappedValue: AIAssistantSettingsViewModel(preferences: preferences)
        )
    }

    // MARK: - Cloud LLM Settings

    @ViewBuilder
    private var cloudLLMSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Cloud LLM")
                    .font(.body)

                Spacer()

                Text("Use a cloud API instead of on-device models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Toggle("Enable cloud LLM for conversion", isOn: Binding(
                get: { preferences.cloudLLMConfig.isEnabled },
                set: { newValue in
                    preferences.cloudLLMConfig.isEnabled = newValue
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier("cloudLLM.enableToggle")

            if preferences.cloudLLMConfig.isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    // Provider picker
                    HStack(spacing: 8) {
                        Text("Provider:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        Picker("", selection: Binding(
                            get: { preferences.cloudLLMConfig.provider },
                            set: { newProvider in
                                preferences.cloudLLMConfig.provider = newProvider
                                preferences.cloudLLMConfig.baseURL = newProvider.defaultBaseURL
                                preferences.cloudLLMConfig.modelID = ""
                                cloudModels = []
                                cloudModelFetchError = nil
                                cloudConnectionTestResult = nil
                            }
                        )) {
                            ForEach(CloudLLMProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("cloudLLM.providerPicker")
                    }

                    // Base URL
                    HStack(spacing: 8) {
                        Text("Base URL:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        TextField(
                            "https://api.example.com/v1",
                            text: Binding(
                                get: { preferences.cloudLLMConfig.baseURL },
                                set: { preferences.cloudLLMConfig.baseURL = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("cloudLLM.baseURL")

                        if preferences.cloudLLMConfig.baseURL != preferences.cloudLLMConfig.provider.defaultBaseURL,
                           !preferences.cloudLLMConfig.provider.defaultBaseURL.isEmpty {
                            Button {
                                preferences.cloudLLMConfig.baseURL = preferences.cloudLLMConfig.provider.defaultBaseURL
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reset to default URL")
                        }
                    }

                    // API Key
                    HStack(spacing: 8) {
                        Text("API Key:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        SecureField("Enter API key", text: $cloudAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: cloudAPIKey) { _, newValue in
                                let provider = preferences.cloudLLMConfig.provider
                                _ = CloudLLMKeychain.saveAPIKey(newValue, for: provider)
                                cloudConnectionTestResult = nil
                            }
                            .accessibilityIdentifier("cloudLLM.apiKey")

                        if !cloudAPIKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.body)
                        }
                    }

                    // Model picker
                    HStack(spacing: 8) {
                        Text("Model:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        if cloudModels.isEmpty {
                            TextField(
                                "Model ID (e.g. gpt-4o)",
                                text: Binding(
                                    get: { preferences.cloudLLMConfig.modelID },
                                    set: { preferences.cloudLLMConfig.modelID = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("cloudLLM.modelIDField")
                        } else {
                            Picker("", selection: Binding(
                                get: { preferences.cloudLLMConfig.modelID },
                                set: { preferences.cloudLLMConfig.modelID = $0 }
                            )) {
                                Text("Select a model").tag("")
                                ForEach(cloudModels) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("cloudLLM.modelPicker")
                        }

                        if isLoadingCloudModels {
                            ProgressView()
                                .controlSize(.small)
                        } else if !cloudAPIKey.isEmpty {
                            Button("Fetch Models") {
                                fetchCloudModels()
                            }
                            .controlSize(.small)
                            .accessibilityIdentifier("cloudLLM.fetchModels")
                        }
                    }

                    if let error = cloudModelFetchError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Max tokens
                    HStack(spacing: 8) {
                        Text("Max tokens:")
                            .font(.body)
                            .frame(width: 70, alignment: .trailing)

                        TextField("", value: Binding(
                            get: { preferences.cloudLLMConfig.maxTokens },
                            set: { preferences.cloudLLMConfig.maxTokens = max(256, min(8192, $0)) }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .accessibilityIdentifier("cloudLLM.maxTokens")

                        Stepper("", value: Binding(
                            get: { preferences.cloudLLMConfig.maxTokens },
                            set: { preferences.cloudLLMConfig.maxTokens = max(256, min(8192, $0)) }
                        ), in: 256...8192, step: 256)
                        .labelsHidden()

                        Spacer()
                    }

                    // Test connection
                    HStack(spacing: 8) {
                        Spacer()
                            .frame(width: 70)

                        Button("Test Connection") {
                            testCloudConnection()
                        }
                        .controlSize(.small)
                        .disabled(cloudAPIKey.isEmpty || preferences.cloudLLMConfig.modelID.isEmpty)
                        .accessibilityIdentifier("cloudLLM.testConnection")

                        if let result = cloudConnectionTestResult {
                            switch result {
                            case .success:
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Connected")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            case .failed(let message):
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private var rewriteSystemPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Assistant System Prompt")
                    .font(.body)

                Spacer()

                Text("Applies to both on-device and cloud assistant generation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Text("This is the assistant system prompt for full-transcript requests. Use `{{assistant_name}}` to insert the active assistant name.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: rewriteSystemPromptBinding)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: RewriteSystemPromptSectionMetrics.editorHeight)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .accessibilityIdentifier("setupWindow.rewriteSystemPrompt.editor")

            HStack {
                Spacer()

                Button("Reset Prompt") {
                    preferences.rewriteSystemPromptPrefix = LLMRewriteService.defaultAssistantSystemPromptTemplate
                }
                .controlSize(.small)
                .disabled(
                    preferences.rewriteSystemPromptPrefix == LLMRewriteService.defaultAssistantSystemPromptTemplate
                )
                .accessibilityIdentifier("setupWindow.rewriteSystemPrompt.reset")
            }
        }
    }

    private func loadCloudAPIKeyIfNeeded() {
        guard !cloudAPIKeyLoaded else { return }
        cloudAPIKeyLoaded = true
        let provider = preferences.cloudLLMConfig.provider
        cloudAPIKey = CloudLLMKeychain.loadAPIKey(for: provider) ?? ""
    }

    private func fetchCloudModels() {
        let config = preferences.cloudLLMConfig
        let apiKey = cloudAPIKey
        isLoadingCloudModels = true
        cloudModelFetchError = nil

        Task {
            do {
                let models = try await CloudModelListService.fetchModels(
                    provider: config.provider,
                    baseURL: config.baseURL,
                    apiKey: apiKey
                )
                cloudModels = models
                isLoadingCloudModels = false
            } catch {
                cloudModelFetchError = error.localizedDescription
                isLoadingCloudModels = false
            }
        }
    }

    private func testCloudConnection() {
        let config = preferences.cloudLLMConfig
        let apiKey = cloudAPIKey
        cloudConnectionTestResult = nil

        Task {
            let service = CloudLLMRewriteService(config: config, apiKey: apiKey)
            do {
                _ = try await service.generate(
                    prompt: "Hello",
                    systemPrompt: LLMRewriteService.resolveAssistantSystemPrompt(
                        promptTemplate: preferences.rewriteSystemPromptPrefix,
                        assistantName: preferences.activeTriggerProfile.activePrimary
                    )
                )
                cloudConnectionTestResult = .success
            } catch {
                let message = (error as? LLMRewriteError)?.errorDescription ?? error.localizedDescription
                cloudConnectionTestResult = .failed(message)
            }
        }
    }

    private func configureSetupWindowSize() {
        guard let window = NSApp.windows.first(where: {
            $0.identifier == NSUserInterfaceItemIdentifier("TypeLessBuddySetupWindow")
        }) else {
            return
        }

        window.setContentSize(
            NSSize(
                width: SetupWindowMetrics.width,
                height: SetupWindowMetrics.collapsedHeight
            )
        )
    }

    private func updateActiveSection(using offsets: [SettingsSection: CGFloat]) {
        guard let nearest = offsets.min(by: { abs($0.value - 12) < abs($1.value - 12) })?.key else {
            return
        }
        activeSection = nearest
    }

    private func scrollToSection(_ section: SettingsSection, proxy: ScrollViewProxy) {
        activeSection = section
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(section, anchor: .top)
        }

        scheduledFlashTask?.cancel()
        scheduledFlashTask = Task { @MainActor in
            // Slightly delay so the highlight happens after the scroll settles (or immediately if no scroll is needed).
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            flashedSection = section
            flashNonce &+= 1
        }
    }

    private func flashTrigger(for section: SettingsSection) -> Int {
        flashedSection == section ? flashNonce : 0
    }

    @ViewBuilder
    private func trackedSection<Content: View>(
        _ section: SettingsSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SectionOffsetPreferenceKey.self,
                        value: [section: geometry.frame(in: .named("settingsScroll")).minY]
                    )
                }
            )
            // `.id` must come after modifiers like `.background` so the *outer* wrapper gets stable identity.
            .id(section)
    }

    private var setupSectionContent: some View {
        SettingsSectionCard(section: .setup, flashTrigger: flashTrigger(for: .setup)) {
            VStack(alignment: .leading, spacing: 16) {
                setupModelStatusContent

                PermissionChecklistView(
                    permissions: readinessStore.snapshot.permissions,
                    requestPermission: { kind in readinessStore.requestPermission(for: kind) },
                    openRecovery: { kind in readinessStore.openRecovery(for: kind) },
                    launchAtLoginEnabled: preferences.launchAtLogin,
                    onToggleLaunchAtLogin: { preferences.setLaunchAtLogin($0) }
                )
            }
        }
    }

    @ViewBuilder
    private var setupModelStatusContent: some View {
        if case .downloading(let model, let progress) = whisperModelLoadState.phase,
           model == preferences.whisperModel {
            ModelDownloadStatusRow(
                title: "Preparing speech model",
                message: "\(model.displayName) is downloading in the background and will be ready for first use when complete.",
                progress: progress
            )
            .accessibilityIdentifier("setupWindow.setupStatus.whisperDownload")
        } else if case .prewarming(let model) = whisperModelLoadState.phase,
                  model == preferences.whisperModel {
            ModelDownloadStatusRow(
                title: "Loading speech model",
                message: "\(model.displayName) is being compiled for your hardware. This only happens once.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.whisperPrewarm")
        }

        if case .downloading(let tier, let progress) = modelLoadState.phase,
           tier == preferences.rewriteModelTier {
            ModelDownloadStatusRow(
                title: "Preparing conversion model",
                message: "\(tier.displayName) is downloading in the background and will be ready for rewrites when complete.",
                progress: progress
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewriteDownload")
        }
    }

    private var generalSectionContent: some View {
        SettingsSectionCard(section: .general, flashTrigger: flashTrigger(for: .general)) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    SetupFieldRow(title: "Microphone") {
                        Picker("", selection: microphoneSelection) {
                            Text("System Default").tag(Optional<String>.none)
                            ForEach(audioDeviceService.availableDevices) { device in
                                Text(device.name).tag(Optional(device.uid))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 240, alignment: .leading)
                    }

                    SetupFieldRow(title: "Auto Paste") {
                        AlwaysAutoPasteRow(isOn: alwaysAutoPasteBinding)
                    }

                    SetupFieldRow(title: "Restore Clipboard") {
                        RestoreClipboardRow(
                            isOn: restorePreviousClipboardBinding,
                            isAutoPasteEnabled: preferences.alwaysAutoPaste
                        )
                    }

                    SetupFieldRow(title: "Play sound effects") {
                        PlaySoundEffectsRow(isOn: playSoundEffectsBinding)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    Text("Pill Position")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .center)

                    PillPositionPickerRow(
                        selection: recordingPillPositionBinding,
                        onHoverChange: updatePillPositionPreview
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(width: 180, alignment: .center)
            }
        }
    }

    private var assistantSectionContent: some View {
        SettingsSectionCard(section: .assistant, flashTrigger: flashTrigger(for: .assistant)) {
            SetupFieldRow(title: "Assistant name") {
                HStack(alignment: .center, spacing: 12) {
                    AssistantDisplayedNameChip(
                        name: assistantSettingsViewModel.displayedName,
                        isPreviewing: assistantSettingsViewModel.isPreviewingRecordedName
                    )
                    .accessibilityIdentifier("assistantRow.activeName")

                    Spacer(minLength: 12)

                    AIAssistantInlineRowView(
                        viewModel: assistantSettingsViewModel,
                        showsActiveName: false,
                        showsResetButton: false,
                        idleRecordButtonTitle: "Record Name"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var replacementsSectionContent: some View {
        SettingsSectionCard(section: .replacements, flashTrigger: flashTrigger(for: .replacements)) {
            ReplacementsSectionView(preferences: preferences)
        }
    }

    private var shortcutsSectionContent: some View {
        SettingsSectionCard(section: .shortcuts, flashTrigger: flashTrigger(for: .shortcuts)) {
            VStack(alignment: .leading, spacing: 14) {
                SetupFieldRow(title: "Start recording") {
                    HStack(spacing: 12) {
                        KeyComboRecorder(name: .activate, preferences: preferences)
                        KeyComboRecorder(name: .activateAlt, preferences: preferences)
                    }
                }

                SetupFieldRow(title: "Stop recording") {
                    HStack(spacing: 12) {
                        KeyComboRecorder(name: .stopSession, preferences: preferences)
                        KeyComboRecorder(name: .stopSessionAlt, preferences: preferences)
                    }
                }

                KeyboardShortcutsRow(
                    preferences: preferences
                )
            }
        }
    }

    private var advancedSectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isAdvancedSettingsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text("Advanced")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isAdvancedSettingsExpanded ? 45 : 0))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("setupWindow.advancedDisclosure")

            if isAdvancedSettingsExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Speech Transcription Model")
                                .font(.body)

                            Spacer()

                            Text("Select a downloaded model. Use the icon to download it or remove its files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        ForEach(WhisperModelChoice.allCases) { model in
                            whisperModelRow(for: model)
                        }

                        if case .failed(_, let message) = whisperModelLoadState.phase {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Conversion Model")
                                .font(.body)

                            Spacer()

                            Text("Select a downloaded model. Use the icon to download it or remove its files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        ForEach(RewriteModelTier.allCases) { tier in
                            conversionModelRow(for: tier)
                        }

                        if case .failed(_, let message) = modelLoadState.phase {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if !canManageConversionModels {
                            Text("Wait for the current recording or transcription to finish before downloading, deleting, or switching conversion models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .opacity(preferences.cloudLLMConfig.isEnabled ? 0.5 : 1.0)
                    .disabled(preferences.cloudLLMConfig.isEnabled)

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    rewriteSystemPromptSection

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    cloudLLMSettingsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(Color(white: 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .modifier(
            SettingsCardFlashModifier(
                cornerRadius: SettingsLayoutMetrics.cardCornerRadius,
                flashTrigger: flashTrigger(for: .advanced)
            )
        )
        .accessibilityIdentifier("setupWindow.section.advanced")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("TypeLessBuddy Settings")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("setupWindow.title")

                    Spacer()

                    Button("Guide") {
                        openGuide()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("setupWindow.guideButton")
                }

                ScrollViewReader { proxy in
                    HStack(alignment: .top, spacing: SettingsLayoutMetrics.contentSpacing) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(SettingsSection.allCases) { section in
                                SettingsSidebarButton(
                                    section: section,
                                    isActive: activeSection == section
                                ) {
                                    scrollToSection(section, proxy: proxy)
                                }
                            }
                        }
                        .frame(width: SettingsLayoutMetrics.sidebarWidth, alignment: .topLeading)
                        .accessibilityIdentifier("setupWindow.sidebar")

                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                trackedSection(.setup) {
                                    setupSectionContent
                                }

                                trackedSection(.general) {
                                    generalSectionContent
                                }

                                trackedSection(.assistant) {
                                    assistantSectionContent
                                }

                                trackedSection(.replacements) {
                                    replacementsSectionContent
                                }

                                trackedSection(.shortcuts) {
                                    shortcutsSectionContent
                                }

                                trackedSection(.advanced) {
                                    advancedSectionContent
                                }
                            }
                            .padding(.trailing, 4)
                            .onPreferenceChange(SectionOffsetPreferenceKey.self) { offsets in
                                updateActiveSection(using: offsets)
                            }
                        }
                        .coordinateSpace(name: "settingsScroll")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(spacing: 12) {
                Button("Quit App") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(.red)

                Spacer()

                Button("Reset") {
                    KeyboardShortcuts.reset(.activate, .activateAlt, .stopSession, .stopSessionAlt)
                    preferences.holdShortcutKeyCode = Int(kVK_RightOption)
                    preferences.holdShortcutModifiers = 0
                    preferences.holdShortcutKeyCodeAlt = -1
                    preferences.holdShortcutModifiersAlt = 0
                    HotkeyService.shared.configureHoldTarget()
                    preferences.micDeviceUIDs = []
                    preferences.whisperModel = .smallEN
                    preferences.muteSoundEffects = false
                }

                Button("Close") {
                    dismissWindow()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("setupWindow.primaryAction")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(
            minWidth: SetupWindowMetrics.width,
            maxWidth: SetupWindowMetrics.width,
            minHeight: SetupWindowMetrics.collapsedHeight
        )
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .preferredColorScheme(.dark)
        .onAppear {
            audioDeviceService.refresh()
            readinessStore.refresh()
            modelLoadState.refreshStatus()
            whisperModelLoadState.refreshStatus()
            configureSetupWindowSize()
            loadCloudAPIKeyIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            updatePillPositionPreview(nil)
            assistantSettingsViewModel.handleSettingsDismissed()
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            readinessStore.refresh()
            modelLoadState.refreshStatus()
            whisperModelLoadState.refreshStatus()
        }
        .onChange(of: preferences.rewriteModelTier) { _ in
            modelLoadState.refreshStatus()
        }
        .onChange(of: preferences.whisperModel) { _ in
            whisperModelLoadState.refreshStatus()
        }
        .onChange(of: preferences.cloudLLMConfig.provider) { _, _ in
            cloudAPIKeyLoaded = false
            loadCloudAPIKeyIfNeeded()
            cloudModels = []
            cloudModelFetchError = nil
            cloudConnectionTestResult = nil
        }
    }
}
