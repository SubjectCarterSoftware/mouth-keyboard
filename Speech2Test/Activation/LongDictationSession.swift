import AVFoundation
import Foundation

enum SegmentSealReason: String, Equatable, Sendable {
    case pause
    case softCap
    case finish
}

enum QueuedSegmentTranscriptionState: Equatable, Sendable {
    case pending
    case transcribing
    case completed(text: String)
    case failed(message: String)
}

struct SealedAudioSegment: Equatable, Sendable {
    static let whisperSampleRate = 16_000.0

    let samples: [Float]
    let sourceFrameCount: AVAudioFrameCount
    let sourceSampleRate: Double

    var durationSeconds: TimeInterval {
        guard sourceSampleRate > 0 else { return 0 }
        return Double(sourceFrameCount) / sourceSampleRate
    }
}

struct QueuedSegment: Equatable, Sendable {
    let index: Int
    let sealReason: SegmentSealReason
    let audio: SealedAudioSegment
    var transcriptionState: QueuedSegmentTranscriptionState = .pending
}

struct LongSessionStatus: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case inactive
        case recordingSegmented
        case finalizing
    }

    var phase: Phase
    var nextSegmentIndex: Int
    var queuedSegmentCount: Int
    var completedSegmentCount: Int
    var failedSegmentCount: Int

    static let inactive = LongSessionStatus(
        phase: .inactive,
        nextSegmentIndex: 0,
        queuedSegmentCount: 0,
        completedSegmentCount: 0,
        failedSegmentCount: 0
    )
}
