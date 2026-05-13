import Accelerate
import AVFoundation
import Foundation

final class MicProbeMonitor {
    enum Verdict: Equatable {
        case alive
        case dead
        case pending
    }

    private let deadThreshold: Float
    private let probeDuration: TimeInterval
    private let dateProvider: () -> Date
    private let lock = NSLock()

    private var maxRMS: Float = 0
    private var probeStartTime: Date?
    private var _verdict: Verdict = .pending

    var verdict: Verdict {
        lock.lock()
        defer { lock.unlock() }
        return _verdict
    }

    init(
        deadThreshold: Float = 1e-7,
        probeDuration: TimeInterval = 0.4,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.deadThreshold = deadThreshold
        self.probeDuration = probeDuration
        self.dateProvider = dateProvider
    }

    nonisolated func process(buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard _verdict == .pending else { return }

        let now = dateProvider()
        if probeStartTime == nil {
            probeStartTime = now
        }

        let frameLength = Int(buffer.frameLength)
        if frameLength > 0, let samples = buffer.floatChannelData?[0] {
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))
            if rms > maxRMS {
                maxRMS = rms
            }
        }

        if maxRMS >= deadThreshold {
            _verdict = .alive
            return
        }

        if let start = probeStartTime, now.timeIntervalSince(start) >= probeDuration {
            _verdict = .dead
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        maxRMS = 0
        probeStartTime = nil
        _verdict = .pending
    }
}
