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
        static let autoModelSelection = "autoModelSelection"
        static let launchAtLogin = "launchAtLogin"
        static let convertModes = "convertModes"
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

    @Published var autoModelSelection: Bool {
        didSet {
            persistIfNeeded {
                defaults.set(autoModelSelection, forKey: Keys.autoModelSelection)
            }
        }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var activeTriggerProfile: TriggerProfile

    @Published var convertModes: [ConvertMode] {
        didSet {
            persistIfNeeded {
                let rawValues = self.convertModes.map(\.rawValue)
                self.defaults.set(rawValues, forKey: Keys.convertModes)
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

        if let storedModel = userDefaults.string(forKey: Keys.whisperModel),
           let model = WhisperModelChoice(rawValue: storedModel) {
            whisperModel = model
        } else {
            whisperModel = .baseEN
        }

        autoModelSelection = userDefaults.object(forKey: Keys.autoModelSelection) as? Bool ?? false

        launchAtLogin = SMAppService.mainApp.status == .enabled

        if let stored = userDefaults.stringArray(forKey: Keys.convertModes) {
            let decoded = stored.compactMap(ConvertMode.init(rawValue:))
            convertModes = decoded.isEmpty ? ConvertMode.allBuiltIns : decoded
        } else {
            convertModes = ConvertMode.allBuiltIns
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

    func setTriggerPreset(_ preset: TriggerNamePreset) {
        let nextProfile = activeTriggerProfile.settingActiveProfile(preset)
        Task { [weak self, triggerProfileStore] in
            do {
                try await triggerProfileStore.save(nextProfile)
                await MainActor.run {
                    self?.activeTriggerProfile = nextProfile
                }
            } catch {
                NSLog("Speech2Text: failed to persist trigger preset: \(error.localizedDescription)")
            }
        }
    }

    func setCustomTrigger(primary: String, aliases: [String]) {
        let nextProfile = activeTriggerProfile.updatingCustom(primary: primary, aliases: aliases)
        Task { [weak self, triggerProfileStore] in
            do {
                try await triggerProfileStore.save(nextProfile)
                await MainActor.run {
                    self?.activeTriggerProfile = nextProfile
                }
            } catch {
                NSLog("Speech2Text: failed to persist custom trigger profile: \(error.localizedDescription)")
            }
        }
    }

    func applyCalibrationAliases(_ aliases: [String]) {
        let normalizedAliases = TriggerAliasNormalizer.normalize(aliases)
        Task { [weak self, triggerProfileStore] in
            do {
                let updated = try await triggerProfileStore.replaceAliasesForActiveProfile(normalizedAliases)
                await MainActor.run {
                    self?.activeTriggerProfile = updated
                }
            } catch {
                NSLog("Speech2Text: failed to persist calibration aliases: \(error.localizedDescription)")
            }
        }
    }

    func reset() {
        withPersistenceSuspended {
            hasCompletedInitialSetup = false
            showsMenuHints = true
            hasRequestedMicrophonePermission = false
            hasRequestedKeyboardPermission = false
            hasRequestedPostEventPermission = false
            micDeviceUID = nil
            whisperModel = .baseEN
            autoModelSelection = false
            convertModes = ConvertMode.allBuiltIns
            activeTriggerProfile = .defaultProfile
        }

        defaults.removeObject(forKey: Keys.hasCompletedInitialSetup)
        defaults.removeObject(forKey: Keys.showsMenuHints)
        defaults.removeObject(forKey: Keys.hasRequestedMicrophonePermission)
        defaults.removeObject(forKey: Keys.hasRequestedKeyboardPermission)
        defaults.removeObject(forKey: Keys.hasRequestedPostEventPermission)
        defaults.removeObject(forKey: Keys.micDeviceUID)
        defaults.removeObject(forKey: Keys.whisperModel)
        defaults.removeObject(forKey: Keys.autoModelSelection)
        defaults.removeObject(forKey: Keys.convertModes)

        Task { [triggerProfileStore] in
            do {
                try await triggerProfileStore.save(.defaultProfile)
            } catch {
                NSLog("Speech2Text: failed to reset trigger profile store: \(error.localizedDescription)")
            }
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

            // Optionally seed calibrated aliases via '-seed-trigger-profile-calibrated'
            if arguments.contains("-seed-trigger-profile-calibrated") {
                let activePreset = seedProfile.activeProfile
                let canonicalName = activePreset == .custom
                    ? seedProfile.customPrimary.lowercased()
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
