import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

enum SetupWindowMetrics {
    static let width: CGFloat = 560
    static let collapsedHeight: CGFloat = 620
    static let expandedHeight: CGFloat = 820
}

private struct HoldShortcutRecorder: View {
    @ObservedObject var preferences: ShellPreferences
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var pendingModifierKeyCode: Int?

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

    private var shortcutName: String {
        Self.displayName(keyCode: preferences.holdShortcutKeyCode, modifiers: preferences.holdShortcutModifiers)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isRecording { stopRecording() } else { startRecording() }
            } label: {
                Text(isRecording ? "Record shortcut…" : shortcutName)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(minWidth: 90)
            }
            .accessibilityIdentifier("setupWindow.holdToTranscribe.recorder")
            .accessibilityLabel(shortcutName)

            if !isRecording {
                Button {
                    preferences.holdShortcutKeyCode = 61
                    preferences.holdShortcutModifiers = 0
                    HotkeyService.shared.configureHoldTarget()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Reset to Right ⌥")
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        pendingModifierKeyCode = nil
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape
                    stopRecording()
                    return nil
                }
                pendingModifierKeyCode = nil
                let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
                recordKey(keyCode: Int(event.keyCode), modifiers: event.modifierFlags.intersection(relevantModifiers).rawValue)
                return nil
            }

            if event.type == .flagsChanged {
                let keyCode = Int(event.keyCode)
                if Self.modifierKeyCodes.contains(keyCode) {
                    let flag = Self.modifierFlag(for: keyCode)
                    if event.modifierFlags.contains(flag) {
                        pendingModifierKeyCode = keyCode
                    } else if pendingModifierKeyCode == keyCode {
                        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
                        let remaining = event.modifierFlags.intersection(relevantModifiers)
                        if remaining.isEmpty {
                            recordKey(keyCode: keyCode, modifiers: 0)
                        }
                        pendingModifierKeyCode = nil
                    }
                }
            }
            return event
        }
    }

    private func recordKey(keyCode: Int, modifiers: UInt) {
        preferences.holdShortcutKeyCode = keyCode
        preferences.holdShortcutModifiers = modifiers
        HotkeyService.shared.configureHoldTarget()
        stopRecording()
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        pendingModifierKeyCode = nil
        isRecording = false
    }
}

private struct HoldToTranscribeRow: View {
    @ObservedObject var preferences: ShellPreferences
    let status: PermissionGrantState
    let requestAccess: () -> Void
    let openRecovery: () -> Void

    @State private var showsAccessibilityGuide = false

    private var statusColor: Color {
        switch status {
        case .authorized:
            return .green
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        }
    }

    private var detailText: String {
        switch status {
        case .authorized:
            return "Hold to record, release to transcribe."
        case .notDetermined:
            return "Needs Accessibility access."
        case .denied:
            return "Accessibility is blocked."
        }
    }

    private var actionTitle: String? {
        switch status {
        case .authorized:
            return nil
        case .notDetermined:
            return "Enable Accessibility"
        case .denied:
            return "Open Accessibility Setup"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            HoldShortcutRecorder(preferences: preferences)

            Text(detailText)
                .font(.caption)
                .foregroundStyle(status == .authorized ? Color.secondary : statusColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("setupWindow.holdToTranscribe.message")

            if let actionTitle {
                Button(actionTitle) {
                    showsAccessibilityGuide = true
                }
                .accessibilityIdentifier("setupWindow.holdToTranscribe.action")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("setupWindow.holdToTranscribe.row")
        .popover(isPresented: $showsAccessibilityGuide, arrowEdge: .bottom) {
            AccessibilitySetupGuide {
                showsAccessibilityGuide = false
                if status == .denied {
                    openRecovery()
                } else {
                    requestAccess()
                }
            }
        }
    }
}

private struct AlwaysAutoPasteRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Always Auto Paste", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Always Auto Paste")
                .accessibilityIdentifier("setupWindow.alwaysAutoPaste.toggle")

            Text("Paste after any successful finish, including Right Option and AI output.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("setupWindow.alwaysAutoPaste.message")
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

    private var holdToTranscribeStatus: PermissionGrantState {
        postEventPermissionService.currentStatus(hasPrompted: preferences.hasRequestedPostEventPermission)
    }

    private func requestHoldToTranscribeAccess() {
        preferences.recordPostEventPermissionPrompt()
        _ = postEventPermissionService.requestAccess()
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

                    KeyboardShortcuts.Recorder("Start / Stop:", name: .activate)
                    KeyboardShortcuts.Recorder("Stop Only:", name: .stopSession)
                    KeyboardShortcuts.Recorder("Stop & Auto Paste:", name: .activateAndPaste)

                    LabeledContent {
                        HoldToTranscribeRow(
                            preferences: preferences,
                            status: holdToTranscribeStatus,
                            requestAccess: requestHoldToTranscribeAccess,
                            openRecovery: { readinessStore.openRecovery(for: .postEvent) }
                        )
                    } label: {
                        Text("Hold to Transcribe:")
                    }

                    LabeledContent {
                        AlwaysAutoPasteRow(isOn: alwaysAutoPasteBinding)
                    } label: {
                        Text("Always Auto Paste:")
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
                        KeyboardShortcuts.reset(.activate, .stopSession, .activateAndPaste)
                        preferences.micDeviceUID = nil
                        preferences.whisperModel = .baseEN
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
