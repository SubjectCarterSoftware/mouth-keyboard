import Combine
import Foundation

@MainActor
protocol ReadinessProviding {
    var snapshot: ReadinessSnapshot { get }
}

extension ReadinessStore: ReadinessProviding {}

@MainActor
final class ActivationStore: ObservableObject {
    static let shared = ActivationStore(preferences: .shared, readinessStore: .shared)

    @Published private(set) var state: RecordingState = .idle

    private let preferences: ShellPreferences
    private let readinessProvider: any ReadinessProviding

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

        state = .recording
    }

    func stop() {
        state = .idle
    }
}
