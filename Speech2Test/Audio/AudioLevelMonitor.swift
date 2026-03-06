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
        let clampedLevel = max(0, min(rms, 1))

        Task { @MainActor in
            self.level = clampedLevel
        }
    }

    func reset() {
        level = 0.0
    }
}
