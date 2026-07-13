import Accelerate
import AVFoundation
import Combine

@MainActor
final class AudioLevelMonitor: ObservableObject {
    @Published private(set) var level: Float = 0.0
    @Published private(set) var displayLevel: Float = 0.0
    @Published private(set) var silenceWarningActive = false

    // MARK: - Silence detection

    var onSilenceTimeout: (() -> Void)?

    private let silenceThreshold: Float = 0.01
    private var silenceStartTime: Date?
    private var hasFiredTimeout = false
    private let now: () -> Date

    // MARK: - Display gating
    //
    // The raw `level` maps the full -80…-10 dB window, so quiet room noise
    // still lands well above zero and keeps the waveform visibly moving even
    // when nothing would be transcribed. `displayLevel` tracks the ambient
    // noise floor and gates against it: audio near the floor renders as 0 (a
    // flat, resting meter) and only speech-level energy clears the gate.

    /// Gate opens this far above the tracked noise floor (~5.6 dB).
    private static let gateMargin: Float = 0.08
    /// Gate never drops below this (~-62.5 dB), so digital silence after a
    /// muted mic doesn't leave the gate wide open.
    private static let minimumGate: Float = 0.25
    /// Gate never rises above this (~-38 dB), so speech stays visible even in
    /// a loud room.
    private static let maximumGate: Float = 0.60
    /// Normalized span from the gate to a fully extended meter (~28 dB).
    private static let speechSpan: Float = 0.40
    /// Per-buffer upward drift toward louder levels; keeps sustained speech
    /// from being absorbed into the floor while pauses re-anchor it instantly.
    private static let floorRiseRate: Float = 0.001
    /// Release half-life for the displayed level: attack is instant, but a
    /// drop decays exponentially so inter-word dips and the end of a phrase
    /// read as a graceful fall instead of a snap to flat.
    private static let releaseHalfLife: TimeInterval = 0.10

    private var noiseFloor: Float = 1.0
    private var lastDisplayUpdate: Date?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    // MARK: - Buffer processing

    nonisolated func process(buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let samples = buffer.floatChannelData?[0] else {
            Task { @MainActor in
                self.level = 0.0
                self.displayLevel = 0.0
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
            self.displayLevel = self.gatedDisplayLevel(for: normalized)
            self.updateSilenceTracking(normalized: normalized)
        }
    }

    private func gatedDisplayLevel(for normalized: Float) -> Float {
        if normalized < noiseFloor {
            noiseFloor = normalized
        } else {
            noiseFloor += (normalized - noiseFloor) * Self.floorRiseRate
        }

        let gate = min(max(noiseFloor + Self.gateMargin, Self.minimumGate), Self.maximumGate)
        let position = (normalized - gate) / Self.speechSpan
        let clamped = max(0, min(position, 1))
        // Smoothstep: soft knee near the gate so borderline noise reads as a
        // flicker instead of a full bar, while speech ramps quickly to full.
        let target = clamped * clamped * (3 - 2 * clamped)

        let currentTime = now()
        defer { lastDisplayUpdate = currentTime }
        guard target < displayLevel, let lastUpdate = lastDisplayUpdate else {
            return target
        }
        let elapsed = max(0, currentTime.timeIntervalSince(lastUpdate))
        let remaining = Float(pow(0.5, elapsed / Self.releaseHalfLife))
        let decayed = target + ((displayLevel - target) * remaining)
        return decayed - target < 0.005 ? target : decayed
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
        displayLevel = 0.0
        noiseFloor = 1.0
        lastDisplayUpdate = nil
        silenceStartTime = nil
        hasFiredTimeout = false
        silenceWarningActive = false
    }
}
