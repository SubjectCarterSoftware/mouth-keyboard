import AppKit
import Combine
import Foundation

// MARK: - ActivationSoundPlayer

struct ActivationSoundPlayer {
    private let playStartImpl: () -> Void
    private let playSuccessImpl: () -> Void
    private let playFailureImpl: () -> Void
    private let playNoteSavedImpl: () -> Void
    private let playSuccessThenNoteSavedImpl: () -> Void

    init(
        playStart: @escaping () -> Void = { Self.playNamedSound("Tink") },
        playSuccess: @escaping () -> Void = { Self.playNamedSound("Glass") },
        playFailure: @escaping () -> Void = { Self.playNamedSound("Basso") },
        playNoteSaved: @escaping () -> Void = { Self.playNamedSound("NoteSaved") },
        playSuccessThenNoteSaved: @escaping () -> Void = { Self.playSuccessThenNoteSavedDefault() }
    ) {
        self.playStartImpl = playStart
        self.playSuccessImpl = playSuccess
        self.playFailureImpl = playFailure
        self.playNoteSavedImpl = playNoteSaved
        self.playSuccessThenNoteSavedImpl = playSuccessThenNoteSaved
    }

    /// A no-op player. Useful in tests so running the suite does not play real
    /// system sounds for every simulated success/failure.
    static let silent = ActivationSoundPlayer(
        playStart: {},
        playSuccess: {},
        playFailure: {},
        playNoteSaved: {},
        playSuccessThenNoteSaved: {}
    )

    func play() {
        playStartImpl()
    }

    func playSuccess() {
        playSuccessImpl()
    }

    func playFailure() {
        playFailureImpl()
    }

    func playNoteSaved() {
        playNoteSavedImpl()
    }

    func playSuccessThenNoteSaved() {
        playSuccessThenNoteSavedImpl()
    }

    private static func playSuccessThenNoteSavedDefault() {
        let successSound = sound(named: "Glass")
        guard let noteSound = sound(named: "NoteSaved") else {
            successSound?.play()
            return
        }
        guard let successSound else {
            noteSound.play()
            return
        }

        let delay = max(successSound.duration, 0.1)
        successSound.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [successSound, noteSound] in
            _ = successSound
            noteSound.play()
        }
    }

    private static func playNamedSound(_ name: String) {
        sound(named: name)?.play()
    }

    private static func sound(named name: String) -> NSSound? {
        if let url = Bundle.main.url(forResource: name, withExtension: "aiff") {
            return NSSound(contentsOf: url, byReference: false)
        }
        return NSSound(named: name)
    }
}

// MARK: - ReadinessProviding

@MainActor
protocol ReadinessProviding {
    var snapshot: ReadinessSnapshot { get }
}

extension ReadinessStore: ReadinessProviding {}

@MainActor
protocol WhisperModelLoadStateProviding: AnyObject {
    var phase: WhisperModelLoadState.Phase { get }
    var phasePublisher: AnyPublisher<WhisperModelLoadState.Phase, Never> { get }
}

extension WhisperModelLoadState: WhisperModelLoadStateProviding {
    var phasePublisher: AnyPublisher<WhisperModelLoadState.Phase, Never> {
        $phase.eraseToAnyPublisher()
    }
}

// MARK: - Sleeping

/// Abstraction over time-based suspension so background timers (e.g. the
/// success-dismiss countdown) can be driven by virtual time in tests instead
/// of real wall-clock sleeps. Production uses `SystemSleeper`, which is a thin
/// wrapper over `Task.sleep` and preserves the previous behaviour exactly.
protocol Sleeping: Sendable {
    func sleep(nanoseconds: UInt64) async
}

struct SystemSleeper: Sleeping {
    func sleep(nanoseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
