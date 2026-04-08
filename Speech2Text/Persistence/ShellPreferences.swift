import Combine
import Foundation
import ServiceManagement

@MainActor
final class ShellPreferences: ObservableObject {
    enum Keys {
        static let suiteName = "com.elicarter.Speech2Text.shell"
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
        static let showsMenuHints = "showsMenuHints"
        static let hasRequestedMicrophonePermission = "hasRequestedMicrophonePermission"
        static let hasRequestedKeyboardPermission = "hasRequestedKeyboardPermission"
        static let hasRequestedPostEventPermission = "hasRequestedPostEventPermission"
        static let micDeviceUID = "micDeviceUID"
        static let whisperModel = "whisperModel"
        static let launchAtLogin = "launchAtLogin"
        static let rewriteModelTier = "rewriteModelTier"
        static let alwaysAutoPaste = "alwaysAutoPaste"
        static let holdShortcutKeyCode = "holdShortcutKeyCode"
        static let holdShortcutModifiers = "holdShortcutModifiers"
        static let holdShortcutKeyCodeAlt = "holdShortcutKeyCodeAlt"
        static let holdShortcutModifiersAlt = "holdShortcutModifiersAlt"
        static let cloudLLMConfig = "cloudLLMConfig"
        static let allowClipboardAccess = "allowClipboardAccess"
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

    @Published var micDeviceUID: String? {
        didSet {
            persistIfNeeded {
                defaults.set(micDeviceUID ?? "", forKey: Keys.micDeviceUID)
            }
        }
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

    @Published var allowClipboardAccess: Bool {
        didSet {
            persistIfNeeded {
                defaults.set(allowClipboardAccess, forKey: Keys.allowClipboardAccess)
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
        let storedMicDeviceUID = userDefaults.string(forKey: Keys.micDeviceUID)
        if let storedMicDeviceUID, !storedMicDeviceUID.isEmpty {
            micDeviceUID = storedMicDeviceUID
        } else {
            micDeviceUID = nil
        }

        if userDefaults.object(forKey: Keys.showsMenuHints) == nil {
            showsMenuHints = true
        } else {
            showsMenuHints = userDefaults.bool(forKey: Keys.showsMenuHints)
        }

        let storedWhisperModel = userDefaults.string(forKey: Keys.whisperModel)
        let resolvedWhisperModel = WhisperModelChoice.resolvedStoredValue(storedWhisperModel) ?? .smallEN
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

        if userDefaults.object(forKey: Keys.allowClipboardAccess) == nil {
            allowClipboardAccess = true
        } else {
            allowClipboardAccess = userDefaults.bool(forKey: Keys.allowClipboardAccess)
        }

        let loadedTriggerProfile = (initialTriggerProfile ?? TriggerProfileStore.loadSynchronously()).normalized()
        let migratedTriggerProfile = Self.migratedTriggerProfile(loadedTriggerProfile)
        activeTriggerProfile = migratedTriggerProfile

        if migratedTriggerProfile != loadedTriggerProfile {
            Task { [triggerProfileStore] in
                do {
                    try await triggerProfileStore.save(migratedTriggerProfile)
                } catch {
                    NSLog("Speech2Text: failed to migrate trigger profile: \(error.localizedDescription)")
                }
            }
        }
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
            NSLog("Speech2Text: failed to update launch-at-login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setCustomTrigger(primary: String, aliases: [String]) {
        Task { [weak self] in
            _ = await self?.persistCustomTrigger(primary: primary, aliases: aliases)
        }
    }

    func resetAssistantNameToDefault() {
        Task { [weak self] in
            _ = await self?.persistAssistantNameResetToDefault()
        }
    }

    @discardableResult
    func persistCustomTrigger(primary: String, aliases: [String]) async -> Bool {
        let nextProfile = activeTriggerProfile.updatingCustom(primary: primary, aliases: aliases)
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
            micDeviceUID = nil
            whisperModel = .smallEN
            rewriteModelTier = .standard2B
            alwaysAutoPaste = true
            allowClipboardAccess = true
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
        defaults.removeObject(forKey: Keys.whisperModel)
        defaults.removeObject(forKey: Keys.rewriteModelTier)
        defaults.removeObject(forKey: Keys.alwaysAutoPaste)
        defaults.removeObject(forKey: Keys.allowClipboardAccess)
        defaults.removeObject(forKey: Keys.holdShortcutKeyCode)
        defaults.removeObject(forKey: Keys.holdShortcutModifiers)
        defaults.removeObject(forKey: Keys.cloudLLMConfig)

        Task { [triggerProfileStore] in
            do {
                try await triggerProfileStore.save(.defaultProfile)
            } catch {
                NSLog("Speech2Text: failed to reset trigger profile store: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    private func persistTriggerProfile(_ nextProfile: TriggerProfile, logContext: String) async -> Bool {
        let normalizedProfile = Self.migratedTriggerProfile(nextProfile.normalized())
        do {
            try await triggerProfileStore.save(normalizedProfile)
            activeTriggerProfile = normalizedProfile
            return true
        } catch {
            NSLog("Speech2Text: failed to persist \(logContext): \(error.localizedDescription)")
            return false
        }
    }

    private static func migratedTriggerProfile(_ profile: TriggerProfile) -> TriggerProfile {
        switch profile.activeProfile {
        case .atlas, .gaia:
            return profile.settingActiveProfile(.zeus)
        case .zeus, .custom:
            return profile
        }
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
                .appendingPathComponent("Speech2Text.UITests", isDirectory: true)
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
                    primary: arguments[arguments.index(after: customNameIndex)],
                    aliases: []
                )
            }

            // Optionally seed calibrated aliases via '-seed-trigger-profile-calibrated'
            if arguments.contains("-seed-trigger-profile-calibrated") {
                let activePreset = seedProfile.activeProfile
                let canonicalName = activePreset == .custom
                    ? TriggerProfile.normalizeAlias(seedProfile.customPrimary)
                    : activePreset.canonicalAlias
                let calibratedAliases = [canonicalName, "hey \(canonicalName)", "assistant \(canonicalName)"]
                seedProfile = seedProfile.replacingAliasesForActiveProfile(calibratedAliases)
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
