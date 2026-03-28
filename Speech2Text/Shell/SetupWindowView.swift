import AppKit
import Carbon.HIToolbox
import Combine
import KeyboardShortcuts
import SwiftUI

enum SetupWindowMetrics {
    static let width: CGFloat = 560
    static let collapsedHeight: CGFloat = 620
    static let expandedHeight: CGFloat = 820
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
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var clickMonitor: Any?
    @State private var currentShortcut: KeyboardShortcuts.Shortcut?
    @State private var shortcutBeforeRecording: KeyboardShortcuts.Shortcut?
    @State private var lastCancelTime: Date = .distantPast

    private var displayText: String {
        currentShortcut?.description ?? "Not Set"
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
                KeyboardShortcuts.setShortcut(shortcut, for: name)
                currentShortcut = shortcut
                finishRecording()
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

    private static let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static let modifierKeyNames: [Int: String] = [
        54: "Right ⌘", 55: "Left ⌘",
        56: "Left ⇧", 57: "⇪ Caps Lock",
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
        let candidate = KeyboardShortcuts.Shortcut(
            KeyboardShortcuts.Key(rawValue: keyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: modifiers)
        )
        let names: [KeyboardShortcuts.Name] = [.activate, .activateAlt, .stopSession, .stopSessionAlt]
        for name in names {
            if let shortcut = KeyboardShortcuts.getShortcut(for: name), shortcut == candidate {
                return true
            }
        }
        return false
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

private struct KeyboardShortcutsRow: View {
    @ObservedObject var preferences: ShellPreferences

    var body: some View {
        LabeledContent("Hold to Transcribe:") {
            HStack(spacing: 12) {
                HoldShortcutRecorder(
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("Auto Paste", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 22)
                .accessibilityLabel("Auto Paste")
                .accessibilityIdentifier("setupWindow.alwaysAutoPaste.toggle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    private let postEventPermissionService = PostEventPermissionService.live
    private let keyboardPermissionService = KeyboardPermissionService.live
    let dismissWindow: () -> Void

    private var primaryActionTitle: String {
        if preferences.hasCompletedInitialSetup {
            return "Close"
        }

        return readinessStore.canFinishSetup ? "Finish Setup" : "Done Later"
    }

    private var microphoneSelection: Binding<String?> {
        Binding(
            get: {
                preferences.micDeviceUID
            },
            set: { newValue in
                preferences.micDeviceUID = newValue
            }
        )
    }

    private var unavailableSelectedMicrophoneUID: String? {
        guard let selectedUID = preferences.micDeviceUID else {
            return nil
        }

        let isAvailable = audioDeviceService.availableDevices.contains { $0.uid == selectedUID }
        return isAvailable ? nil : selectedUID
    }

    private var isAnyModelTransferInFlight: Bool {
        modelLoadState.phase.downloadProgress != nil || modelLoadState.deletingTier != nil
    }

    private var canManageConversionModels: Bool {
        activationStore.state.allowsRewriteModelManagement
    }

    private var isAnyWhisperTransferInFlight: Bool {
        whisperModelLoadState.phase.downloadProgress != nil || whisperModelLoadState.deletingModel != nil
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
        status: RewriteModelLoadState.TierStatus,
        isSelected: Bool
    ) -> String {
        var details = [
            "\(String(format: "%.1f", tier.approximateDownloadSizeGB)) GB",
            shortRamGuidance(for: tier)
        ]

        if status.isDownloading {
            details.append("Downloading")
        } else if status.isDeleting {
            details.append("Deleting")
        } else if status.isDownloaded {
            details.append("Downloaded")
        } else {
            details.append("Download first")
        }

        if status.isWarm {
            details.append("Warm")
        }

        if isSelected {
            details.append(status.isDownloaded ? "Active" : "Configured")
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

                    Text(conversionModelDetailText(for: tier, status: status, isSelected: isSelected))
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
        status: WhisperModelLoadState.ModelStatus,
        isSelected: Bool
    ) -> String {
        var details = [model.detailSummary]

        if status.isDownloading {
            details.append("Downloading")
        } else if status.isDeleting {
            details.append("Deleting")
        } else if status.isLoading {
            details.append("Loading")
        } else if status.isDownloaded {
            details.append("Downloaded")
        } else {
            details.append("Download first")
        }

        if status.isWarm {
            details.append("Warm")
        }

        if isSelected {
            details.append(status.isDownloaded ? "Active" : "Configured")
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
        } else if status.isDeleting || status.isLoading {
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

                    Text(whisperModelDetailText(for: model, status: status, isSelected: isSelected))
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

    private func updateSetupWindowSize(forAdvancedSettingsExpanded isExpanded: Bool) {
        guard let window = NSApp.windows.first(where: {
            $0.identifier == NSUserInterfaceItemIdentifier("Speech2TextSetupWindow")
        }) else {
            return
        }

        window.setContentSize(
            NSSize(
                width: SetupWindowMetrics.width,
                height: isExpanded ? SetupWindowMetrics.expandedHeight : SetupWindowMetrics.collapsedHeight
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                Divider()

                Form {
                    Picker("Microphone", selection: microphoneSelection) {
                        Text("System Default").tag(Optional<String>.none)
                        ForEach(audioDeviceService.availableDevices) { device in
                            Text(device.name).tag(Optional(device.uid))
                        }
                        if let unavailableSelectedMicrophoneUID {
                            Text("Selected Microphone (Unavailable)").tag(Optional(unavailableSelectedMicrophoneUID))
                        }
                    }
                    .pickerStyle(.menu)

                    LabeledContent("Start:") {
                        HStack(spacing: 12) {
                            KeyComboRecorder(name: .activate)
                            KeyComboRecorder(name: .activateAlt)
                        }
                    }
                    LabeledContent("Stop:") {
                        HStack(spacing: 12) {
                            KeyComboRecorder(name: .stopSession)
                            KeyComboRecorder(name: .stopSessionAlt)
                        }
                    }

                    KeyboardShortcutsRow(
                        preferences: preferences
                    )

                    LabeledContent {
                        AlwaysAutoPasteRow(isOn: alwaysAutoPasteBinding)
                    } label: {
                        Text("Auto Paste:")
                    }

                    LabeledContent {
                        AIAssistantInlineRowView(
                            viewModel: assistantSettingsViewModel
                        )
                    } label: {
                        Text("Assistant name:")
                    }
                }
                .formStyle(.columns)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isAdvancedSettingsExpanded.toggle()
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Advanced")
                                .font(.body)

                            Spacer()

                            Text("Model downloads and selection")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)

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
                        }
                        .padding(.top, 10)
                    }
                }

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
                        preferences.micDeviceUID = nil
                        preferences.whisperModel = .smallEN
                    }

                    Button(primaryActionTitle) {
                        if readinessStore.canFinishSetup {
                            _ = readinessStore.finalizeSetup()
                        }
                        dismissWindow()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("setupWindow.primaryAction")
                }
            }
            .padding(24)
        }
        .frame(
            minWidth: SetupWindowMetrics.width,
            maxWidth: SetupWindowMetrics.width,
            minHeight: SetupWindowMetrics.collapsedHeight,
            maxHeight: SetupWindowMetrics.expandedHeight
        )
        .background(.regularMaterial)
        .onAppear {
            audioDeviceService.refresh()
            readinessStore.refresh()
            modelLoadState.refreshStatus()
            whisperModelLoadState.refreshStatus()
            updateSetupWindowSize(forAdvancedSettingsExpanded: isAdvancedSettingsExpanded)
            NSApp.activate(ignoringOtherApps: true)
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
        .onChange(of: isAdvancedSettingsExpanded) { _, isExpanded in
            updateSetupWindowSize(forAdvancedSettingsExpanded: isExpanded)
        }
    }
}
