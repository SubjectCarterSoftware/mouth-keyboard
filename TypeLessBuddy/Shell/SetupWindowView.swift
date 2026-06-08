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

enum SettingsSection: String, CaseIterable, Identifiable {
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

enum OnboardingStep: String, CaseIterable, Identifiable {
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

enum SettingsLayoutMetrics {
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

// MARK: - Shared shortcut recorder visual field

// MARK: - Key combo recorder (Start / Stop shortcuts)

// MARK: - Hold-key recorder (modifier-only keys allowed)

enum SetupSectionMetrics {
    static let rowLabelWidth: CGFloat = 150
    static let rowIndent: CGFloat = 4
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

    private var canManageRewriteModels: Bool {
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

    private func rewriteModelDetailText(
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
    private func rewriteModelActionView(
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
            .disabled(isAnyModelTransferInFlight || !canManageRewriteModels)
            .help(
                canManageRewriteModels
                    ? (isDownloaded ? "Delete downloaded model" : "Download model")
                    : "Wait for the current transcription to finish before changing rewrite models"
            )
            .accessibilityIdentifier("rewriteModel.\(tier.rawValue).action")
        }
    }

    @ViewBuilder
    private func rewriteModelRow(for tier: RewriteModelTier) -> some View {
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

                    Text(rewriteModelDetailText(for: tier, status: status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
                .opacity(rowOpacity)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable || !canManageRewriteModels || isAnyModelTransferInFlight)
            .help(
                canManageRewriteModels
                    ? "Select this model for future rewrites"
                    : "Wait for the current transcription to finish before changing rewrite models"
            )
            .accessibilityIdentifier("rewriteModel.\(tier.rawValue).select")

            rewriteModelActionView(for: tier, status: status)
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
        .accessibilityIdentifier("rewriteModel.\(tier.rawValue)")
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

            Toggle("Enable cloud LLM for rewrites", isOn: Binding(
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
                            rewriteModelRow(for: tier)
                        }

                        if case .failed(_, let message) = modelLoadState.phase {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if !canManageRewriteModels {
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
