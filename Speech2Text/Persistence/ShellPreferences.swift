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
        static let micDeviceUID = "micDeviceUID"
        static let whisperModel = "whisperModel"
        static let autoModelSelection = "autoModelSelection"
        static let launchAtLogin = "launchAtLogin"
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

    var shouldPresentSetupOnLaunch: Bool {
        !hasCompletedInitialSetup
    }

    private let defaults: UserDefaults
    private var isPersistenceSuspended = false

    init(userDefaults: UserDefaults) {
        defaults = userDefaults
        hasCompletedInitialSetup = userDefaults.bool(forKey: Keys.hasCompletedInitialSetup)
        hasRequestedMicrophonePermission = userDefaults.bool(forKey: Keys.hasRequestedMicrophonePermission)
        hasRequestedKeyboardPermission = userDefaults.bool(forKey: Keys.hasRequestedKeyboardPermission)
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

    func reset() {
        withPersistenceSuspended {
            hasCompletedInitialSetup = false
            showsMenuHints = true
            hasRequestedMicrophonePermission = false
            hasRequestedKeyboardPermission = false
            micDeviceUID = nil
            whisperModel = .baseEN
            autoModelSelection = false
        }

        defaults.removeObject(forKey: Keys.hasCompletedInitialSetup)
        defaults.removeObject(forKey: Keys.showsMenuHints)
        defaults.removeObject(forKey: Keys.hasRequestedMicrophonePermission)
        defaults.removeObject(forKey: Keys.hasRequestedKeyboardPermission)
        defaults.removeObject(forKey: Keys.micDeviceUID)
        defaults.removeObject(forKey: Keys.whisperModel)
        defaults.removeObject(forKey: Keys.autoModelSelection)
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

        return ShellPreferences(userDefaults: userDefaults)
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
