import Combine
import Foundation
import ServiceManagement

enum RecordingPillPosition: String, CaseIterable, Codable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    static let `default` = RecordingPillPosition.bottomCenter

    var displayName: String {
        switch self {
        case .topLeft:
            return "Top Left"
        case .topCenter:
            return "Top Center"
        case .topRight:
            return "Top Right"
        case .centerLeft:
            return "Center Left"
        case .centerRight:
            return "Center Right"
        case .bottomLeft:
            return "Bottom Left"
        case .bottomCenter:
            return "Bottom Center"
        case .bottomRight:
            return "Bottom Right"
        }
    }
}

@MainActor
final class ShellPreferences: ObservableObject {
    enum Keys {
        static let suiteName = "com.elicarter.TypeLessBuddy.shell"
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
        static let completedOnboardingBuildIdentifier = "completedOnboardingBuildIdentifier"
        static let onboardingResumeToken = "onboardingResumeToken"
        static let showsMenuHints = "showsMenuHints"
        static let hasRequestedMicrophonePermission = "hasRequestedMicrophonePermission"
        static let hasRequestedPostEventPermission = "hasRequestedPostEventPermission"
        static let micDeviceUID = "micDeviceUID" // legacy — kept for migration only
        static let micDeviceUIDs = "micDeviceUIDs"
        static let whisperModel = "whisperModel"
        static let launchAtLogin = "launchAtLogin"
        static let rewriteModelTier = "rewriteModelTier"
        static let alwaysAutoPaste = "alwaysAutoPaste"
        static let restorePreviousClipboardAfterAutoPaste = "restorePreviousClipboardAfterAutoPaste"
        static let muteSoundEffects = "muteSoundEffects"
        static let holdShortcutKeyCode = "holdShortcutKeyCode"
        static let holdShortcutModifiers = "holdShortcutModifiers"
        static let holdShortcutKeyCodeAlt = "holdShortcutKeyCodeAlt"
        static let holdShortcutModifiersAlt = "holdShortcutModifiersAlt"
        static let cloudLLMConfig = "cloudLLMConfig"
        static let legacyAllowClipboardAccess = "allowClipboardAccess"
        static let rewriteSystemPromptPrefix = "rewriteSystemPromptPrefix"
        static let recordingPillPosition = "recordingPillPosition"
    }

    static let shared = makeShared()
    static let defaultHoldShortcutKeyCode = 61
    static let defaultHoldShortcutModifiers: UInt = 0
    static let defaultHoldShortcutKeyCodeAlt = -1
    static let defaultHoldShortcutModifiersAlt: UInt = 0

    @Published var hasCompletedInitialSetup: Bool {
        didSet {
            defaults.set(hasCompletedInitialSetup, forKey: Keys.hasCompletedInitialSetup)
        }
    }

    @Published private(set) var completedOnboardingBuildIdentifier: String? {
        didSet {
            persistIfNeeded {
                if let completedOnboardingBuildIdentifier {
                    defaults.set(
                        completedOnboardingBuildIdentifier,
                        forKey: Keys.completedOnboardingBuildIdentifier
                    )
                } else {
                    defaults.removeObject(forKey: Keys.completedOnboardingBuildIdentifier)
                }
            }
        }
    }

    @Published private(set) var onboardingResumeToken: String? {
        didSet {
            persistIfNeeded {
                if let onboardingResumeToken {
                    defaults.set(onboardingResumeToken, forKey: Keys.onboardingResumeToken)
                } else {
                    defaults.removeObject(forKey: Keys.onboardingResumeToken)
                }
            }
        }
    }

    @Published var showsMenuHints: Bool {
        didSet {
            defaults.set(showsMenuHints, forKey: Keys.showsMenuHints)
        }
    }

    @Published var hasRequestedMicrophonePermission: Bool {
        didSet {
            defaults.set(hasRequestedMicrophonePermission, forKey: Keys.hasRequestedMicrophonePermission)
        }
    }

    @Published var hasRequestedPostEventPermission: Bool {
        didSet {
            defaults.set(hasRequestedPostEventPermission, forKey: Keys.hasRequestedPostEventPermission)
        }
    }

    /// Priority-ordered list of mic device UIDs. First available device wins at capture time.
    /// Empty means "use system default".
    @Published var micDeviceUIDs: [String] {
        didSet {
            persistIfNeeded {
                guard !micDeviceUIDs.isEmpty else {
                    defaults.removeObject(forKey: Keys.micDeviceUIDs)
                    return
                }

                if let data = try? JSONEncoder().encode(micDeviceUIDs) {
                    defaults.set(data, forKey: Keys.micDeviceUIDs)
                }
            }
        }
    }

    /// Promotes `uid` to the front of `micDeviceUIDs`, inserting it if not already present.
    func promoteMicDevice(_ uid: String) {
        var list = micDeviceUIDs
        list.removeAll { $0 == uid }
        list.insert(uid, at: 0)
        micDeviceUIDs = list
    }

    func removeMicDevice(_ uid: String) {
        micDeviceUIDs.removeAll { $0 == uid }
    }

    @Published var whisperModel: WhisperModelChoice {
        didSet {
            persistIfNeeded {
                defaults.set(whisperModel.rawValue, forKey: Keys.whisperModel)
            }
        }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var activeTriggerProfile: TriggerProfile
    @Published private(set) var activeDictionaryData: DictionaryData

    @Published var rewriteModelTier: RewriteModelTier {
        didSet {
            persistIfNeeded {
                defaults.set(rewriteModelTier.rawValue, forKey: Keys.rewriteModelTier)
            }
        }
    }

    @Published var alwaysAutoPaste: Bool {
        didSet {
            persistIfNeeded {
                defaults.set(alwaysAutoPaste, forKey: Keys.alwaysAutoPaste)
            }
        }
    }

    @Published var restorePreviousClipboardAfterAutoPaste: Bool {
        didSet {
            persistIfNeeded {
                defaults.set(
                    restorePreviousClipboardAfterAutoPaste,
                    forKey: Keys.restorePreviousClipboardAfterAutoPaste
                )
            }
        }
    }

    @Published var muteSoundEffects: Bool {
        didSet {
            persistIfNeeded {
                defaults.set(muteSoundEffects, forKey: Keys.muteSoundEffects)
            }
        }
    }

    @Published var recordingPillPosition: RecordingPillPosition {
        didSet {
            persistIfNeeded {
                defaults.set(recordingPillPosition.rawValue, forKey: Keys.recordingPillPosition)
            }
        }
    }

    @Published var holdShortcutKeyCode: Int {
        didSet {
            persistIfNeeded {
                defaults.set(holdShortcutKeyCode, forKey: Keys.holdShortcutKeyCode)
            }
        }
    }

    @Published var holdShortcutModifiers: UInt {
        didSet {
            persistIfNeeded {
                defaults.set(Int(holdShortcutModifiers), forKey: Keys.holdShortcutModifiers)
            }
        }
    }

    /// Alternate hold shortcut. -1 means unset (no binding).
    @Published var holdShortcutKeyCodeAlt: Int {
        didSet {
            persistIfNeeded {
                defaults.set(holdShortcutKeyCodeAlt, forKey: Keys.holdShortcutKeyCodeAlt)
            }
        }
    }

    @Published var holdShortcutModifiersAlt: UInt {
        didSet {
            persistIfNeeded {
                defaults.set(Int(holdShortcutModifiersAlt), forKey: Keys.holdShortcutModifiersAlt)
            }
        }
    }

    @Published var cloudLLMConfig: CloudLLMConfig {
        didSet {
            persistIfNeeded {
                if let data = try? JSONEncoder().encode(cloudLLMConfig) {
                    defaults.set(data, forKey: Keys.cloudLLMConfig)
                }
            }
        }
    }

    @Published var rewriteSystemPromptPrefix: String {
        didSet {
            let normalized = Self.normalizedRewritePromptPrefix(rewriteSystemPromptPrefix)
            if rewriteSystemPromptPrefix != normalized {
                rewriteSystemPromptPrefix = normalized
                return
            }

            persistIfNeeded {
                defaults.set(rewriteSystemPromptPrefix, forKey: Keys.rewriteSystemPromptPrefix)
            }
        }
    }

    var shouldPresentSetupOnLaunch: Bool {
        !hasCompletedInitialSetup
    }

    var shouldPresentOnboardingOnLaunch: Bool {
        completedOnboardingBuildIdentifier != currentBuildIdentifier
    }

    private let defaults: UserDefaults
    private let triggerProfileStore: TriggerProfileStore
    private let dictionaryStore: DictionaryStore
    private let currentBuildIdentifier: String

    init(
        userDefaults: UserDefaults,
        triggerProfileStore: TriggerProfileStore = .shared,
        dictionaryStore: DictionaryStore = .shared,
        initialTriggerProfile: TriggerProfile? = nil,
        initialDictionaryData: DictionaryData? = nil,
        currentBuildIdentifier: String? = nil
    ) {
        defaults = userDefaults
        self.triggerProfileStore = triggerProfileStore
        self.dictionaryStore = dictionaryStore
        self.currentBuildIdentifier = currentBuildIdentifier ?? Self.resolveCurrentBuildIdentifier()
        hasCompletedInitialSetup = userDefaults.bool(forKey: Keys.hasCompletedInitialSetup)
        completedOnboardingBuildIdentifier = userDefaults.string(
            forKey: Keys.completedOnboardingBuildIdentifier
        )
        onboardingResumeToken = userDefaults.string(forKey: Keys.onboardingResumeToken)
        hasRequestedMicrophonePermission = userDefaults.bool(forKey: Keys.hasRequestedMicrophonePermission)
        hasRequestedPostEventPermission = userDefaults.bool(forKey: Keys.hasRequestedPostEventPermission)
        if let data = userDefaults.data(forKey: Keys.micDeviceUIDs),
           let uids = try? JSONDecoder().decode([String].self, from: data) {
            micDeviceUIDs = uids
        } else if let legacy = userDefaults.string(forKey: Keys.micDeviceUID), !legacy.isEmpty {
            // Migrate from old single-UID preference.
            micDeviceUIDs = [legacy]
        } else {
            micDeviceUIDs = []
        }

        if userDefaults.object(forKey: Keys.showsMenuHints) == nil {
            showsMenuHints = true
        } else {
            showsMenuHints = userDefaults.bool(forKey: Keys.showsMenuHints)
        }

        let storedWhisperModel = userDefaults.string(forKey: Keys.whisperModel)
        let resolvedWhisperModel = WhisperModelChoice.resolvedStoredValue(storedWhisperModel) ?? .recommendedForHardware()
        whisperModel = resolvedWhisperModel

        if storedWhisperModel == WhisperModelChoice.legacyLargeTurboRawValue {
            userDefaults.set(resolvedWhisperModel.rawValue, forKey: Keys.whisperModel)
        }

        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if isUITesting {
            launchAtLogin = userDefaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        } else {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }

        if let storedTier = userDefaults.string(forKey: Keys.rewriteModelTier),
           let tier = RewriteModelTier(rawValue: storedTier) {
            rewriteModelTier = tier
        } else {
            rewriteModelTier = .standard2B
        }

        if userDefaults.object(forKey: Keys.alwaysAutoPaste) == nil {
            alwaysAutoPaste = true
        } else {
            alwaysAutoPaste = userDefaults.bool(forKey: Keys.alwaysAutoPaste)
        }

        if userDefaults.object(forKey: Keys.restorePreviousClipboardAfterAutoPaste) == nil {
            restorePreviousClipboardAfterAutoPaste = true
        } else {
            restorePreviousClipboardAfterAutoPaste = userDefaults.bool(
                forKey: Keys.restorePreviousClipboardAfterAutoPaste
            )
        }

        if userDefaults.object(forKey: Keys.muteSoundEffects) == nil {
            muteSoundEffects = false
        } else {
            muteSoundEffects = userDefaults.bool(forKey: Keys.muteSoundEffects)
        }

        if let storedPillPosition = userDefaults.string(forKey: Keys.recordingPillPosition),
           let pillPosition = RecordingPillPosition(rawValue: storedPillPosition) {
            recordingPillPosition = pillPosition
        } else {
            recordingPillPosition = .default
        }

        if userDefaults.object(forKey: Keys.holdShortcutKeyCode) == nil {
            holdShortcutKeyCode = Self.defaultHoldShortcutKeyCode
        } else {
            holdShortcutKeyCode = userDefaults.integer(forKey: Keys.holdShortcutKeyCode)
        }

        holdShortcutModifiers = UInt(max(0, userDefaults.integer(forKey: Keys.holdShortcutModifiers)))

        if userDefaults.object(forKey: Keys.holdShortcutKeyCodeAlt) == nil {
            holdShortcutKeyCodeAlt = Self.defaultHoldShortcutKeyCodeAlt
        } else {
            holdShortcutKeyCodeAlt = userDefaults.integer(forKey: Keys.holdShortcutKeyCodeAlt)
        }

        holdShortcutModifiersAlt = UInt(max(0, userDefaults.integer(forKey: Keys.holdShortcutModifiersAlt)))

        if let configData = userDefaults.data(forKey: Keys.cloudLLMConfig),
           let decoded = try? JSONDecoder().decode(CloudLLMConfig.self, from: configData) {
            cloudLLMConfig = decoded
        } else {
            cloudLLMConfig = .default
        }

        userDefaults.removeObject(forKey: Keys.legacyAllowClipboardAccess)

        let storedRewritePromptPrefix = userDefaults.string(forKey: Keys.rewriteSystemPromptPrefix)
        let migratedRewritePromptPrefix = Self.migratedRewriteSystemPromptPrefix(storedRewritePromptPrefix)
        rewriteSystemPromptPrefix = migratedRewritePromptPrefix
        if migratedRewritePromptPrefix != storedRewritePromptPrefix {
            userDefaults.set(migratedRewritePromptPrefix, forKey: Keys.rewriteSystemPromptPrefix)
        }

        activeTriggerProfile = (initialTriggerProfile ?? TriggerProfileStore.loadSynchronously()).normalized()
        activeDictionaryData = initialDictionaryData ?? DictionaryStore.loadSynchronously()
    }

    func completeInitialSetup() {
        hasCompletedInitialSetup = true
    }

    func acknowledgeOnboardingForCurrentBuild() {
        completedOnboardingBuildIdentifier = currentBuildIdentifier
        onboardingResumeToken = nil
    }

    func setOnboardingResumeToken(_ token: String?) {
        onboardingResumeToken = token
    }

    func recordMicrophonePermissionPrompt() {
        hasRequestedMicrophonePermission = true
    }

    func recordPostEventPermissionPrompt() {
        hasRequestedPostEventPermission = true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            defaults.set(enabled, forKey: Keys.launchAtLogin)
            launchAtLogin = enabled
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("TypeLessBuddy: failed to update launch-at-login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setCustomTrigger(primary: String) {
        activeTriggerProfile = activeTriggerProfile.updatingCustom(primary: primary)
        Task { [weak self] in
            _ = await self?.persistCustomTrigger(primary: primary)
        }
    }

    func resetAssistantNameToDefault() {
        activeTriggerProfile = .defaultProfile
        Task { [weak self] in
            _ = await self?.persistAssistantNameResetToDefault()
        }
    }

    @discardableResult
    func persistCustomTrigger(primary: String) async -> Bool {
        let nextProfile = activeTriggerProfile.updatingCustom(primary: primary)
        return await persistTriggerProfile(nextProfile, logContext: "custom trigger profile")
    }

    @discardableResult
    func persistAssistantNameResetToDefault() async -> Bool {
        await persistTriggerProfile(.defaultProfile, logContext: "assistant name reset")
    }

    func updateDictionaryData(_ data: DictionaryData) {
        Task { [weak self] in
            _ = await self?.persistDictionaryData(data)
        }
    }

    @discardableResult
    func persistDictionaryData(_ data: DictionaryData) async -> Bool {
        do {
            try await dictionaryStore.save(data)
            activeDictionaryData = data
            return true
        } catch {
            NSLog("TypeLessBuddy: failed to persist dictionary data: \(error.localizedDescription)")
            return false
        }
    }

    func restoreDefaultGeneralSettings() {
        micDeviceUIDs = []
        alwaysAutoPaste = true
        restorePreviousClipboardAfterAutoPaste = true
        muteSoundEffects = false
        recordingPillPosition = .default
    }

    func restoreDefaultHoldShortcuts() {
        holdShortcutKeyCode = Self.defaultHoldShortcutKeyCode
        holdShortcutModifiers = Self.defaultHoldShortcutModifiers
        holdShortcutKeyCodeAlt = Self.defaultHoldShortcutKeyCodeAlt
        holdShortcutModifiersAlt = Self.defaultHoldShortcutModifiersAlt
    }

    func clearWordReplacements() {
        guard !activeDictionaryData.replacements.isEmpty else {
            return
        }

        var data = activeDictionaryData
        data.replacements.removeAll()
        updateDictionaryData(data)
    }

    @discardableResult
    private func persistTriggerProfile(_ nextProfile: TriggerProfile, logContext: String) async -> Bool {
        let normalizedProfile = nextProfile.normalized()
        do {
            try await triggerProfileStore.save(normalizedProfile)
            activeTriggerProfile = normalizedProfile
            return true
        } catch {
            NSLog("TypeLessBuddy: failed to persist \(logContext): \(error.localizedDescription)")
            return false
        }
    }

    private static func migratedRewriteSystemPromptPrefix(_ storedValue: String?) -> String {
        guard let storedValue else {
            return LLMRewriteService.defaultAssistantSystemPromptTemplate
        }

        let trimmedValue = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLegacyDefault = LLMRewriteService.legacyDefaultRewritePromptPrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty || trimmedValue == trimmedLegacyDefault {
            return LLMRewriteService.defaultAssistantSystemPromptTemplate
        }

        return LLMRewriteService.normalizeAssistantSystemPromptTemplate(storedValue)
    }

    private static func normalizedRewritePromptPrefix(_ value: String) -> String {
        LLMRewriteService.normalizeAssistantSystemPromptTemplate(value)
    }

    private static func resolveCurrentBuildIdentifier(bundle: Bundle = .main) -> String {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let buildDate = bundle.executableURL
            .flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            ?? (try? bundle.bundleURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        guard let buildDate else {
            return [shortVersion, buildVersion].joined(separator: "|")
        }

        return [
            shortVersion,
            buildVersion,
            ISO8601DateFormatter().string(from: buildDate)
        ].joined(separator: "|")
    }

    private static func makeShared() -> ShellPreferences {
        let arguments = ProcessInfo.processInfo.arguments
        let suiteName = arguments.contains("-ui-testing") ? "\(Keys.suiteName).ui-tests" : Keys.suiteName
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard

        if arguments.contains("-reset-shell-preferences") {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        if arguments.contains("-complete-shell-setup") {
            userDefaults.set(true, forKey: Keys.hasCompletedInitialSetup)
            userDefaults.set(true, forKey: Keys.launchAtLogin)
        }

        if arguments.contains("-hide-menu-hints") {
            userDefaults.set(false, forKey: Keys.showsMenuHints)
        }

        if arguments.contains("-mark-microphone-requested") {
            userDefaults.set(true, forKey: Keys.hasRequestedMicrophonePermission)
        }

        if arguments.contains("-mark-postevent-requested") {
            userDefaults.set(true, forKey: Keys.hasRequestedPostEventPermission)
        }

        let triggerStore: TriggerProfileStore
        let initialTriggerProfile: TriggerProfile
        let dictStore: DictionaryStore
        let initialDictionaryData: DictionaryData

        if arguments.contains("-ui-testing") {
            // Use an isolated, temporary trigger-profile store for UI tests so
            // they never read or mutate the developer's real Application Support store.
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TypeLessBuddy.UITests", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let testStoreURL = tempDir.appendingPathComponent("TriggerProfileStore.json")
            // Remove leftover file from a previous test run so each launch is clean.
            try? FileManager.default.removeItem(at: testStoreURL)
            triggerStore = TriggerProfileStore(storeURL: testStoreURL)

            // Optionally seed a specific preset via '-seed-trigger-preset <preset>'
            var seedProfile = TriggerProfile.defaultProfile
            if let presetIndex = arguments.firstIndex(of: "-seed-trigger-preset"),
               arguments.indices.contains(arguments.index(after: presetIndex)),
               let preset = TriggerNamePreset(rawValue: arguments[arguments.index(after: presetIndex)]) {
                seedProfile = seedProfile.settingActiveProfile(preset)
            }

            if let customNameIndex = arguments.firstIndex(of: "-seed-trigger-custom-name"),
               arguments.indices.contains(arguments.index(after: customNameIndex)) {
                seedProfile = seedProfile.updatingCustom(
                    primary: arguments[arguments.index(after: customNameIndex)]
                )
            }

            initialTriggerProfile = seedProfile

            let dictTestURL = tempDir.appendingPathComponent("DictionaryStore.json")
            try? FileManager.default.removeItem(at: dictTestURL)
            dictStore = DictionaryStore(storeURL: dictTestURL)
            initialDictionaryData = .empty
        } else {
            triggerStore = TriggerProfileStore.shared
            initialTriggerProfile = TriggerProfileStore.loadSynchronously()
            dictStore = DictionaryStore.shared
            initialDictionaryData = DictionaryStore.loadSynchronously()
        }

        return ShellPreferences(
            userDefaults: userDefaults,
            triggerProfileStore: triggerStore,
            dictionaryStore: dictStore,
            initialTriggerProfile: initialTriggerProfile,
            initialDictionaryData: initialDictionaryData
        )
    }

    private func persistIfNeeded(_ operation: () -> Void) {
        operation()
    }
}
