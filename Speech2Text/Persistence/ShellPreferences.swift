import Combine
import Foundation

@MainActor
final class ShellPreferences: ObservableObject {
    enum Keys {
        static let suiteName = "com.elicarter.Speech2Text.shell"
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
        static let showsMenuHints = "showsMenuHints"
        static let hasRequestedMicrophonePermission = "hasRequestedMicrophonePermission"
        static let hasRequestedKeyboardPermission = "hasRequestedKeyboardPermission"
        static let activationSoundEnabled = "activationSoundEnabled"
        static let micDeviceUID = "micDeviceUID"
        static let indicatorVisible = "indicatorVisible"
        static let whisperModel = "whisperModel"
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

    @Published var indicatorVisible: Bool {
        didSet {
            persistIfNeeded {
                defaults.set(indicatorVisible, forKey: Keys.indicatorVisible)
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

        indicatorVisible = userDefaults.object(forKey: Keys.indicatorVisible) as? Bool ?? true

        if let storedModel = userDefaults.string(forKey: Keys.whisperModel),
           let model = WhisperModelChoice(rawValue: storedModel) {
            whisperModel = model
        } else {
            whisperModel = .tinyEN
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

    func reset() {
        withPersistenceSuspended {
            hasCompletedInitialSetup = false
            showsMenuHints = true
            hasRequestedMicrophonePermission = false
            hasRequestedKeyboardPermission = false
            activationSoundEnabled = true
            micDeviceUID = nil
            indicatorVisible = true
            whisperModel = .tinyEN
        }

        defaults.removeObject(forKey: Keys.hasCompletedInitialSetup)
        defaults.removeObject(forKey: Keys.showsMenuHints)
        defaults.removeObject(forKey: Keys.hasRequestedMicrophonePermission)
        defaults.removeObject(forKey: Keys.hasRequestedKeyboardPermission)
        defaults.removeObject(forKey: Keys.activationSoundEnabled)
        defaults.removeObject(forKey: Keys.micDeviceUID)
        defaults.removeObject(forKey: Keys.indicatorVisible)
        defaults.removeObject(forKey: Keys.whisperModel)
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

        if arguments.contains("-hide-recording-indicator") {
            userDefaults.set(false, forKey: Keys.indicatorVisible)
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
