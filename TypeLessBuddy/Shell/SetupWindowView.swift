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
            return "Try It Out"
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
            return "Take TypeLessBuddy for a quick spin — just hold your key and speak."
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
            return "mic.fill"
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
            return "Optional — try it now, or finish and explore on your own once the models are ready."
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
    @ObservedObject var modelLoadState = RewriteModelLoadState.shared
    @ObservedObject var whisperModelLoadState = WhisperModelLoadState.shared
    @ObservedObject var activationStore = ActivationStore.shared
    @ObservedObject var audioDeviceService = AudioDeviceService.shared
    @StateObject var assistantSettingsViewModel: AIAssistantSettingsViewModel
    @State var isAdvancedSettingsExpanded = false
    @StateObject var cloudVM = CloudLLMSettingsViewModel()
    @State var activeSection: SettingsSection = .general
    @State var flashedSection: SettingsSection?
    @State var flashNonce: Int = 0
    @State var keyboardShortcutChangeNonce: Int = 0
    @State var isShowingAssistantSystemPromptEditor = false
    @State var isShowingClearAllReplacementsConfirmation = false
    @State var scheduledFlashTask: Task<Void, Never>?
    @State var isProgrammaticScroll = false
    @State var onboardingStep: OnboardingStep = .microphone
    @State var hasInitializedOnboardingStep = false
    @State var isMicPriorityPickerMenuOpen = false
    @State var tryoutStep: Int = 0
    @State var tryoutMaxReachedStep: Int = 0
    @State var tryoutBoxText: String = ""
    @State var didCopyTryoutSample: Bool = false
    @State var tryoutAdvanceTask: Task<Void, Never>?
    @FocusState var isTryoutBoxFocused: Bool
    @State var accessibilityWaitingForGrant = false
    @State var accessibilityJustGranted = false
    @State var accessibilityAdvanceTask: Task<Void, Never>?
    @StateObject var historyVM: HistorySettingsViewModel
    @State var isShowingClearHistoryConfirmation = false
    let updatePillPositionPreview: (RecordingPillPosition?) -> Void
    let dismissWindow: () -> Void
    let openGuide: () -> Void
    let completeOnboarding: () -> Void

    var rewriteSystemPromptBinding: Binding<String> {
        Binding(
            get: {
                preferences.rewriteSystemPromptPrefix
            },
            set: { newValue in
                preferences.rewriteSystemPromptPrefix = newValue
            }
        )
    }

    var isAnyModelTransferInFlight: Bool {
        modelLoadState.phase.downloadProgress != nil || modelLoadState.deletingTier != nil
    }

    var canManageRewriteModels: Bool {
        activationStore.state.allowsRewriteModelManagement
    }

    var isAnyWhisperTransferInFlight: Bool {
        whisperModelLoadState.phase.isTransferInFlight || whisperModelLoadState.deletingModel != nil
    }

    var isGeneralSectionCustomized: Bool {
        !preferences.micDeviceUIDs.isEmpty
            || !preferences.alwaysAutoPaste
            || !preferences.restorePreviousClipboardAfterAutoPaste
            || preferences.muteSoundEffects
            || preferences.recordingPillPosition != .default
    }

    var isKeyboardShortcutsCustomized: Bool {
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

    var hasWordReplacements: Bool {
        preferences.activeDictionaryData.replacements.contains { $0.sourcePackIDs.isEmpty }
    }

    var alwaysAutoPasteBinding: Binding<Bool> {
        Binding(
            get: {
                preferences.alwaysAutoPaste
            },
            set: { newValue in
                preferences.alwaysAutoPaste = newValue
            }
        )
    }

    var restorePreviousClipboardBinding: Binding<Bool> {
        Binding(
            get: {
                preferences.restorePreviousClipboardAfterAutoPaste
            },
            set: { newValue in
                preferences.restorePreviousClipboardAfterAutoPaste = newValue
            }
        )
    }

    var playSoundEffectsBinding: Binding<Bool> {
        Binding(
            get: {
                !preferences.muteSoundEffects
            },
            set: { newValue in
                preferences.muteSoundEffects = !newValue
            }
        )
    }

    var assistantNoteModeBinding: Binding<AssistantNoteMode> {
        Binding(
            get: {
                preferences.assistantNoteMode
            },
            set: { newValue in
                preferences.assistantNoteMode = newValue
            }
        )
    }

    var recordingPillPositionBinding: Binding<RecordingPillPosition> {
        Binding(
            get: {
                preferences.recordingPillPosition
            },
            set: { newValue in
                preferences.recordingPillPosition = newValue
            }
        )
    }

    var microphonePermissionItem: PermissionChecklistItem? {
        readinessStore.snapshot.permissions.first(where: { $0.kind == .microphone })
    }

    var accessibilityPermissionItem: PermissionChecklistItem? {
        readinessStore.snapshot.permissions.first(where: { $0.kind == .postEvent })
    }

    var isMicrophoneAuthorized: Bool {
        microphonePermissionItem?.isAuthorized ?? false
    }

    var isAccessibilityAuthorized: Bool {
        accessibilityPermissionItem?.isAuthorized ?? false
    }

    var speechEngineStatus: WhisperModelLoadState.ModelStatus {
        whisperModelLoadState.status(for: preferences.whisperModel)
    }

    var isSpeechEngineReady: Bool {
        let status = speechEngineStatus
        return status.isDownloaded && !status.isDownloading && !status.isPrewarming && !status.isLoading && !status.isDeleting
    }

    var selectedBuiltInAssistantTier: RewriteModelTier {
        preferences.rewriteModelTier
    }

    var selectedBuiltInAssistantStatus: RewriteModelLoadState.TierStatus {
        modelLoadState.status(for: selectedBuiltInAssistantTier)
    }

    var selectedAssistantModelDisplayName: String {
        selectedBuiltInAssistantTier.displayName
    }

    var usesLocalAssistantModel: Bool {
        !preferences.cloudLLMConfig.isEnabled
    }

    var isLocalAssistantModelReady: Bool {
        guard usesLocalAssistantModel else { return true }
        let status = selectedBuiltInAssistantStatus
        return status.isDownloaded && status.isPrepared && !status.isDownloading && !status.isPrewarming && !status.isDeleting
    }

    var areOnboardingModelsReady: Bool {
        isSpeechEngineReady && isLocalAssistantModelReady
    }

    var onboardingStepSequence: [OnboardingStep] {
        OnboardingStep.allCases
    }

    var onboardingStepIndex: Int {
        (onboardingStepSequence.firstIndex(of: onboardingStep) ?? 0) + 1
    }

    func badgeTone(for status: PermissionGrantState) -> OnboardingBadgeTone {
        switch status {
        case .authorized:
            return .success
        case .notDetermined:
            return .warning
        case .denied:
            return .danger
        }
    }

    func requestPermission(_ kind: PermissionKind) {
        readinessStore.requestPermission(for: kind)
    }

    func openPermissionRecovery(_ kind: PermissionKind) {
        readinessStore.openRecovery(for: kind)
    }

    func microphoneActionTitle(for status: PermissionGrantState) -> String {
        switch status {
        case .authorized:
            return "Microphone Granted"
        case .notDetermined:
            return "Grant Microphone Access"
        case .denied:
            return "Open Microphone Settings"
        }
    }

    func accessibilityActionTitle(for status: PermissionGrantState) -> String {
        switch status {
        case .authorized:
            return "Accessibility Granted"
        case .notDetermined:
            return "Grant Accessibility"
        case .denied:
            return "Open Accessibility Settings"
        }
    }

    func shortRamGuidance(for tier: RewriteModelTier) -> String {
        switch tier {
        case .standard2B:
            return "Any Mac"
        case .standard4B:
            return "8GB+"
        case .high9B:
            return "16GB+"
        }
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
        self.updatePillPositionPreview = updatePillPositionPreview
        self.dismissWindow = dismissWindow
        self.openGuide = openGuide
        self.completeOnboarding = completeOnboarding
        _assistantSettingsViewModel = StateObject(
            wrappedValue: AIAssistantSettingsViewModel(preferences: preferences)
        )
        _historyVM = StateObject(
            wrappedValue: HistorySettingsViewModel(
                historyCaptureService: historyCaptureService,
                configuration: { preferences.historyConfiguration }
            )
        )
    }

    // MARK: - Cloud LLM Settings

    var cloudLLMSettingsSection: some View {
        CloudLLMSettingsSectionView(preferences: preferences, cloudVM: cloudVM)
    }
    func chooseAssistantNoteFolder() {
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

    func chooseAssistantNoteAppendFile() {
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

    func loadAssistantSystemPromptFromFile() {
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

    func chooseHistoryFolder() {
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
        historyVM.reloadEntries()
    }

    func revealHistoryFolder() {
        let url = URL(fileURLWithPath: preferences.historyConfiguration.resolvedFolderPath, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealHistoryEntry(_ fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func restoreDefaultGeneralSettings() {
        updatePillPositionPreview(nil)
        preferences.restoreDefaultGeneralSettings()
    }

    func restoreDefaultKeyboardShortcuts() {
        KeyboardShortcuts.reset(.activate, .activateAlt, .stopSession, .stopSessionAlt)
        preferences.restoreDefaultHoldShortcuts()
        HotkeyService.shared.configureHoldTarget()
        HotkeyService.shared.configureMouseBindings()
        keyboardShortcutChangeNonce &+= 1
    }

    func clearAllWordReplacements() {
        preferences.clearWordReplacements()
    }

    func onTapShortcutChanged() {
        keyboardShortcutChangeNonce &+= 1
    }

    func configureSetupWindowSize() {
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

    func updateActiveSection(using offsets: [SettingsSection: CGFloat]) {
        guard !isProgrammaticScroll else { return }
        guard let nearest = offsets.min(by: { abs($0.value - 12) < abs($1.value - 12) })?.key else {
            return
        }
        activeSection = nearest
    }

    func scrollToSection(_ section: SettingsSection, proxy: ScrollViewProxy) {
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

    func flashTrigger(for section: SettingsSection) -> Int {
        flashedSection == section ? flashNonce : 0
    }

    @ViewBuilder
    func trackedSection<Content: View>(
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
            cloudVM.loadAPIKeyIfNeeded(provider: preferences.cloudLLMConfig.provider)
            synchronizeOnboardingStepIfNeeded()
            persistOnboardingProgress()
            historyVM.reloadEntries()
            if mode == .onboarding && !preferences.launchAtLogin {
                preferences.setLaunchAtLogin(true)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            updatePillPositionPreview(nil)
            assistantSettingsViewModel.handleSettingsDismissed()
            cancelTryoutAdvance()
            accessibilityAdvanceTask?.cancel()
            accessibilityAdvanceTask = nil
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            readinessStore.refresh()
            modelLoadState.refreshStatus()
            whisperModelLoadState.refreshStatus()
            if mode != .onboarding {
                historyVM.reloadEntries()
            }
        }
        .onChange(of: preferences.rewriteModelTier) { _ in
            modelLoadState.refreshStatus()
        }
        .onChange(of: preferences.whisperModel) { _ in
            whisperModelLoadState.refreshStatus()
        }
        .onChange(of: preferences.historyFolderPath) { _, _ in
            historyVM.reloadEntries()
        }
        .onChange(of: onboardingStep) { _, newStep in
            persistOnboardingProgress()
            if newStep != .accessibility {
                accessibilityWaitingForGrant = false
                accessibilityJustGranted = false
                accessibilityAdvanceTask?.cancel()
                accessibilityAdvanceTask = nil
            }
        }
        .onChange(of: isAccessibilityAuthorized) { _, newValue in
            handleAccessibilityAuthorizationChange(newValue)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Poll quickly while waiting on the Accessibility toggle so the step
            // reacts almost instantly when the user flips the switch.
            if mode == .onboarding, onboardingStep == .accessibility, !isAccessibilityAuthorized {
                readinessStore.refresh()
            }
        }
        .onChange(of: preferences.cloudLLMConfig.provider) { _, _ in
            cloudVM.providerChanged(provider: preferences.cloudLLMConfig.provider)
        }
    }
}
