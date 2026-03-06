import Accelerate
import AVFoundation
import Combine

@MainActor
final class AudioLevelMonitor: ObservableObject {
    @Published private(set) var level: Float = 0.0

    nonisolated func process(buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let samples = buffer.floatChannelData?[0] else {
            Task { @MainActor in
                self.level = 0.0
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
        }
    }

    func reset() {
        level = 0.0
    }
}
