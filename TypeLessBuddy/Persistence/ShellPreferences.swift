import Combine
import Foundation
import ServiceManagement

@MainActor
final class ShellPreferences: ObservableObject {
    enum Keys {
        static let suiteName = "com.elicarter.TypeLessBuddy.shell"
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
        static let showsMenuHints = "showsMenuHints"
        static let hasRequestedMicrophonePermission = "hasRequestedMicrophonePermission"
        static let hasRequestedKeyboardPermission = "hasRequestedKeyboardPermission"
        static let hasRequestedPostEventPermission = "hasRequestedPostEventPermission"
        static let micDeviceUID = "micDeviceUID" // legacy — kept for migration only
        static let micDeviceUIDs = "micDeviceUIDs"
        static let whisperModel = "whisperModel"
        static let launchAtLogin = "launchAtLogin"
        static let rewriteModelTier = "rewriteModelTier"
        static let alwaysAutoPaste = "alwaysAutoPaste"
        static let holdShortcutKeyCode = "holdShortcutKeyCode"
        static let holdShortcutModifiers = "holdShortcutModifiers"
        static let holdShortcutKeyCodeAlt = "holdShortcutKeyCodeAlt"
        static let holdShortcutModifiersAlt = "holdShortcutModifiersAlt"
        static let cloudLLMConfig = "cloudLLMConfig"
        static let legacyAllowClipboardAccess = "allowClipboardAccess"
        static let rewriteSystemPromptPrefix = "rewriteSystemPromptPrefix"
    }

    static let shared = makeShared()

    @Published var hasCompletedInitialSetup: Bool {
        didSet {
            defaults.set(hasCompletedInitialSetup, forKey: Keys.hasCompletedInitialSetup)
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

    @Published var hasRequestedKeyboardPermission: Bool {
        didSet {
            defaults.set(hasRequestedKeyboardPermission, forKey: Keys.hasRequestedKeyboardPermission)
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

    @Published var whisperModel: WhisperModelChoice {
        didSet {
            persistIfNeeded {
                defaults.set(whisperModel.rawValue, forKey: Keys.whisperModel)
            }
        }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var activeTriggerProfile: TriggerProfile

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

    private let defaults: UserDefaults
    private let triggerProfileStore: TriggerProfileStore
    private var isPersistenceSuspended = false

    init(
        userDefaults: UserDefaults,
        triggerProfileStore: TriggerProfileStore = .shared,
        initialTriggerProfile: TriggerProfile? = nil
    ) {
        defaults = userDefaults
        self.triggerProfileStore = triggerProfileStore
        hasCompletedInitialSetup = userDefaults.bool(forKey: Keys.hasCompletedInitialSetup)
        hasRequestedMicrophonePermission = userDefaults.bool(forKey: Keys.hasRequestedMicrophonePermission)
        hasRequestedKeyboardPermission = userDefaults.bool(forKey: Keys.hasRequestedKeyboardPermission)
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

        if userDefaults.object(forKey: Keys.holdShortcutKeyCode) == nil {
            holdShortcutKeyCode = 61
        } else {
            holdShortcutKeyCode = userDefaults.integer(forKey: Keys.holdShortcutKeyCode)
        }

        holdShortcutModifiers = UInt(max(0, userDefaults.integer(forKey: Keys.holdShortcutModifiers)))

        if userDefaults.object(forKey: Keys.holdShortcutKeyCodeAlt) == nil {
            holdShortcutKeyCodeAlt = -1
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
    }

    func completeInitialSetup() {
        hasCompletedInitialSetup = true
    }

    func recordMicrophonePermissionPrompt() {
        hasRequestedMicrophonePermission = true
    }

    func recordKeyboardPermissionPrompt() {
        hasRequestedKeyboardPermission = true
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
        Task { [weak self] in
            _ = await self?.persistCustomTrigger(primary: primary)
        }
    }

    func resetAssistantNameToDefault() {
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


    func reset() {
        withPersistenceSuspended {
            hasCompletedInitialSetup = false
            showsMenuHints = true
            hasRequestedMicrophonePermission = false
            hasRequestedKeyboardPermission = false
            hasRequestedPostEventPermission = false
            launchAtLogin = false
            micDeviceUIDs = []
            whisperModel = .smallEN
            rewriteModelTier = .standard2B
            alwaysAutoPaste = true
            rewriteSystemPromptPrefix = LLMRewriteService.defaultAssistantSystemPromptTemplate
            holdShortcutKeyCode = 61
            holdShortcutModifiers = 0
            cloudLLMConfig = .default
            activeTriggerProfile = .defaultProfile
        }

        defaults.removeObject(forKey: Keys.hasCompletedInitialSetup)
        defaults.removeObject(forKey: Keys.showsMenuHints)
        defaults.removeObject(forKey: Keys.hasRequestedMicrophonePermission)
        defaults.removeObject(forKey: Keys.hasRequestedKeyboardPermission)
        defaults.removeObject(forKey: Keys.hasRequestedPostEventPermission)
        defaults.removeObject(forKey: Keys.launchAtLogin)
        defaults.removeObject(forKey: Keys.micDeviceUID)
        defaults.removeObject(forKey: Keys.micDeviceUIDs)
        defaults.removeObject(forKey: Keys.whisperModel)
        defaults.removeObject(forKey: Keys.rewriteModelTier)
        defaults.removeObject(forKey: Keys.alwaysAutoPaste)
        defaults.removeObject(forKey: Keys.legacyAllowClipboardAccess)
        defaults.removeObject(forKey: Keys.rewriteSystemPromptPrefix)
        defaults.removeObject(forKey: Keys.holdShortcutKeyCode)
        defaults.removeObject(forKey: Keys.holdShortcutModifiers)
        defaults.removeObject(forKey: Keys.cloudLLMConfig)

        Task { [triggerProfileStore] in
            do {
                try await triggerProfileStore.save(.defaultProfile)
            } catch {
                NSLog("TypeLessBuddy: failed to reset trigger profile store: \(error.localizedDescription)")
            }
        }
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

        if arguments.contains("-mark-keyboard-requested") {
            userDefaults.set(true, forKey: Keys.hasRequestedKeyboardPermission)
        }

        if arguments.contains("-mark-postevent-requested") {
            userDefaults.set(true, forKey: Keys.hasRequestedPostEventPermission)
        }

        let triggerStore: TriggerProfileStore
        let initialTriggerProfile: TriggerProfile

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
        } else {
            triggerStore = TriggerProfileStore.shared
            initialTriggerProfile = TriggerProfileStore.loadSynchronously()
        }

        return ShellPreferences(
            userDefaults: userDefaults,
            triggerProfileStore: triggerStore,
            initialTriggerProfile: initialTriggerProfile
        )
    }

    private func withPersistenceSuspended(_ operation: () -> Void) {
        isPersistenceSuspended = true
        operation()
        isPersistenceSuspended = false
    }

    private func persistIfNeeded(_ operation: () -> Void) {
        guard !isPersistenceSuspended else {
            return
        }

        operation()
    }
}
