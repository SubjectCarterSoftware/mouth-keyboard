import Combine
import Foundation

@MainActor
final class ShellPreferences: ObservableObject {
    enum Keys {
        static let suiteName = "com.elicarter.Speech2Test.shell"
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
        static let showsMenuHints = "showsMenuHints"
        static let hasRequestedMicrophonePermission = "hasRequestedMicrophonePermission"
        static let hasRequestedKeyboardPermission = "hasRequestedKeyboardPermission"
        static let tapMode = "tapMode"
        static let activationSoundEnabled = "activationSoundEnabled"
        static let micDeviceUID = "micDeviceUID"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let indicatorVisible = "indicatorVisible"
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

    @Published var tapMode: TapMode {
        didSet {
            persistIfNeeded {
                defaults.set(tapMode.rawValue, forKey: Keys.tapMode)
            }
        }
    }

    @Published var activationSoundEnabled: Bool {
        didSet {
            persistIfNeeded {
                defaults.set(activationSoundEnabled, forKey: Keys.activationSoundEnabled)
            }
        }
    }

    @Published var micDeviceUID: String? {
        didSet {
            persistIfNeeded {
                defaults.set(micDeviceUID ?? "", forKey: Keys.micDeviceUID)
            }
        }
    }

    @Published var autoPasteEnabled: Bool {
        didSet {
            persistIfNeeded {
                defaults.set(autoPasteEnabled, forKey: Keys.autoPasteEnabled)
            }
        }
    }

    @Published var indicatorVisible: Bool {
        didSet {
            persistIfNeeded {
                defaults.set(indicatorVisible, forKey: Keys.indicatorVisible)
            }
        }
    }

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
        tapMode = TapMode(rawValue: userDefaults.string(forKey: Keys.tapMode) ?? "") ?? .double
        activationSoundEnabled = userDefaults.object(forKey: Keys.activationSoundEnabled) as? Bool ?? true

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

        autoPasteEnabled = userDefaults.object(forKey: Keys.autoPasteEnabled) as? Bool ?? true
        indicatorVisible = userDefaults.object(forKey: Keys.indicatorVisible) as? Bool ?? true
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

    func reset() {
        withPersistenceSuspended {
            hasCompletedInitialSetup = false
            showsMenuHints = true
            hasRequestedMicrophonePermission = false
            hasRequestedKeyboardPermission = false
            tapMode = .double
            activationSoundEnabled = true
            micDeviceUID = nil
            autoPasteEnabled = true
            indicatorVisible = true
        }

        defaults.removeObject(forKey: Keys.hasCompletedInitialSetup)
        defaults.removeObject(forKey: Keys.showsMenuHints)
        defaults.removeObject(forKey: Keys.hasRequestedMicrophonePermission)
        defaults.removeObject(forKey: Keys.hasRequestedKeyboardPermission)
        defaults.removeObject(forKey: Keys.tapMode)
        defaults.removeObject(forKey: Keys.activationSoundEnabled)
        defaults.removeObject(forKey: Keys.micDeviceUID)
        defaults.removeObject(forKey: Keys.autoPasteEnabled)
        defaults.removeObject(forKey: Keys.indicatorVisible)
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

        if arguments.contains("-mark-microphone-requested") {
            userDefaults.set(true, forKey: Keys.hasRequestedMicrophonePermission)
        }

        if arguments.contains("-mark-keyboard-requested") {
            userDefaults.set(true, forKey: Keys.hasRequestedKeyboardPermission)
        }

        if arguments.contains("-set-tap-mode-single") {
            userDefaults.set(TapMode.single.rawValue, forKey: Keys.tapMode)
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
