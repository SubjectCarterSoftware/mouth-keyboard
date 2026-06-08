import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

enum SetupWindowMetrics {
    static let width: CGFloat = 920
    static let collapsedHeight: CGFloat = 780
}

enum CloudConnectionTestResult: Equatable {
    case success(String)
    case failed(String)
}

enum CloudSettingsSaveResult: Equatable {
    case success(String)
    case failed(String)
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case assistant
    case replacements
    case notes
    case history
    case permissions
    case advanced

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .assistant:
            return "Assistant"
        case .notes:
            return "Note Saving"
        case .replacements:
            return "Word Replacements"
        case .shortcuts:
            return "Hotkeys"
        case .history:
            return "Historical Transcripts"
        case .permissions:
            return "System Permissions"
        case .advanced:
            return "Advanced"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .replacements:
            return "Word Replacements"
        case .notes:
            return "Note Saving"
        case .shortcuts:
            return "Hotkeys"
        case .history:
            return "Historical Transcripts"
        case .permissions:
            return "System Permissions"
        default:
            return title
        }
    }
}

enum SetupWindowMode: Equatable {
    case settings
    case onboarding
}

private enum OnboardingStep: String, CaseIterable, Identifiable {
    case microphone
    case shortcuts
    case pillPosition
    case accessibility
    case vocabularyPacks
    case speechEngine

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .microphone:
            return "Microphone Access"
        case .shortcuts:
            return "Keyboard Shortcuts"
        case .pillPosition:
            return "Pill Position"
        case .accessibility:
            return "Accessibility Permission"
        case .vocabularyPacks:
            return "Tailor Your Vocabulary"
        case .speechEngine:
            return "Preparing Local Models"
        }
    }

    var subtitle: String {
        switch self {
        case .microphone:
            return "Grant microphone access first, then choose the input device TypeLessBuddy should use."
        case .shortcuts:
            return "Configure the shortcuts now so they are ready as soon as setup finishes."
        case .pillPosition:
            return "Pick where the recording pill should appear on screen."
        case .accessibility:
            return "Accessibility is required for full cross-app control and unlocks auto-paste when you want it. Global keyboard and mouse triggers may also depend on macOS input event access."
        case .vocabularyPacks:
            return "Pick the roles that fit you. We'll auto-correct the jargon, tools, and brand names you say most — like \"TypeScript\" or \"Figma\"."
        case .speechEngine:
            return "The speech transcription model and local assistant model are being prepared in the background. Once both are ready, setup can finish."
        }
    }

    var continueTitle: String {
        switch self {
        case .speechEngine:
            return "Finish Setup"
        default:
            return "Continue"
        }
    }

    var symbolName: String {
        switch self {
        case .microphone:
            return "mic.fill"
        case .shortcuts:
            return "command"
        case .pillPosition:
            return "rectangle.inset.filled.and.person.filled"
        case .accessibility:
            return "figure.wave"
        case .vocabularyPacks:
            return "text.book.closed"
        case .speechEngine:
            return "cpu"
        }
    }

    var footerNote: String {
        switch self {
        case .microphone:
            return "Approve microphone access first, then choose the input device you want TypeLessBuddy to use."
        case .shortcuts:
            return "Set the shortcuts now so they are ready as soon as the remaining permissions are granted."
        case .pillPosition:
            return "Choose a position that stays visible without covering the apps you use most."
        case .accessibility:
            return "Accessibility is required for the full control flow and underpins auto-paste when you want it. Global keyboard and mouse triggers may also depend on macOS input event access."
        case .vocabularyPacks:
            return "Optional — you can change these any time in Word Replacements."
        case .speechEngine:
            return "This step waits for the first-time preparation of the speech transcription model and the local assistant model."
        }
    }
}

private enum SettingsLayoutMetrics {
    static let sidebarWidth: CGFloat = 172
    static let contentSpacing: CGFloat = 18
    static let cardCornerRadius: CGFloat = 18
    static let shortcutRecorderWidth: CGFloat = 145
}

enum SetupColorPalette {
    static let appBackground = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let cardBackground = Color(red: 0.15, green: 0.16, blue: 0.18)
    static let raisedControlBackground = Color(red: 0.20, green: 0.21, blue: 0.23)
    static let cardBorder = Color.white.opacity(0.10)
    static let controlBorder = Color.white.opacity(0.14)
}

private struct AssistantSystemPromptSheet: View {
    @Binding var prompt: String
    let onLoadFromFile: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Assistant System Prompt")
                .font(.title3.weight(.semibold))

            TextEditor(text: $prompt)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 320)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SetupColorPalette.raisedControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
                )
                .accessibilityIdentifier("setupWindow.rewriteSystemPrompt.editor")

            HStack(spacing: 10) {
                Button("Load from File…") {
                    onLoadFromFile()
                }

                Button("Reset") {
                    prompt = LocalRewriteService.defaultAssistantSystemPromptTemplate
                }
                .disabled(prompt == LocalRewriteService.defaultAssistantSystemPromptTemplate)
                .accessibilityIdentifier("setupWindow.rewriteSystemPrompt.reset")

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 430)
    }
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

// MARK: - Key combo recorder (Start / Stop shortcuts)

private struct KeyComboRecorder: View {
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

private struct MouseButtonRecorder: View {
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

private enum SetupSectionMetrics {
    static let rowLabelWidth: CGFloat = 150
    static let rowIndent: CGFloat = 4
}

private enum SettingsSectionHeaderAccessoryPlacement {
    case inline
    case trailing
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

private struct SettingsSectionCard<Content: View, HeaderAccessory: View>: View {
    let section: SettingsSection
    let flashTrigger: Int
    let headerAccessoryPlacement: SettingsSectionHeaderAccessoryPlacement
    let headerAccessory: HeaderAccessory
    let content: Content

    init(section: SettingsSection, flashTrigger: Int = 0, @ViewBuilder content: () -> Content)
    where HeaderAccessory == EmptyView {
        self.section = section
        self.flashTrigger = flashTrigger
        self.headerAccessoryPlacement = .trailing
        self.headerAccessory = EmptyView()
        self.content = content()
    }

    init(
        section: SettingsSection,
        flashTrigger: Int = 0,
        headerAccessoryPlacement: SettingsSectionHeaderAccessoryPlacement = .trailing,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.section = section
        self.flashTrigger = flashTrigger
        self.headerAccessoryPlacement = headerAccessoryPlacement
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(section.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("setupWindow.section.\(section.rawValue).title")

                if headerAccessoryPlacement == .inline {
                    headerAccessory
                }

                Spacer(minLength: 12)

                if headerAccessoryPlacement == .trailing {
                    headerAccessory
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(SetupColorPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SetupColorPalette.cardBorder, lineWidth: 1)
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

private struct SettingsSectionActionButton: View {
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(SetupColorPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SetupColorPalette.cardBorder, lineWidth: 1)
        )
    }
}

private enum OnboardingBadgeTone {
    case neutral
    case success
    case warning
    case danger

    var foregroundStyle: Color {
        switch self {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }

    var backgroundStyle: Color {
        switch self {
        case .neutral:
            return Color.white.opacity(0.08)
        case .success:
            return Color.green.opacity(0.15)
        case .warning:
            return Color.orange.opacity(0.16)
        case .danger:
            return Color.red.opacity(0.16)
        }
    }
}

private struct OnboardingStatusBadge: View {
    let title: String
    let tone: OnboardingBadgeTone

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foregroundStyle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.backgroundStyle, in: Capsule())
    }
}

private struct OnboardingFeatureCard<Content: View>: View {
    let systemImage: String
    let title: String
    var badgeTitle: String? = nil
    var badgeTone: OnboardingBadgeTone = .neutral
    var isHighlighted = false
    let content: Content

    init(
        systemImage: String,
        title: String,
        badgeTitle: String? = nil,
        badgeTone: OnboardingBadgeTone = .neutral,
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.systemImage = systemImage
        self.title = title
        self.badgeTitle = badgeTitle
        self.badgeTone = badgeTone
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                Spacer(minLength: 12)

                if let badgeTitle {
                    OnboardingStatusBadge(title: badgeTitle, tone: badgeTone)
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.08) : Color(white: 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isHighlighted ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
    }
}

private struct OnboardingNoteBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct OnboardingChecklistItem: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingPillPreviewCard: View {
    let position: RecordingPillPosition

    private var alignment: Alignment {
        switch position {
        case .topLeft:
            return .topLeading
        case .topCenter:
            return .top
        case .topRight:
            return .topTrailing
        case .centerLeft:
            return .leading
        case .centerRight:
            return .trailing
        case .bottomLeft:
            return .bottomLeading
        case .bottomCenter:
            return .bottom
        case .bottomRight:
            return .bottomTrailing
        }
    }

    private var previewPadding: EdgeInsets {
        switch position {
        case .topLeft:
            return EdgeInsets(top: 22, leading: 22, bottom: 0, trailing: 0)
        case .topCenter:
            return EdgeInsets(top: 22, leading: 0, bottom: 0, trailing: 0)
        case .topRight:
            return EdgeInsets(top: 22, leading: 0, bottom: 0, trailing: 22)
        case .centerLeft:
            return EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 0)
        case .centerRight:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 22)
        case .bottomLeft:
            return EdgeInsets(top: 0, leading: 22, bottom: 22, trailing: 0)
        case .bottomCenter:
            return EdgeInsets(top: 0, leading: 0, bottom: 22, trailing: 0)
        case .bottomRight:
            return EdgeInsets(top: 0, leading: 0, bottom: 22, trailing: 22)
        }
    }

    var body: some View {
        OnboardingFeatureCard(
            systemImage: "display",
            title: "Preview",
            badgeTitle: position.displayName,
            badgeTone: .neutral
        ) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                .frame(minHeight: 240)
                .overlay(alignment: alignment) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text("Listening…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .padding(previewPadding)
                }
        }
    }
}

private struct OnboardingPermissionCard: View {
    let item: PermissionChecklistItem
    let headline: String
    let message: String
    let actionTitle: String
    let requestPermission: (PermissionKind) -> Void
    let openRecovery: (PermissionKind) -> Void

    @State private var showsSetupGuide = false

    private var badgeTone: OnboardingBadgeTone {
        switch item.status {
        case .authorized:
            return .success
        case .notDetermined:
            return .warning
        case .denied:
            return .danger
        }
    }

    var body: some View {
        OnboardingFeatureCard(
            systemImage: item.kind.systemImage,
            title: headline,
            badgeTitle: item.status.label,
            badgeTone: badgeTone,
            isHighlighted: true
        ) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if item.isAuthorized {
                Label("Permission granted. You can continue when you are ready.", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle) {
                    handleAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .popover(isPresented: $showsSetupGuide, arrowEdge: .bottom) {
                    setupGuide
                }
            }
        }
    }

    private func handleAction() {
        if item.kind == .postEvent && item.status == .notDetermined {
            showsSetupGuide = true
        } else if item.status == .denied {
            openRecovery(item.kind)
        } else {
            requestPermission(item.kind)
        }
    }

    @ViewBuilder
    private var setupGuide: some View {
        AccessibilitySetupGuide {
            showsSetupGuide = false
            if item.status == .denied {
                openRecovery(item.kind)
            } else {
                requestPermission(item.kind)
            }
        }
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
            .onChange(of: flashTrigger) { _, newValue in
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
                    defaultKeyCode: ShellPreferences.defaultHoldShortcutKeyCode,
                    defaultModifiers: ShellPreferences.defaultHoldShortcutModifiers,
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
                        preferences.holdShortcutKeyCode = ShellPreferences.defaultHoldShortcutKeyCode
                        preferences.holdShortcutModifiers = ShellPreferences.defaultHoldShortcutModifiers
                        HotkeyService.shared.configureHoldTarget()
                    }
                )

                HoldShortcutRecorder(
                    slot: .secondary,
                    preferences: preferences,
                    keyCode: preferences.holdShortcutKeyCodeAlt,
                    modifiers: preferences.holdShortcutModifiersAlt,
                    defaultKeyCode: ShellPreferences.defaultHoldShortcutKeyCodeAlt,
                    defaultModifiers: ShellPreferences.defaultHoldShortcutModifiersAlt,
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
                        preferences.holdShortcutKeyCodeAlt = ShellPreferences.defaultHoldShortcutKeyCodeAlt
                        preferences.holdShortcutModifiersAlt = ShellPreferences.defaultHoldShortcutModifiersAlt
                        HotkeyService.shared.configureHoldTarget()
                    }
                )

                MouseButtonRecorder(
                    action: .holdToRecord,
                    preferences: preferences,
                    binding: preferences.holdMouseButtonBinding,
                    accessibilityID: "setupWindow.holdShortcut.mouseRecorder",
                    onRecord: { binding in
                        preferences.holdMouseButtonBinding = binding
                        HotkeyService.shared.configureMouseBindings()
                    },
                    onClear: {
                        preferences.holdMouseButtonBinding = nil
                        HotkeyService.shared.configureMouseBindings()
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

private struct NoteCaptureModeRow: View {
    @Binding var mode: AssistantNoteMode

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            NoteCaptureModeOption(
                title: "New note file every time",
                isSelected: mode == .newFile,
                accessibilityIdentifier: "setupWindow.notes.mode.newFile"
            ) {
                mode = .newFile
            }

            NoteCaptureModeOption(
                title: "Append to a single file",
                isSelected: mode == .appendToFile,
                accessibilityIdentifier: "setupWindow.notes.mode.appendToFile"
            ) {
                mode = .appendToFile
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setupWindow.notes.mode")
    }
}

private struct NoteCaptureModeOption: View {
    let title: String
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.65) : SetupColorPalette.controlBorder,
                            lineWidth: 1
                        )
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct AssistantNoteDestinationRow: View {
    enum DestinationKind {
        case folder
        case file
    }

    private enum Metrics {
        static let rowSpacing: CGFloat = 8
        static let fieldSpacing: CGFloat = 2
        static let fieldHorizontalPadding: CGFloat = 10
        static let fieldVerticalPadding: CGFloat = 8
        static let fieldMinWidth: CGFloat = 280
        static let fieldIdealWidth: CGFloat = 360
        static let fieldMaxWidth: CGFloat = 420
    }

    let path: String
    let placeholder: String
    let destinationKind: DestinationKind
    let pathAccessibilityIdentifier: String
    let browseAccessibilityIdentifier: String
    let clearAccessibilityIdentifier: String
    let browseAction: () -> Void
    let clearAction: () -> Void
    var helperText: String? = nil
    var isClearDisabled: Bool? = nil

    private var displayPath: String {
        guard !path.isEmpty else { return placeholder }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private var symbolName: String {
        switch destinationKind {
        case .folder:
            return "folder.fill"
        case .file:
            return "doc.text.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.rowSpacing) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(path.isEmpty ? .secondary : Color.accentColor)

                Text(displayPath)
                    .font(.callout)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
                .padding(.horizontal, Metrics.fieldHorizontalPadding)
                .padding(.vertical, 6)
                .frame(
                    minWidth: Metrics.fieldMinWidth,
                    idealWidth: Metrics.fieldIdealWidth,
                    maxWidth: Metrics.fieldMaxWidth,
                    alignment: .leading
                )
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SetupColorPalette.raisedControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
                )
                .help(path.isEmpty ? placeholder : path)
                .accessibilityIdentifier(pathAccessibilityIdentifier)

            Button("Browse…", action: browseAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier(browseAccessibilityIdentifier)

            Button("Clear", action: clearAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isClearDisabled ?? path.isEmpty)
                .accessibilityIdentifier(clearAccessibilityIdentifier)

            if let helperText {
                ImmediateHelpIcon(text: helperText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryStorageLimitRow: View {
    @Binding var storageLimitMB: Int
    var usageText: String?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("", value: Binding(
                get: { storageLimitMB },
                set: { storageLimitMB = max(1, $0) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
            .accessibilityIdentifier("setupWindow.history.storageLimit")

            Stepper("", value: Binding(
                get: { storageLimitMB },
                set: { storageLimitMB = max(1, $0) }
            ), in: 1...10_000, step: 50)
            .labelsHidden()

            Text("MB")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let usageText {
                Text(usageText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("setupWindow.history.usage")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Humane date/time formatting shared by the history list and detail pane.
enum HistoryFormat {
    static func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMMd" : "MMMd yyyy"
        )
        return formatter.string(from: date)
    }

    static func time(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    static func meta(for date: Date?) -> String {
        guard let date else { return "Unknown date" }
        return "\(dayLabel(for: date)) at \(time(for: date))"
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }
}

private struct HistoryModeBadge: View {
    let mode: HistoryEntryMode
    var selected: Bool = false

    private var palette: (bg: Color, fg: Color) {
        if selected { return (Color.white.opacity(0.22), .white) }
        switch mode {
        case .raw: return (Color.white.opacity(0.09), .secondary)
        case .assistant: return (Color.accentColor.opacity(0.18), Color.accentColor)
        }
    }

    var body: some View {
        Text(mode.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(palette.bg))
            .foregroundStyle(palette.fg)
    }
}

private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.previewText.isEmpty ? "(empty transcription)" : entry.previewText)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    HistoryModeBadge(mode: entry.mode, selected: isSelected)
                    Text(HistoryFormat.time(for: entry.createdAt))
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.55)
                            : SetupColorPalette.raisedControlBackground
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : SetupColorPalette.controlBorder,
                        lineWidth: isSelected ? 1 : 0.75
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .padding(6)
                    .help("Delete entry")
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct HistoryFolderRow: View {
    let path: String
    let placeholder: String
    let showsResetAction: Bool
    let browseAction: () -> Void
    let resetAction: () -> Void

    private var displayPath: String {
        guard !path.isEmpty else { return placeholder }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: browseAction) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(path.isEmpty ? .secondary : Color.accentColor)

                    Text(displayPath)
                        .font(.callout)
                        .foregroundStyle(path.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SetupColorPalette.raisedControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(path.isEmpty ? placeholder : path)
            .accessibilityIdentifier("setupWindow.history.path")

            if showsResetAction {
                Button("Reset", action: resetAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("setupWindow.history.clear")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryDetailPane: View {
    let detail: HistoryEntryDetail?
    let copyLabel: String
    let copyAction: () -> Void
    let revealAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        Group {
            if let detail {
                VStack(alignment: .leading, spacing: 0) {
                    header(detail)
                    Divider().opacity(0.5)
                    ScrollView {
                        body(detail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                }
            } else {
                Text("Select a transcription to preview it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 280, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SetupColorPalette.raisedControlBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("setupWindow.history.preview")
    }

    private func header(_ detail: HistoryEntryDetail) -> some View {
        HStack(spacing: 8) {
            HistoryModeBadge(mode: detail.mode)
            Text(HistoryFormat.meta(for: detail.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("· \(HistoryFormat.wordCount(detail.primaryText)) words")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            Button(copyLabel, action: copyAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("setupWindow.history.copy")

            Button(action: revealAction) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Button(action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this entry")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func body(_ detail: HistoryEntryDetail) -> some View {
        if let assistant = detail.assistantOutput, !detail.rawTranscription.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                section(label: "Original", text: detail.rawTranscription, secondary: true)
                section(label: "Result", text: assistant, secondary: false)
            }
        } else {
            Text(detail.primaryText)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(label: String, text: String, secondary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)

            if secondary {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
            } else {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
    @State private var isPopoverPresented = false
    private let tooltipWidth: CGFloat = 260

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onHover { hovering in
                if isPopoverPresented != hovering {
                    isPopoverPresented = hovering
                }
            }
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: tooltipWidth, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SetupColorPalette.raisedControlBackground)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SetupColorPalette.controlBorder, lineWidth: 0.75)
                    }
                    .shadow(color: Color.black.opacity(0.18), radius: 12, y: 6)
                    .padding(2)
            }
            .accessibilityLabel(text)
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

private struct OnboardingProgressDots: View {
    let steps: [OnboardingStep]
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps) { step in
                Circle()
                    .fill(step == currentStep ? Color.accentColor : Color.white.opacity(0.18))
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(step == currentStep ? 0.35 : 0.08), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05), in: Capsule())
    }
}

private struct CompactSetupStatusChip: View {
    let title: String
    let status: PermissionGrantState
    let icon: String

    private var tintColor: Color {
        switch status {
        case .authorized:
            return .green
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tintColor)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(tintColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SetupWindowView: View {
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    let mode: SetupWindowMode
    private let historyCaptureService: any HistoryCapturing
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
    @State private var cloudSaveResult: CloudSettingsSaveResult?
    @State private var activeSection: SettingsSection = .general
    @State private var flashedSection: SettingsSection?
    @State private var flashNonce: Int = 0
    @State private var keyboardShortcutChangeNonce: Int = 0
    @State private var isShowingAssistantSystemPromptEditor = false
    @State private var isShowingClearAllReplacementsConfirmation = false
    @State private var scheduledFlashTask: Task<Void, Never>?
    @State private var isProgrammaticScroll = false
    @State private var onboardingStep: OnboardingStep = .microphone
    @State private var hasInitializedOnboardingStep = false
    @State private var historyEntries: [HistoryEntry] = []
    @State private var selectedHistoryEntryURL: URL?
    @State private var selectedHistoryDetail: HistoryEntryDetail?
    @State private var historySearchQuery = ""
    @State private var historyUsage: HistoryUsage?
    @State private var isShowingClearHistoryConfirmation = false
    @State private var historyLoadError: String?
    @State private var historyCopyConfirmationVisible = false
    @State private var historyCopyConfirmationTask: Task<Void, Never>?
    let updatePillPositionPreview: (RecordingPillPosition?) -> Void
    let dismissWindow: () -> Void
    let openGuide: () -> Void
    let completeOnboarding: () -> Void

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

    private var isAnyModelTransferInFlight: Bool {
        modelLoadState.phase.downloadProgress != nil || modelLoadState.deletingTier != nil
    }

    private var canManageConversionModels: Bool {
        activationStore.state.allowsRewriteModelManagement
    }

    private var isAnyWhisperTransferInFlight: Bool {
        whisperModelLoadState.phase.isTransferInFlight || whisperModelLoadState.deletingModel != nil
    }

    private var isGeneralSectionCustomized: Bool {
        !preferences.micDeviceUIDs.isEmpty
            || !preferences.alwaysAutoPaste
            || !preferences.restorePreviousClipboardAfterAutoPaste
            || preferences.muteSoundEffects
            || preferences.recordingPillPosition != .default
    }

    private var isKeyboardShortcutsCustomized: Bool {
        _ = keyboardShortcutChangeNonce

        let managedTapShortcuts: [KeyboardShortcuts.Name] = [
            .activate,
            .activateAlt,
            .stopSession,
            .stopSessionAlt,
        ]
        let hasCustomizedTapShortcut = managedTapShortcuts.contains {
            KeyboardShortcuts.getShortcut(for: $0) != $0.defaultShortcut
        }
        let hasCustomizedHoldShortcut =
            preferences.holdShortcutKeyCode != ShellPreferences.defaultHoldShortcutKeyCode
            || preferences.holdShortcutModifiers != ShellPreferences.defaultHoldShortcutModifiers
            || preferences.holdShortcutKeyCodeAlt != ShellPreferences.defaultHoldShortcutKeyCodeAlt
            || preferences.holdShortcutModifiersAlt != ShellPreferences.defaultHoldShortcutModifiersAlt
        let hasCustomizedMouseShortcut =
            preferences.startMouseButtonBinding != nil
            || preferences.stopMouseButtonBinding != nil
            || preferences.holdMouseButtonBinding != nil

        return hasCustomizedTapShortcut || hasCustomizedHoldShortcut || hasCustomizedMouseShortcut
    }

    private var hasWordReplacements: Bool {
        preferences.activeDictionaryData.replacements.contains { $0.sourcePackIDs.isEmpty }
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

    private var assistantNoteModeBinding: Binding<AssistantNoteMode> {
        Binding(
            get: {
                preferences.assistantNoteMode
            },
            set: { newValue in
                preferences.assistantNoteMode = newValue
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

    private var microphonePermissionItem: PermissionChecklistItem? {
        readinessStore.snapshot.permissions.first(where: { $0.kind == .microphone })
    }

    private var accessibilityPermissionItem: PermissionChecklistItem? {
        readinessStore.snapshot.permissions.first(where: { $0.kind == .postEvent })
    }

    private var isMicrophoneAuthorized: Bool {
        microphonePermissionItem?.isAuthorized ?? false
    }

    private var isAccessibilityAuthorized: Bool {
        accessibilityPermissionItem?.isAuthorized ?? false
    }

    private var speechEngineStatus: WhisperModelLoadState.ModelStatus {
        whisperModelLoadState.status(for: preferences.whisperModel)
    }

    private var isSpeechEngineReady: Bool {
        let status = speechEngineStatus
        return status.isDownloaded && !status.isDownloading && !status.isPrewarming && !status.isLoading && !status.isDeleting
    }

    private var selectedBuiltInAssistantTier: RewriteModelTier {
        preferences.rewriteModelTier
    }

    private var selectedBuiltInAssistantStatus: RewriteModelLoadState.TierStatus {
        modelLoadState.status(for: selectedBuiltInAssistantTier)
    }

    private var selectedAssistantModelDisplayName: String {
        selectedBuiltInAssistantTier.displayName
    }

    private var usesLocalAssistantModel: Bool {
        !preferences.cloudLLMConfig.isEnabled
    }

    private var isLocalAssistantModelReady: Bool {
        guard usesLocalAssistantModel else { return true }
        let status = selectedBuiltInAssistantStatus
        return status.isDownloaded && status.isPrepared && !status.isDownloading && !status.isPrewarming && !status.isDeleting
    }

    private var areOnboardingModelsReady: Bool {
        isSpeechEngineReady && isLocalAssistantModelReady
    }

    private var onboardingStepSequence: [OnboardingStep] {
        OnboardingStep.allCases
    }

    private var onboardingStepIndex: Int {
        (onboardingStepSequence.firstIndex(of: onboardingStep) ?? 0) + 1
    }

    private func badgeTone(for status: PermissionGrantState) -> OnboardingBadgeTone {
        switch status {
        case .authorized:
            return .success
        case .notDetermined:
            return .warning
        case .denied:
            return .danger
        }
    }

    private func requestPermission(_ kind: PermissionKind) {
        readinessStore.requestPermission(for: kind)
    }

    private func openPermissionRecovery(_ kind: PermissionKind) {
        readinessStore.openRecovery(for: kind)
    }

    private func microphoneActionTitle(for status: PermissionGrantState) -> String {
        switch status {
        case .authorized:
            return "Microphone Granted"
        case .notDetermined:
            return "Grant Microphone Access"
        case .denied:
            return "Open Microphone Settings"
        }
    }

    private func accessibilityActionTitle(for status: PermissionGrantState) -> String {
        switch status {
        case .authorized:
            return "Accessibility Granted"
        case .notDetermined:
            return "Grant Accessibility"
        case .denied:
            return "Open Accessibility Settings"
        }
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
        mode: SetupWindowMode,
        historyCaptureService: any HistoryCapturing = HistoryCaptureService(),
        updatePillPositionPreview: @escaping (RecordingPillPosition?) -> Void,
        dismissWindow: @escaping () -> Void,
        openGuide: @escaping () -> Void,
        completeOnboarding: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.readinessStore = readinessStore
        self.mode = mode
        self.historyCaptureService = historyCaptureService
        self.updatePillPositionPreview = updatePillPositionPreview
        self.dismissWindow = dismissWindow
        self.openGuide = openGuide
        self.completeOnboarding = completeOnboarding
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
                                cloudSaveResult = nil
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
                                set: {
                                    preferences.cloudLLMConfig.baseURL = $0
                                    cloudConnectionTestResult = nil
                                    cloudSaveResult = nil
                                }
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
                                cloudConnectionTestResult = nil
                                cloudSaveResult = nil
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
                                    set: {
                                        preferences.cloudLLMConfig.modelID = $0
                                        cloudConnectionTestResult = nil
                                        cloudSaveResult = nil
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("cloudLLM.modelIDField")
                        } else {
                            Picker("", selection: Binding(
                                get: { preferences.cloudLLMConfig.modelID },
                                set: {
                                    preferences.cloudLLMConfig.modelID = $0
                                    cloudConnectionTestResult = nil
                                    cloudSaveResult = nil
                                }
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
                        } else if !preferences.cloudLLMConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                            set: {
                                preferences.cloudLLMConfig.maxTokens = max(256, min(8192, $0))
                                cloudConnectionTestResult = nil
                                cloudSaveResult = nil
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .accessibilityIdentifier("cloudLLM.maxTokens")

                        Stepper("", value: Binding(
                            get: { preferences.cloudLLMConfig.maxTokens },
                            set: {
                                preferences.cloudLLMConfig.maxTokens = max(256, min(8192, $0))
                                cloudConnectionTestResult = nil
                                cloudSaveResult = nil
                            }
                        ), in: 256...8192, step: 256)
                        .labelsHidden()

                        Spacer()
                    }

                    // Test connection
                    HStack(spacing: 8) {
                        Spacer()
                            .frame(width: 70)

                        Button("Save") {
                            saveCloudSettings()
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("cloudLLM.save")

                        Button("Test Connection") {
                            testCloudConnection()
                        }
                        .controlSize(.small)
                        .disabled(preferences.cloudLLMConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("cloudLLM.testConnection")

                        if let saveResult = cloudSaveResult {
                            switch saveResult {
                            case .success(let message):
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(message)
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

                        if let result = cloudConnectionTestResult {
                            switch result {
                            case .success(let message):
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(message)
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

    private func loadCloudAPIKeyIfNeeded() {
        guard !cloudAPIKeyLoaded else { return }
        cloudAPIKeyLoaded = true
        let provider = preferences.cloudLLMConfig.provider
        cloudAPIKey = CloudLLMKeychain.loadAPIKey(for: provider) ?? ""
    }

    private func fetchCloudModels() {
        let config = preferences.cloudLLMConfig
        let apiKey = resolvedCloudRequestAPIKey(for: config.provider)
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

    private func saveCloudSettings() {
        let provider = preferences.cloudLLMConfig.provider
        let didSave = CloudLLMKeychain.saveAPIKey(cloudAPIKey, for: provider)
        cloudSaveResult = didSave
            ? .success("Saved")
            : .failed("Could not save API key")
    }

    private func resolvedCloudRequestAPIKey(for provider: CloudLLMProvider) -> String {
        let trimmed = cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        switch provider {
        case .custom:
            return "lm-studio"
        case .openAI, .anthropic, .google:
            return ""
        }
    }

    private func testCloudConnection() {
        let config = preferences.cloudLLMConfig
        let apiKey = resolvedCloudRequestAPIKey(for: config.provider)
        cloudConnectionTestResult = nil

        Task {
            do {
                if config.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let models = try await CloudModelListService.fetchModels(
                        provider: config.provider,
                        baseURL: config.baseURL,
                        apiKey: apiKey
                    )
                    cloudModels = models
                    if models.isEmpty {
                        cloudConnectionTestResult = .success("Connected")
                    } else {
                        cloudConnectionTestResult = .success("Connected (\(models.count) models)")
                    }
                } else {
                    let service = CloudRewriteService(config: config, apiKey: apiKey)
                    _ = try await service.generate(
                        prompt: "Hello",
                        systemPrompt: LocalRewriteService.resolveAssistantSystemPrompt(
                            promptTemplate: preferences.rewriteSystemPromptPrefix,
                            assistantName: preferences.activeTriggerProfile.activePrimary
                        )
                    )
                    cloudConnectionTestResult = .success("Connected")
                }
            } catch {
                let message = (error as? RewriteError)?.errorDescription ?? error.localizedDescription
                cloudConnectionTestResult = .failed(message)
            }
        }
    }

    private func chooseAssistantNoteFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Note Folder"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !preferences.assistantNoteFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: preferences.assistantNoteFolderPath, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.assistantNoteFolderPath = url.path
    }

    private func chooseAssistantNoteAppendFile() {
        let panel = NSSavePanel()
        panel.title = "Choose Append File"
        panel.prompt = "Choose File"
        panel.canCreateDirectories = true
        panel.allowedFileTypes = ["md", "markdown", "txt"]
        if !preferences.assistantNoteAppendFilePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: preferences.assistantNoteAppendFilePath)
                .deletingLastPathComponent()
            panel.nameFieldStringValue = URL(fileURLWithPath: preferences.assistantNoteAppendFilePath)
                .lastPathComponent
        } else {
            panel.nameFieldStringValue = "notes.md"
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.assistantNoteAppendFilePath = url.path
    }

    private func loadAssistantSystemPromptFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Load Assistant System Prompt"
        panel.prompt = "Load Prompt"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .plainText,
            .utf8PlainText,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText
        ]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            return
        }

        preferences.rewriteSystemPromptPrefix = String(decoding: data, as: UTF8.self)
    }

    private func chooseHistoryFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose History Folder"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(
            fileURLWithPath: preferences.historyConfiguration.resolvedFolderPath,
            isDirectory: true
        )

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.historyFolderPath = url.path
        reloadHistoryEntries()
    }

    private func reloadHistoryEntries() {
        historyCopyConfirmationTask?.cancel()
        historyCopyConfirmationVisible = false

        do {
            let entries = try historyCaptureService.listEntries(configuration: preferences.historyConfiguration)
            historyEntries = entries
            historyUsage = try? historyCaptureService.storageUsage(configuration: preferences.historyConfiguration)
            historyLoadError = nil

            if let selectedHistoryEntryURL,
               entries.contains(where: { $0.fileURL == selectedHistoryEntryURL }) {
                loadHistoryEntryDetail(for: selectedHistoryEntryURL)
                return
            }

            if let firstEntry = entries.first {
                selectedHistoryEntryURL = firstEntry.fileURL
                loadHistoryEntryDetail(for: firstEntry.fileURL)
            } else {
                selectedHistoryEntryURL = nil
                selectedHistoryDetail = nil
            }
        } catch {
            historyEntries = []
            historyUsage = nil
            selectedHistoryEntryURL = nil
            selectedHistoryDetail = nil
            historyLoadError = error.localizedDescription
        }
    }

    private func selectHistoryEntry(_ fileURL: URL) {
        selectedHistoryEntryURL = fileURL
        historyCopyConfirmationTask?.cancel()
        historyCopyConfirmationVisible = false
        loadHistoryEntryDetail(for: fileURL)
    }

    private func loadHistoryEntryDetail(for fileURL: URL) {
        do {
            selectedHistoryDetail = try historyCaptureService.loadEntryDetail(at: fileURL)
            historyLoadError = nil
            historyCopyConfirmationVisible = false
        } catch {
            selectedHistoryDetail = nil
            historyLoadError = error.localizedDescription
            historyCopyConfirmationVisible = false
        }
    }

    private func copySelectedHistoryEntry() {
        guard let text = selectedHistoryDetail?.primaryText, !text.isEmpty else {
            return
        }

        guard ClipboardService().writeToClipboard(text) else {
            return
        }

        historyCopyConfirmationTask?.cancel()
        historyCopyConfirmationVisible = true
        historyCopyConfirmationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            historyCopyConfirmationVisible = false
        }
    }

    private func deleteHistoryEntry(_ fileURL: URL) {
        do {
            try historyCaptureService.deleteEntry(at: fileURL)
            if selectedHistoryEntryURL == fileURL {
                selectedHistoryEntryURL = nil
                selectedHistoryDetail = nil
            }
            reloadHistoryEntries()
        } catch {
            historyLoadError = error.localizedDescription
        }
    }

    private func clearAllHistory() {
        do {
            try historyCaptureService.deleteAllEntries(configuration: preferences.historyConfiguration)
            selectedHistoryEntryURL = nil
            selectedHistoryDetail = nil
            reloadHistoryEntries()
        } catch {
            historyLoadError = error.localizedDescription
        }
    }

    private func revealHistoryFolder() {
        let url = URL(fileURLWithPath: preferences.historyConfiguration.resolvedFolderPath, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func revealHistoryEntry(_ fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Entries filtered by the search query (matched against the preview snippet).
    private var filteredHistoryEntries: [HistoryEntry] {
        let query = historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return historyEntries }
        return historyEntries.filter { $0.previewText.lowercased().contains(query) }
    }

    /// Filtered entries bucketed into day groups (Today / Yesterday / date), newest first.
    private var groupedHistoryEntries: [(label: String, entries: [HistoryEntry])] {
        var order: [String] = []
        var buckets: [String: [HistoryEntry]] = [:]
        for entry in filteredHistoryEntries {
            let label = HistoryFormat.dayLabel(for: entry.createdAt)
            if buckets[label] == nil {
                buckets[label] = []
                order.append(label)
            }
            buckets[label]?.append(entry)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private var historyUsageDescription: String? {
        guard let historyUsage else { return nil }
        let used = ByteCountFormatter.string(fromByteCount: historyUsage.totalBytes, countStyle: .file)
        return "\(used) used"
    }

    private func restoreDefaultGeneralSettings() {
        updatePillPositionPreview(nil)
        preferences.restoreDefaultGeneralSettings()
    }

    private func restoreDefaultKeyboardShortcuts() {
        KeyboardShortcuts.reset(.activate, .activateAlt, .stopSession, .stopSessionAlt)
        preferences.restoreDefaultHoldShortcuts()
        HotkeyService.shared.configureHoldTarget()
        HotkeyService.shared.configureMouseBindings()
        keyboardShortcutChangeNonce &+= 1
    }

    private func clearAllWordReplacements() {
        preferences.clearWordReplacements()
    }

    private func onTapShortcutChanged() {
        keyboardShortcutChangeNonce &+= 1
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
        guard !isProgrammaticScroll else { return }
        guard let nearest = offsets.min(by: { abs($0.value - 12) < abs($1.value - 12) })?.key else {
            return
        }
        activeSection = nearest
    }

    private func scrollToSection(_ section: SettingsSection, proxy: ScrollViewProxy) {
        activeSection = section
        isProgrammaticScroll = true
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
            // Allow scroll-based section tracking to resume after the flash starts.
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            isProgrammaticScroll = false
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

    private func isStepComplete(_ step: OnboardingStep) -> Bool {
        switch step {
        case .microphone:
            return isMicrophoneAuthorized
        case .shortcuts, .pillPosition, .vocabularyPacks:
            return true
        case .accessibility:
            return isAccessibilityAuthorized
        case .speechEngine:
            return areOnboardingModelsReady
        }
    }

    private func canResume(step: OnboardingStep) -> Bool {
        for candidate in onboardingStepSequence {
            if candidate == step {
                return true
            }

            guard isStepComplete(candidate) else {
                return false
            }
        }

        return true
    }

    private func firstIncompleteOnboardingStep() -> OnboardingStep? {
        onboardingStepSequence.first(where: { !isStepComplete($0) })
    }

    private func synchronizeOnboardingStepIfNeeded() {
        guard mode == .onboarding else { return }
        guard !hasInitializedOnboardingStep else { return }
        hasInitializedOnboardingStep = true

        if let resumeToken = preferences.onboardingResumeToken,
           let resumedStep = OnboardingStep(rawValue: resumeToken),
           canResume(step: resumedStep) {
            onboardingStep = resumedStep
            return
        }

        onboardingStep = firstIncompleteOnboardingStep() ?? .speechEngine
    }

    private func persistOnboardingProgress() {
        guard mode == .onboarding else { return }
        preferences.setOnboardingResumeToken(onboardingStep.rawValue)
    }

    private func advanceOnboarding() {
        if onboardingStep == .speechEngine {
            guard areOnboardingModelsReady else { return }
            completeOnboarding()
            return
        }

        guard let currentIndex = onboardingStepSequence.firstIndex(of: onboardingStep) else {
            return
        }

        let nextIndex = onboardingStepSequence.index(after: currentIndex)
        guard onboardingStepSequence.indices.contains(nextIndex) else {
            return
        }

        onboardingStep = onboardingStepSequence[nextIndex]
    }

    private func goBackOnboarding() {
        guard let currentIndex = onboardingStepSequence.firstIndex(of: onboardingStep),
              currentIndex > onboardingStepSequence.startIndex else {
            return
        }

        onboardingStep = onboardingStepSequence[onboardingStepSequence.index(before: currentIndex)]
    }

    private var canContinueOnboarding: Bool {
        switch onboardingStep {
        case .microphone:
            return isMicrophoneAuthorized
        case .shortcuts, .pillPosition, .vocabularyPacks:
            return true
        case .accessibility:
            return isAccessibilityAuthorized
        case .speechEngine:
            return areOnboardingModelsReady
        }
    }

    @ViewBuilder
    private var onboardingStepContent: some View {
        switch onboardingStep {
        case .microphone:
            onboardingMicrophoneStep
        case .shortcuts:
            onboardingShortcutsStep
        case .pillPosition:
            onboardingPillPositionStep
        case .accessibility:
            onboardingAccessibilityStep
        case .vocabularyPacks:
            onboardingVocabularyPacksStep
        case .speechEngine:
            onboardingSpeechEngineStep
        }
    }

    private var onboardingVocabularyPacksStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowLayout(spacing: 8) {
                ForEach(ReplacementPackCatalog.roles) { pack in
                    VocabularyPackPill(
                        pack: pack,
                        isOn: preferences.isPackEnabled(pack.id),
                        onToggle: {
                            preferences.setPack(pack, enabled: !preferences.isPackEnabled(pack.id))
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onboardingMicrophoneStep: some View {
        HStack(alignment: .top, spacing: 18) {
            if let microphonePermissionItem {
                OnboardingPermissionCard(
                    item: microphonePermissionItem,
                    headline: "Microphone Permission",
                    message: "TypeLessBuddy only records when you trigger it. Audio stays on-device, and this permission is required before anything else can work.",
                    actionTitle: microphoneActionTitle(for: microphonePermissionItem.status),
                    requestPermission: requestPermission,
                    openRecovery: openPermissionRecovery
                )
            }

            OnboardingFeatureCard(
                systemImage: "wave.3.left.circle.fill",
                title: "Preferred Microphone",
                badgeTitle: isMicrophoneAuthorized ? "Ready to pick" : "Locked",
                badgeTone: isMicrophoneAuthorized ? .neutral : .warning
            ) {
                if isMicrophoneAuthorized {
                    Text("Choose the input TypeLessBuddy should prefer whenever it is available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    MicPriorityPicker(
                        preferences: preferences,
                        audioDeviceService: audioDeviceService
                    )
                    .frame(maxWidth: 280, alignment: .leading)
                    .zIndex(10)
                } else {
                    Text("Approve microphone access first. As soon as macOS grants it, this card unlocks so you can choose the specific input device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var onboardingShortcutsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingNoteBanner(
                text: "Configure the shortcuts now so they are ready as soon as setup finishes."
            )

            OnboardingFeatureCard(
                systemImage: "command",
                title: "Shortcut Assignment",
                isHighlighted: true
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    SetupFieldRow(title: "Start recording") {
                        HStack(spacing: 12) {
                            KeyComboRecorder(name: .activate, preferences: preferences)
                            KeyComboRecorder(name: .activateAlt, preferences: preferences)
                            MouseButtonRecorder(
                                action: .startRecording,
                                preferences: preferences,
                                binding: preferences.startMouseButtonBinding,
                                accessibilityID: "setupWindow.activate.mouseRecorder",
                                onRecord: { binding in
                                    preferences.startMouseButtonBinding = binding
                                    HotkeyService.shared.configureMouseBindings()
                                },
                                onClear: {
                                    preferences.startMouseButtonBinding = nil
                                    HotkeyService.shared.configureMouseBindings()
                                }
                            )
                        }
                    }

                    SetupFieldRow(title: "Stop recording") {
                        HStack(spacing: 12) {
                            KeyComboRecorder(name: .stopSession, preferences: preferences)
                            KeyComboRecorder(name: .stopSessionAlt, preferences: preferences)
                            MouseButtonRecorder(
                                action: .stopRecording,
                                preferences: preferences,
                                binding: preferences.stopMouseButtonBinding,
                                accessibilityID: "setupWindow.stopSession.mouseRecorder",
                                onRecord: { binding in
                                    preferences.stopMouseButtonBinding = binding
                                    HotkeyService.shared.configureMouseBindings()
                                },
                                onClear: {
                                    preferences.stopMouseButtonBinding = nil
                                    HotkeyService.shared.configureMouseBindings()
                                }
                            )
                        }
                    }

                    KeyboardShortcutsRow(preferences: preferences)
                }
            }
        }
    }

    private var onboardingPillPositionStep: some View {
        HStack(alignment: .top, spacing: 18) {
            OnboardingFeatureCard(
                systemImage: "rectangle.inset.filled.and.person.filled",
                title: "Pill Position",
                badgeTitle: preferences.recordingPillPosition.displayName,
                badgeTone: .neutral,
                isHighlighted: true
            ) {
                Text("Place the recording pill where it is easiest to notice without covering the apps you use most.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    PillPositionPickerRow(
                        selection: recordingPillPositionBinding,
                        onHoverChange: updatePillPositionPreview
                    )
                    Spacer()
                }
            }

            OnboardingPillPreviewCard(position: preferences.recordingPillPosition)
        }
    }

    private var onboardingAccessibilityStep: some View {
        HStack(alignment: .top, spacing: 18) {
            if let accessibilityPermissionItem {
                OnboardingPermissionCard(
                    item: accessibilityPermissionItem,
                    headline: "Accessibility Permission",
                    message: "Accessibility is required for TypeLessBuddy’s full cross-app control behavior. It also unlocks auto-paste whenever you want to use it, while global keyboard and mouse triggers may also depend on macOS input event access.",
                    actionTitle: accessibilityActionTitle(for: accessibilityPermissionItem.status),
                    requestPermission: requestPermission,
                    openRecovery: openPermissionRecovery
                )
            }

            OnboardingFeatureCard(
                systemImage: "sparkles",
                title: "What this enables"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingChecklistItem(text: "Auto-paste into the focused app whenever you want it.")
                    OnboardingChecklistItem(text: "Reliable cross-app control after transcription finishes.")
                    OnboardingChecklistItem(text: "The permission foundation the shortcut flow depends on later.")
                }
            }
        }
    }

    private var onboardingSpeechEngineStep: some View {
        OnboardingFeatureCard(
            systemImage: "cpu",
            title: "Preparing Local Models",
            badgeTitle: areOnboardingModelsReady ? "Ready" : "In Progress",
            badgeTone: areOnboardingModelsReady ? .success : .warning,
            isHighlighted: true
        ) {
            Text("TypeLessBuddy already picked the right local models for this Mac. This step makes the first-time download and hardware preparation visible so setup does not finish before both are ready.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if areOnboardingModelsReady {
                Label(
                    "\(preferences.whisperModel.displayName) and \(selectedAssistantModelDisplayName) are downloaded and prepared for first use.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                speechModelStatusContent
                assistantModelStatusContent
            }
        }
    }

    private var onboardingBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 16) {
                    Button {
                        goBackOnboarding()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(onboardingStep == onboardingStepSequence.first ? .clear : .secondary)
                    .disabled(onboardingStep == onboardingStepSequence.first)

                    Spacer()

                    Text("Step \(onboardingStepIndex) of \(onboardingStepSequence.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .overlay {
                    OnboardingProgressDots(steps: onboardingStepSequence, currentStep: onboardingStep)
                }

                VStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.16))
                            .frame(width: 64, height: 64)

                        Image(systemName: onboardingStep.symbolName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .center, spacing: 8) {
                        Text(onboardingStep.title)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(onboardingStep.subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 660)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                onboardingStepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(alignment: .center, spacing: 16) {
                Text(onboardingStep.footerNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460, alignment: .leading)

                Spacer()

                Button("Quit App") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(.red)

                Button(onboardingStep.continueTitle) {
                    advanceOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinueOnboarding)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(SetupColorPalette.appBackground)
        }
    }

    private var permissionsSectionContent: some View {
        SettingsSectionCard(section: .permissions, flashTrigger: flashTrigger(for: .permissions)) {
            VStack(alignment: .leading, spacing: 16) {
                setupModelStatusContent
                PermissionChecklistView(
                    permissions: readinessStore.snapshot.permissions,
                    requestPermission: requestPermission,
                    openRecovery: openPermissionRecovery,
                    launchAtLoginEnabled: preferences.launchAtLogin,
                    onToggleLaunchAtLogin: { preferences.setLaunchAtLogin($0) },
                    usesGridLayout: true
                )
            }
        }
    }

    @ViewBuilder
    private var speechModelStatusContent: some View {
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
        } else if !speechEngineStatus.isDownloaded && !whisperModelLoadState.phase.isTransferInFlight {
            ModelDownloadStatusRow(
                title: "Speech transcription model",
                message: "\(preferences.whisperModel.displayName) is queued for download.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.whisperQueued")
        }
    }

    @ViewBuilder
    private var assistantModelStatusContent: some View {
        if !usesLocalAssistantModel {
            Label(
                "Cloud assistant mode is enabled, so local assistant model setup is skipped.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.green)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if case .downloading(let tier, let progress) = modelLoadState.phase,
                  tier == selectedBuiltInAssistantTier {
            ModelDownloadStatusRow(
                title: "Local assistant model",
                message: "\(tier.displayName) is downloading in the background and will be ready for assistant requests when complete.",
                progress: progress
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewriteDownload")
        } else if case .prewarming(let tier) = modelLoadState.phase,
                  tier == selectedBuiltInAssistantTier {
            ModelDownloadStatusRow(
                title: "Local assistant model",
                message: "\(tier.displayName) is being loaded and cached for first use. This only happens once.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewritePrewarm")
        } else if !selectedBuiltInAssistantStatus.isPrepared && !modelLoadState.phase.isTransferInFlight {
            ModelDownloadStatusRow(
                title: "Local assistant model",
                message: selectedBuiltInAssistantStatus.isDownloaded
                    ? "\(selectedAssistantModelDisplayName) is queued for first-time setup."
                    : "\(selectedAssistantModelDisplayName) is queued for download.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewriteQueued")
        }
    }

    @ViewBuilder
    private var setupModelStatusContent: some View {
        speechModelStatusContent

        if case .downloading(let tier, let progress) = modelLoadState.phase,
           tier == selectedBuiltInAssistantTier {
            ModelDownloadStatusRow(
                title: "Preparing local assistant model",
                message: "\(tier.displayName) is downloading in the background and will be ready for rewrites when complete.",
                progress: progress
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewriteDownload")
        } else if case .prewarming(let tier) = modelLoadState.phase,
                  tier == selectedBuiltInAssistantTier {
            ModelDownloadStatusRow(
                title: "Preparing local assistant model",
                message: "\(tier.displayName) is being loaded and cached for first use. This only happens once.",
                progress: nil
            )
            .accessibilityIdentifier("setupWindow.setupStatus.rewritePrewarm")
        }
    }

    private var generalSectionContent: some View {
        SettingsSectionCard(
            section: .general,
            flashTrigger: flashTrigger(for: .general)
        ) {
            SettingsSectionActionButton(
                title: "Restore Defaults",
                accessibilityIdentifier: "setupWindow.section.general.restoreDefaults"
            ) {
                restoreDefaultGeneralSettings()
            }
            .disabled(!isGeneralSectionCustomized)
        } content: {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    SetupFieldRow(title: "Microphone") {
                        MicPriorityPicker(
                            preferences: preferences,
                            audioDeviceService: audioDeviceService
                        )
                        .frame(maxWidth: 240, alignment: .leading)
                    }
                    .zIndex(10)

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
            VStack(alignment: .leading, spacing: 14) {
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

                SetupFieldRow(title: "Assistant system prompt") {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Assistant prompt used every time assistant is invoked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Edit…") {
                            isShowingAssistantSystemPromptEditor = true
                        }
                        .frame(maxWidth: .infinity)
                        .frame(width: AssistantNameControlMetrics.recordControlWidth, alignment: .trailing)
                        .accessibilityIdentifier("setupWindow.rewriteSystemPrompt.open")
                    }
                }
            }
        }
    }

    private var notesSectionContent: some View {
        SettingsSectionCard(section: .notes, flashTrigger: flashTrigger(for: .notes)) {
            VStack(alignment: .leading, spacing: 14) {
                SetupFieldRow(title: "Saving mode") {
                    NoteCaptureModeRow(mode: assistantNoteModeBinding)
                }

                SetupFieldRow(title: "Destination") {
                    if preferences.assistantNoteMode == .newFile {
                        AssistantNoteDestinationRow(
                            path: preferences.assistantNoteFolderPath,
                            placeholder: "No note folder selected",
                            destinationKind: .folder,
                            pathAccessibilityIdentifier: "setupWindow.notes.destination.path",
                            browseAccessibilityIdentifier: "setupWindow.notes.destination.browse",
                            clearAccessibilityIdentifier: "setupWindow.notes.destination.clear",
                            browseAction: chooseAssistantNoteFolder,
                            clearAction: { preferences.assistantNoteFolderPath = "" }
                        )
                    } else {
                        AssistantNoteDestinationRow(
                            path: preferences.assistantNoteAppendFilePath,
                            placeholder: "No append file selected",
                            destinationKind: .file,
                            pathAccessibilityIdentifier: "setupWindow.notes.destination.path",
                            browseAccessibilityIdentifier: "setupWindow.notes.destination.browse",
                            clearAccessibilityIdentifier: "setupWindow.notes.destination.clear",
                            browseAction: chooseAssistantNoteAppendFile,
                            clearAction: { preferences.assistantNoteAppendFilePath = "" }
                        )
                    }
                }
            }
        }
    }

    private var historySectionContent: some View {
        SettingsSectionCard(
            section: .history,
            flashTrigger: flashTrigger(for: .history)
        ) {
            Toggle("Save history", isOn: Binding(
                get: { preferences.historyEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        preferences.historyEnabled = newValue
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.8, anchor: .trailing)
            .fixedSize()
            .accessibilityLabel("Save history")
            .accessibilityIdentifier("setupWindow.history.enabled")
        } content: {
            if preferences.historyEnabled {
                VStack(alignment: .leading, spacing: 14) {
                    SetupFieldRow(title: "History folder") {
                        HStack(alignment: .center, spacing: 8) {
                            HistoryFolderRow(
                                path: preferences.historyConfiguration.resolvedFolderPath,
                                placeholder: "No history folder selected",
                                showsResetAction: !preferences.historyFolderPath.isEmpty,
                                browseAction: chooseHistoryFolder,
                                resetAction: { preferences.historyFolderPath = "" }
                            )

                            Button(action: revealHistoryFolder) {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.body)
                            }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                            .accessibilityIdentifier("setupWindow.history.reveal")
                        }
                    }

                    SetupFieldRow(title: "History storage limit", alignment: .top) {
                        HistoryStorageLimitRow(
                            storageLimitMB: Binding(
                                get: { preferences.historyStorageLimitMB },
                                set: { preferences.historyStorageLimitMB = $0 }
                            ),
                            usageText: historyUsageDescription
                        )
                    }

                    savedEntriesZone
                        .padding(.leading, SetupSectionMetrics.rowIndent)
                }
            }
        }
    }

    @ViewBuilder
    private var savedEntriesZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved entries")
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isShowingClearHistoryConfirmation = true
                } label: {
                    Label("Clear history…", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(historyEntries.isEmpty)
                .accessibilityIdentifier("setupWindow.history.clearAll")
            }

            if let historyLoadError {
                Text(historyLoadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if historyEntries.isEmpty {
                Text("No saved history entries in the current folder yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextField("Search transcriptions…", text: $historySearchQuery)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("setupWindow.history.search")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SetupColorPalette.controlBorder, lineWidth: 0.75)
                )

                HStack(alignment: .top, spacing: 12) {
                    historyList
                    HistoryDetailPane(
                        detail: filteredSelectionDetail,
                        copyLabel: historyCopyConfirmationVisible ? "Copied" : "Copy",
                        copyAction: copySelectedHistoryEntry,
                        revealAction: { if let url = selectedHistoryEntryURL { revealHistoryEntry(url) } },
                        deleteAction: { if let url = selectedHistoryEntryURL { deleteHistoryEntry(url) } }
                    )
                    .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedHistoryEntries, id: \.label) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            HistoryEntryRow(
                                entry: entry,
                                isSelected: selectedHistoryEntryURL == entry.fileURL,
                                onSelect: { selectHistoryEntry(entry.fileURL) },
                                onDelete: { deleteHistoryEntry(entry.fileURL) }
                            )
                        }
                    } header: {
                        Text(group.label)
                            .font(.caption2.weight(.bold))
                            .tracking(0.4)
                            .textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .background(SetupColorPalette.cardBackground)
                    }
                }

                if filteredHistoryEntries.isEmpty {
                    Text("No transcriptions match your search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 18)
                }
            }
            .padding(.trailing, 4)
        }
        .frame(width: 220)
        .frame(minHeight: 230, maxHeight: 280)
        .accessibilityIdentifier("setupWindow.history.list")
    }

    private var filteredSelectionDetail: HistoryEntryDetail? {
        guard let url = selectedHistoryEntryURL,
              filteredHistoryEntries.contains(where: { $0.fileURL == url }) else {
            return nil
        }
        return selectedHistoryDetail
    }

    private var replacementsSectionContent: some View {
        SettingsSectionCard(
            section: .replacements,
            flashTrigger: flashTrigger(for: .replacements)
        ) {
            SettingsSectionActionButton(
                title: "Clear Mine…",
                accessibilityIdentifier: "setupWindow.section.replacements.clearAll"
            ) {
                isShowingClearAllReplacementsConfirmation = true
            }
            .disabled(!hasWordReplacements)
        } content: {
            ReplacementsSectionView(preferences: preferences)
        }
    }

    private var shortcutsSectionContent: some View {
        SettingsSectionCard(
            section: .shortcuts,
            flashTrigger: flashTrigger(for: .shortcuts)
        ) {
            SettingsSectionActionButton(
                title: "Restore Defaults",
                accessibilityIdentifier: "setupWindow.section.shortcuts.restoreDefaults"
            ) {
                restoreDefaultKeyboardShortcuts()
            }
            .disabled(!isKeyboardShortcutsCustomized)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                SetupFieldRow(title: "Start recording") {
                    HStack(spacing: 12) {
                        KeyComboRecorder(name: .activate, preferences: preferences, onShortcutChanged: onTapShortcutChanged)
                        KeyComboRecorder(name: .activateAlt, preferences: preferences, onShortcutChanged: onTapShortcutChanged)
                        MouseButtonRecorder(
                            action: .startRecording,
                            preferences: preferences,
                            binding: preferences.startMouseButtonBinding,
                            accessibilityID: "setupWindow.activate.mouseRecorder",
                            onRecord: { binding in
                                preferences.startMouseButtonBinding = binding
                                HotkeyService.shared.configureMouseBindings()
                                onTapShortcutChanged()
                            },
                            onClear: {
                                preferences.startMouseButtonBinding = nil
                                HotkeyService.shared.configureMouseBindings()
                                onTapShortcutChanged()
                            }
                        )
                    }
                }

                SetupFieldRow(title: "Stop recording") {
                    HStack(spacing: 12) {
                        KeyComboRecorder(name: .stopSession, preferences: preferences, onShortcutChanged: onTapShortcutChanged)
                        KeyComboRecorder(name: .stopSessionAlt, preferences: preferences, onShortcutChanged: onTapShortcutChanged)
                        MouseButtonRecorder(
                            action: .stopRecording,
                            preferences: preferences,
                            binding: preferences.stopMouseButtonBinding,
                            accessibilityID: "setupWindow.stopSession.mouseRecorder",
                            onRecord: { binding in
                                preferences.stopMouseButtonBinding = binding
                                HotkeyService.shared.configureMouseBindings()
                                onTapShortcutChanged()
                            },
                            onClear: {
                                preferences.stopMouseButtonBinding = nil
                                HotkeyService.shared.configureMouseBindings()
                                onTapShortcutChanged()
                            }
                        )
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
                            Text("Assistant Model")
                                .font(.body)

                            Spacer()

                            Text("Select a downloaded built-in local model, or use the cloud / localhost provider below.")
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
                            Text("Wait for the current recording or transcription to finish before downloading, deleting, or switching assistant models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .opacity(preferences.cloudLLMConfig.isEnabled ? 0.5 : 1.0)
                    .disabled(preferences.cloudLLMConfig.isEnabled)

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
                .fill(SetupColorPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SetupColorPalette.cardBorder, lineWidth: 1)
        )
        .modifier(
            SettingsCardFlashModifier(
                cornerRadius: SettingsLayoutMetrics.cardCornerRadius,
                flashTrigger: flashTrigger(for: .advanced)
            )
        )
        .accessibilityIdentifier("setupWindow.section.advanced")
    }

    private var settingsBody: some View {
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
                                trackedSection(.general) {
                                    generalSectionContent
                                }

                                trackedSection(.shortcuts) {
                                    shortcutsSectionContent
                                }

                                trackedSection(.assistant) {
                                    assistantSectionContent
                                }

                                trackedSection(.replacements) {
                                    replacementsSectionContent
                                }

                                trackedSection(.notes) {
                                    notesSectionContent
                                }

                                trackedSection(.history) {
                                    historySectionContent
                                }

                                trackedSection(.permissions) {
                                    permissionsSectionContent
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
                    .onReceive(NotificationCenter.default.publisher(for: .postEventGuideRequested)) { _ in
                        scrollToSection(.permissions, proxy: proxy)
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

                Button("Close") {
                    dismissWindow()
                }
                .accessibilityIdentifier("setupWindow.primaryAction")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(SetupColorPalette.appBackground)
        }
        .confirmationDialog(
            "Clear your word replacements?",
            isPresented: $isShowingClearAllReplacementsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Mine", role: .destructive) {
                clearAllWordReplacements()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the replacements you added yourself. Vocabulary packs stay on.")
        }
        .confirmationDialog(
            "Clear all saved history?",
            isPresented: $isShowingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                clearAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every saved transcription in the current history folder.")
        }
        .sheet(isPresented: $isShowingAssistantSystemPromptEditor) {
            AssistantSystemPromptSheet(
                prompt: rewriteSystemPromptBinding,
                onLoadFromFile: loadAssistantSystemPromptFromFile,
                onDismiss: { isShowingAssistantSystemPromptEditor = false }
            )
        }
    }

    var body: some View {
        Group {
            if mode == .onboarding {
                onboardingBody
            } else {
                settingsBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(
            minWidth: SetupWindowMetrics.width,
            maxWidth: SetupWindowMetrics.width,
            minHeight: SetupWindowMetrics.collapsedHeight
        )
        .background(SetupColorPalette.appBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            audioDeviceService.refresh()
            readinessStore.refresh()
            modelLoadState.refreshStatus()
            whisperModelLoadState.refreshStatus()
            configureSetupWindowSize()
            loadCloudAPIKeyIfNeeded()
            synchronizeOnboardingStepIfNeeded()
            persistOnboardingProgress()
            reloadHistoryEntries()
            if mode == .onboarding && !preferences.launchAtLogin {
                preferences.setLaunchAtLogin(true)
            }
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
            if mode != .onboarding {
                reloadHistoryEntries()
            }
        }
        .onChange(of: preferences.rewriteModelTier) { _ in
            modelLoadState.refreshStatus()
        }
        .onChange(of: preferences.whisperModel) { _ in
            whisperModelLoadState.refreshStatus()
        }
        .onChange(of: preferences.historyFolderPath) { _, _ in
            reloadHistoryEntries()
        }
        .onChange(of: onboardingStep) { _, _ in
            persistOnboardingProgress()
        }
        .onChange(of: preferences.cloudLLMConfig.provider) { _, _ in
            cloudAPIKeyLoaded = false
            loadCloudAPIKeyIfNeeded()
            cloudModels = []
            cloudModelFetchError = nil
            cloudConnectionTestResult = nil
            cloudSaveResult = nil
        }
    }
}
