import AudioToolbox
import Combine
import Foundation

// MARK: - ActivationSoundPlayer

struct ActivationSoundPlayer {
    // System sound 1057 is the keyboard click — no bundled audio file required.
    func play() {
        AudioServicesPlaySystemSound(1057)
    }
}

// MARK: - ReadinessProviding

@MainActor
protocol ReadinessProviding {
    var snapshot: ReadinessSnapshot { get }
}

extension ReadinessStore: ReadinessProviding {}

// MARK: - ActivationStore

@MainActor
final class ActivationStore: ObservableObject {
    static let shared = ActivationStore(preferences: .shared, readinessStore: .shared)

    @Published private(set) var state: RecordingState = .idle

    private let preferences: ShellPreferences
    private let readinessProvider: any ReadinessProviding
    var soundPlayer: ActivationSoundPlayer = .init()

    convenience init(preferences: ShellPreferences, readinessStore: ReadinessStore) {
        self.init(preferences: preferences, readinessProvider: readinessStore)
    }

    init(preferences: ShellPreferences, readinessProvider: any ReadinessProviding) {
        self.preferences = preferences
        self.readinessProvider = readinessProvider
    }

    func arm() {
        // Require all permissions to be granted, but do NOT require setup to be
        // "finalized" (hasCompletedInitialSetup). The finalize step is an
        // onboarding UX gate, not a runtime safety requirement. Recording must
        // work as soon as microphone and keyboard-monitoring permissions are
        // authorized, even if the user dismissed the setup window early.
        let snapshot = readinessProvider.snapshot
        guard snapshot.permissions.allSatisfy(\.isAuthorized) else {
            return
        }

        if preferences.activationSoundEnabled {
            soundPlayer.play()
        }

        state = .recording
    }

    func stop() {
        state = .idle
    }
}
