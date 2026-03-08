import AVFoundation
import XCTest
@testable import Speech2Test

final class AudioBufferAccumulatorTests: XCTestCase {

    func makeBuffer(samples: [Float], sampleRate: Double = 16000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let data = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                data[index] = sample
            }
        }
        return buffer
    }

    func makeBuffer(frameCount: AVAudioFrameCount, sampleRate: Double = 44100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        // Fill with a simple sine wave so conversion has valid data
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameCount) {
                data[i] = sin(Float(i) * 0.01)
            }
        }
        return buffer
    }

    func testAppendIncreasesTotalFrameCount() {
        let accumulator = AudioBufferAccumulator()
        let buffer = makeBuffer(frameCount: 1024)
        accumulator.append(buffer)
        XCTAssertEqual(accumulator.totalFrameCount, 1024)
    }

    func testMultipleAppendsAccumulate() {
        let accumulator = AudioBufferAccumulator()
        accumulator.append(makeBuffer(frameCount: 512))
        accumulator.append(makeBuffer(frameCount: 256))
        XCTAssertEqual(accumulator.totalFrameCount, 768)
    }

    func testResetClearsBuffers() {
        let accumulator = AudioBufferAccumulator()
        accumulator.append(makeBuffer(frameCount: 1024))
        accumulator.reset()
        XCTAssertEqual(accumulator.totalFrameCount, 0)
    }

    func testConvertToWhisperFormatThrowsOnEmptyBuffers() throws {
        let accumulator = AudioBufferAccumulator()
        XCTAssertThrowsError(try accumulator.convertToWhisperFormat())
    }

    func testConvertToWhisperFormatReturnsSamples() throws {
        let accumulator = AudioBufferAccumulator()
        // 44100 frames at 44100 Hz = 1 second
        // Should resample to 16000 samples at 16kHz
        let buffer = makeBuffer(frameCount: 44100, sampleRate: 44100)
        accumulator.append(buffer)
        let samples = try accumulator.convertToWhisperFormat()
        XCTAssertFalse(samples.isEmpty, "Should return non-empty samples after conversion")
        // Ratio: 16000/44100 ≈ 0.362, so approximately 16000 samples
        let expectedCount = 16000
        let tolerance = 500
        XCTAssertTrue(abs(samples.count - expectedCount) <= tolerance,
                      "Sample count \(samples.count) should be approximately \(expectedCount) (±\(tolerance))")
    }

    func testSealSegmentReturnsImmutablePayloadAfterMultipleAppends() throws {
        let accumulator = AudioBufferAccumulator()
        accumulator.append(makeBuffer(samples: [1, 2, 3]))
        accumulator.append(makeBuffer(samples: [4, 5]))

        let segment = try accumulator.sealSegment(index: 0, reason: .pause)

        XCTAssertEqual(segment.index, 0)
        XCTAssertEqual(segment.sealReason, .pause)
        XCTAssertEqual(segment.transcriptionState, .pending)
        XCTAssertEqual(segment.audio.sourceFrameCount, 5)
        XCTAssertEqual(segment.audio.samples, [1, 2, 3, 4, 5])
        XCTAssertEqual(accumulator.totalFrameCount, 0)
    }

    func testSealSegmentResetsLiveAccumulatorForSubsequentAppends() throws {
        let accumulator = AudioBufferAccumulator()
        accumulator.append(makeBuffer(samples: [1, 2]))

        _ = try accumulator.sealSegment(index: 0, reason: .softCap)
        accumulator.append(makeBuffer(samples: [7, 8, 9]))

        XCTAssertEqual(accumulator.totalFrameCount, 3)

        let nextSegment = try accumulator.sealSegment(index: 1, reason: .pause)
        XCTAssertEqual(nextSegment.audio.samples, [7, 8, 9])
    }

    func testConsecutiveSealsDoNotDuplicateOrLoseFramesAcrossSegments() throws {
        let accumulator = AudioBufferAccumulator()
        accumulator.append(makeBuffer(samples: [0.1, 0.2, 0.3]))
        accumulator.append(makeBuffer(samples: [0.4]))

        let firstSegment = try accumulator.sealSegment(index: 0, reason: .pause)

        accumulator.append(makeBuffer(samples: [0.9, 1.0]))
        let secondSegment = try accumulator.sealSegment(index: 1, reason: .softCap)

        XCTAssertEqual(firstSegment.audio.samples, [0.1, 0.2, 0.3, 0.4])
        XCTAssertEqual(secondSegment.audio.samples, [0.9, 1.0])
        XCTAssertEqual(
            firstSegment.audio.sourceFrameCount + secondSegment.audio.sourceFrameCount,
            6
        )
    }
}
