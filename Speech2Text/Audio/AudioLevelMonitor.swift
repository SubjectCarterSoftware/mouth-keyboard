import Accelerate
import AVFoundation
import Combine

@MainActor
final class AudioLevelMonitor: ObservableObject {
    @Published private(set) var level: Float = 0.0
    @Published private(set) var silenceWarningActive = false

    // MARK: - Silence detection

    var onSilenceTimeout: (() -> Void)?

    private let silenceThreshold: Float = 0.01
    private var silenceStartTime: Date?
    private var hasFiredTimeout = false
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    // MARK: - Buffer processing

    nonisolated func process(buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let samples = buffer.floatChannelData?[0] else {
            Task { @MainActor in
                self.level = 0.0
                self.updateSilenceTracking(normalized: 0.0)
            }
            return
        }

        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))

        // Convert to dB, then map to 0–1 range.
        let minDB: Float = -80
        let maxDB: Float = -10
        let db = rms > 0 ? 20 * log10(rms) : minDB
        let normalized = max(0, min(1, (db - minDB) / (maxDB - minDB)))

        Task { @MainActor in
            self.level = normalized
            self.updateSilenceTracking(normalized: normalized)
        }
    }

    private func updateSilenceTracking(normalized: Float) {
        let currentTime = now()
        if normalized < silenceThreshold {
            // Silent
            if silenceStartTime == nil {
                silenceStartTime = currentTime
            }
            let elapsed = currentTime.timeIntervalSince(silenceStartTime!)
            if elapsed >= 45 {
                silenceWarningActive = true
            }
            if elapsed >= 60 && !hasFiredTimeout {
                hasFiredTimeout = true
                onSilenceTimeout?()
            }
        } else {
            // Sound detected — reset silence tracking
            silenceStartTime = nil
            silenceWarningActive = false
            hasFiredTimeout = false
        }
    }

    func reset() {
        level = 0.0
        silenceStartTime = nil
        hasFiredTimeout = false
        silenceWarningActive = false
    }
}
