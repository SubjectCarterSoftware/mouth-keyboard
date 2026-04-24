import AppKit
import Carbon.HIToolbox
import Combine
import KeyboardShortcuts
import SwiftUI

enum SetupWindowMetrics {
    static let width: CGFloat = 672
    static let collapsedHeight: CGFloat = 750
}

enum CloudConnectionTestResult: Equatable {
    case success
    case failed(String)
}

private enum RewriteSystemPromptSectionMetrics {
    static let editorHeight: CGFloat = 150
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

    private static let modifierKeyCodes: Set<Int> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    private static let modifierKeyNames: [Int: String] = [
        54: "Right ⌘", 55: "Left ⌘",
        56: "Left ⇧",
        58: "Left ⌥", 59: "Left ⌃",
        60: "Right ⇧", 61: "Right ⌥",
        62: "Right ⌃", 63: "fn",
    ]

    private static func modifierFlag(for keyCode: Int) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 63: return .function
        default: return []
        }
    }

    static func displayName(keyCode: Int, modifiers: UInt) -> String {
        let nsFlags = NSEvent.ModifierFlags(rawValue: modifiers)
        var symbols = ""
        if nsFlags.contains(.control) { symbols += "⌃" }
        if nsFlags.contains(.option) { symbols += "⌥" }
        if nsFlags.contains(.shift) { symbols += "⇧" }
        if nsFlags.contains(.command) { symbols += "⌘" }

        if let modName = modifierKeyNames[keyCode] {
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
                let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
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
                if Self.modifierKeyCodes.contains(kc) {
                    let flag = Self.modifierFlag(for: kc)
                    if event.modifierFlags.contains(flag) {
                        pendingModifierKeyCode = kc
                    } else if pendingModifierKeyCode == kc {
                        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
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
    static let rowIndent: CGFloat = 12
}

private struct SetupSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
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

private struct KeyboardShortcutsRow: View {
    @ObservedObject var preferences: ShellPreferences

    var body: some View {
        SetupFieldRow(title: "Hold to Transcribe:") {
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
    var helperText: String? = "Automatically pastes the result into the focused field each time a transcription completes. Clipboard passthrough protection restores whatever was on your clipboard beforehand, so nothing you had copied is lost."

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle("Always Auto Paste", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 22)
                .fixedSize()
                .accessibilityLabel("Always Auto Paste")
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

private struct AllowClipboardAccessRow: View {
    @Binding var isOn: Bool
    let helperText: String?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle("Clipboard Access", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 22)
                .fixedSize()
                .accessibilityLabel("Clipboard Access")
                .accessibilityIdentifier("setupWindow.allowClipboardAccess.toggle")

            if let helperText {
                ImmediateHelpIcon(text: helperText)
                    .accessibilityIdentifier("setupWindow.allowClipboardAccess.info")
            }
        }
        .frame(height: 22, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssistantActivationGuidanceView: View {
    @ObservedObject var viewModel: AIAssistantSettingsViewModel

    private var resolvedAssistantName: String {
        let trimmed = viewModel.activeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AssistantDefaults.defaultAssistantName : trimmed
    }

    private var assistantUsageText: Text {
        Text("Say ").foregroundColor(.primary)
        + Text(resolvedAssistantName).bold().foregroundColor(.accentColor)
        + Text(" in your transcription to send your message to the assistant.").foregroundColor(.primary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SetupFieldRow(title: "Activation:", alignment: .top) {
                assistantUsageText
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SetupFieldRow(title: "Assistant Name:") {
                HStack(alignment: .center, spacing: 8) {
                    AssistantDisplayedNameChip(
                        name: viewModel.displayedName,
                        isPreviewing: viewModel.isPreviewingRecordedName
                    )
                    .accessibilityIdentifier("assistantRow.activeName")

                    Spacer(minLength: 12)

                    AIAssistantInlineRowView(
                        viewModel: viewModel,
                        showsActiveName: false
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setupWindow.assistantActivation.section")
    }
}

private struct AssistantActivationSupportingText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
    let modelName: String
    let progress: Double?  // nil = prewarming (indeterminate)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(progress != nil ? "Preparing speech model" : "Loading speech model")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(
                    progress != nil
                        ? "\(modelName) is downloading in the background and will be ready for first use when complete."
                        : "\(modelName) is being compiled for your hardware. This only happens once."
                )
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
    private let postEventPermissionService = PostEventPermissionService.live
    private let keyboardPermissionService = KeyboardPermissionService.live
    let dismissWindow: () -> Void

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

    private var keyboardShortcutsStatus: PermissionGrantState {
        keyboardPermissionService.currentStatus(hasPrompted: preferences.hasRequestedKeyboardPermission)
    }

    private func requestKeyboardShortcutsAccess() {
        preferences.recordKeyboardPermissionPrompt()
        _ = keyboardPermissionService.requestAccess()
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

    private var allowClipboardAccessBinding: Binding<Bool> {
        Binding(
            get: {
                preferences.allowClipboardAccess
            },
            set: { newValue in
                preferences.allowClipboardAccess = newValue
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
        dismissWindow: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.readinessStore = readinessStore
        self.dismissWindow = dismissWindow
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
            $0.identifier == NSUserInterfaceItemIdentifier("Speech2TextSetupWindow")
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Speech2Text Settings")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("setupWindow.title")

                    PermissionChecklistView(
                        permissions: readinessStore.snapshot.permissions,
                        requestPermission: { kind in readinessStore.requestPermission(for: kind) },
                        openRecovery: { kind in readinessStore.openRecovery(for: kind) },
                        launchAtLoginEnabled: preferences.launchAtLogin,
                        onToggleLaunchAtLogin: { preferences.setLaunchAtLogin($0) }
                    )

                    if case .downloading(let model, let progress) = whisperModelLoadState.phase,
                       model == preferences.whisperModel {
                        ModelDownloadStatusRow(modelName: model.displayName, progress: progress)
                    } else if case .prewarming(let model) = whisperModelLoadState.phase,
                              model == preferences.whisperModel {
                        ModelDownloadStatusRow(modelName: model.displayName, progress: nil)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        AssistantActivationGuidanceView(
                            viewModel: assistantSettingsViewModel
                        )

                        Divider()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SetupFieldRow(title: "Microphone:") {
                            Picker("", selection: microphoneSelection) {
                                Text("System Default").tag(Optional<String>.none)
                                ForEach(audioDeviceService.availableDevices) { device in
                                    Text(device.name).tag(Optional(device.uid))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        SetupFieldRow(title: "Always Auto Paste:") {
                            AlwaysAutoPasteRow(isOn: alwaysAutoPasteBinding)
                        }

                        SetupFieldRow(title: "Clipboard Access:") {
                            AllowClipboardAccessRow(
                                isOn: allowClipboardAccessBinding,
                                helperText: "Grants the AI assistant access to your clipboard contents. When you mention your clipboard (or what you copied) in a transcription or instruction, the assistant is allowed to read and include that text in its response."
                            )
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        SetupFieldRow(title: "Start Transcription:") {
                            HStack(spacing: 12) {
                                KeyComboRecorder(name: .activate, preferences: preferences)
                                KeyComboRecorder(name: .activateAlt, preferences: preferences)
                            }
                        }

                        SetupFieldRow(title: "Stop Transcription:") {
                            HStack(spacing: 12) {
                                KeyComboRecorder(name: .stopSession, preferences: preferences)
                                KeyComboRecorder(name: .stopSessionAlt, preferences: preferences)
                            }
                        }

                        KeyboardShortcutsRow(
                            preferences: preferences
                        )
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isAdvancedSettingsExpanded.toggle()
                            }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("Advanced")
                                    .font(.headline)

                                Spacer()

                                Image(systemName: isAdvancedSettingsExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("setupWindow.advancedDisclosure")

                        if isAdvancedSettingsExpanded {
                            VStack(alignment: .leading, spacing: 16) {
                                Divider()
                                    .padding(.top, 16)

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

                                rewriteSystemPromptSection

                                Divider()

                                cloudLLMSettingsSection
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(spacing: 12) {
                Button("Shut Down App") {
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
