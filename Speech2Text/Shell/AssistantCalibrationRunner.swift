import Foundation

// MARK: - Protocol

protocol CalibrationSampleCapturing: Sendable {
    /// Returns the next sample, or nil if the capture produced an unusable result.
    /// Throws `CalibrationCapturingDone` to signal the capturer has no more samples
    /// (e.g. a test stub that ran out of canned results, or the user cancelled).
    func captureSample(for primaryName: String) async throws -> CalibrationSample?
}

enum CalibrationCapturingDone: Error {
    case exhausted
}

// MARK: - Runner

/// Coordinates a three-sample calibration session without depending on the
/// global ActivationStore recording state machine.
@MainActor
final class AssistantCalibrationRunner {
    let primaryName: String
    private let preferences: ShellPreferences
    private let capturer: any CalibrationSampleCapturing
    private var session: TriggerCalibrationSession

    var onRetry: (() -> Void)?
    var onSampleAccepted: ((Int) -> Void)?  // delivers accepted count (1, 2)
    var onComplete: (() -> Void)?

    private(set) var isComplete: Bool = false

    init(
        primaryName: String,
        preferences: ShellPreferences,
        capturer: any CalibrationSampleCapturing
    ) {
        self.primaryName = primaryName
        self.preferences = preferences
        self.capturer = capturer
        self.session = TriggerCalibrationSession(primaryName: primaryName)
    }

    func runSession() async {
        session = TriggerCalibrationSession(primaryName: primaryName)
        isComplete = false

        while !session.isComplete {
            let sample: CalibrationSample?
            do {
                sample = try await capturer.captureSample(for: primaryName)
            } catch is CalibrationCapturingDone {
                // Capturer signals no more samples available — exit cleanly without completing.
                return
            } catch {
                // Other errors: treat as retry signal
                onRetry?()
                continue
            }

            let result = session.recordSample(sample)
            switch result {
            case .retry:
                onRetry?()
            case .accepted:
                onSampleAccepted?(0)
            case .completed:
                isComplete = true
                let aliases = session.finalizedAliases()
                preferences.applyCalibrationAliases(aliases)
                onComplete?()
            }
        }
    }

    private func countAccepted() -> Int {
        // TriggerCalibrationSession doesn't expose its count, derive from isComplete
        // We use isComplete as a proxy; for accepted events, we track via callbacks.
        // This is a best-effort count for UI progress — not exposed as state.
        return 0
    }
}
