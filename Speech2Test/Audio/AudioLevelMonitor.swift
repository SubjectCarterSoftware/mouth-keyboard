import Accelerate
import AVFoundation
import Combine

struct LongDictationBoundaryConfiguration: Equatable, Sendable {
    let activationThreshold: TimeInterval
    let pauseThreshold: TimeInterval
    let softCapDuration: TimeInterval

    static let v1 = LongDictationBoundaryConfiguration(
        activationThreshold: 30,
        pauseThreshold: 1.2,
        softCapDuration: 45
    )
}

struct LongDictationBoundaryTracker {
    private let configuration: LongDictationBoundaryConfiguration

    private(set) var totalDuration: TimeInterval = 0
    private(set) var currentSegmentDuration: TimeInterval = 0
    private(set) var isLongSessionActive = false
    private var currentSilenceDuration: TimeInterval = 0
    private var speechDetectedSinceLastBoundary = false

    init(configuration: LongDictationBoundaryConfiguration = .v1) {
        self.configuration = configuration
    }

    mutating func ingest(
        normalizedLevel: Float,
        frameDuration: TimeInterval,
        silenceThreshold: Float
    ) -> [LongDictationBoundaryEvent] {
        guard frameDuration > 0 else { return [] }

        totalDuration += frameDuration
        currentSegmentDuration += frameDuration

        if normalizedLevel < silenceThreshold {
            currentSilenceDuration += frameDuration
        } else {
            currentSilenceDuration = 0
            speechDetectedSinceLastBoundary = true
        }

        var events: [LongDictationBoundaryEvent] = []

        if !isLongSessionActive, totalDuration >= configuration.activationThreshold {
            isLongSessionActive = true
            events.append(.thresholdReached)
        }

        guard isLongSessionActive, speechDetectedSinceLastBoundary else {
            return events
        }

        if currentSilenceDuration >= configuration.pauseThreshold {
            events.append(.segmentBoundary(reason: .pause))
            resetCurrentSegment()
            return events
        }

        if currentSegmentDuration >= configuration.softCapDuration {
            events.append(.segmentBoundary(reason: .softCap))
            resetCurrentSegment()
        }

        return events
    }

    mutating func reset() {
        totalDuration = 0
        currentSegmentDuration = 0
        currentSilenceDuration = 0
        speechDetectedSinceLastBoundary = false
        isLongSessionActive = false
    }

    private mutating func resetCurrentSegment() {
        currentSegmentDuration = 0
        currentSilenceDuration = 0
        speechDetectedSinceLastBoundary = false
    }
}

@MainActor
final class AudioLevelMonitor: ObservableObject {
    @Published private(set) var level: Float = 0.0

    // MARK: - Silence detection

    var onSilenceWarning: (() -> Void)?
    var onSilenceTimeout: (() -> Void)?
    var onSegmentBoundary: ((LongDictationBoundaryEvent) -> Void)?

    private let silenceThreshold: Float = 0.01
    private var silenceStartTime: Date?
    private var hasFiredWarning = false
    private var hasFiredTimeout = false
    private var longDictationBoundaryTracker: LongDictationBoundaryTracker

    init(boundaryConfiguration: LongDictationBoundaryConfiguration = .v1) {
        longDictationBoundaryTracker = LongDictationBoundaryTracker(configuration: boundaryConfiguration)
    }

    // MARK: - Buffer processing

    nonisolated func process(buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        let frameDuration = buffer.format.sampleRate > 0
            ? Double(buffer.frameLength) / buffer.format.sampleRate
            : 0
        guard frameLength > 0, let samples = buffer.floatChannelData?[0] else {
            Task { @MainActor in
                self.level = 0.0
                self.updateSilenceTracking(normalized: 0.0)
                self.updateLongDictationTracking(normalized: 0.0, frameDuration: frameDuration)
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
            self.updateLongDictationTracking(normalized: normalized, frameDuration: frameDuration)
        }
    }

    private func updateSilenceTracking(normalized: Float) {
        if normalized < silenceThreshold {
            // Silent
            if silenceStartTime == nil {
                silenceStartTime = Date()
            }
            let elapsed = Date().timeIntervalSince(silenceStartTime!)
            if elapsed >= 45 && !hasFiredWarning {
                hasFiredWarning = true
                onSilenceWarning?()
            }
            if elapsed >= 60 && !hasFiredTimeout {
                hasFiredTimeout = true
                onSilenceTimeout?()
            }
        } else {
            // Sound detected — reset silence tracking
            silenceStartTime = nil
            hasFiredWarning = false
            hasFiredTimeout = false
        }
    }

    func reset() {
        level = 0.0
        silenceStartTime = nil
        hasFiredWarning = false
        hasFiredTimeout = false
        longDictationBoundaryTracker.reset()
    }

    private func updateLongDictationTracking(normalized: Float, frameDuration: TimeInterval) {
        let events = longDictationBoundaryTracker.ingest(
            normalizedLevel: normalized,
            frameDuration: frameDuration,
            silenceThreshold: silenceThreshold
        )

        for event in events {
            onSegmentBoundary?(event)
        }
    }
}
