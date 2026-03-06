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
        guard readinessProvider.snapshot.state == .ready else {
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
