import AVFoundation
import XCTest
@testable import TypeLessBuddy

final class AudioBufferAccumulatorTests: XCTestCase {
    private let windowSampleCount = 1_600

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

    func testAppendStopsAddingBuffersAfterOverflow() {
        let accumulator = AudioBufferAccumulator(maxDuration: 0.001)
        let buffer = makeBuffer(frameCount: 16, sampleRate: 16_000)

        accumulator.append(buffer)
        XCTAssertEqual(accumulator.totalFrameCount, 16)

        accumulator.append(buffer)
        XCTAssertEqual(accumulator.totalFrameCount, 16, "Overflow should block additional frames from being stored")
    }

    func testConvertThrowsOverflowAfterCap() throws {
        let accumulator = AudioBufferAccumulator(maxDuration: 0.001)
        let buffer = makeBuffer(frameCount: 16, sampleRate: 16_000)
        accumulator.append(buffer)
        accumulator.append(buffer)

        XCTAssertThrowsError(try accumulator.convertToWhisperFormat()) { error in
            guard case AudioBufferAccumulatorError.overflow = error else {
                return XCTFail("Expected overflow error, got \(error)")
            }
        }
    }

    func testPrepareForTranscriptionAddsTrailingSilenceAndMinimumDurationPadding() {
        let original: [Float] = [0.25, -0.5, 0.75, -1.0]

        let prepared = AudioBufferAccumulator.prepareForTranscription(
            original,
            minimumDuration: 0.001,
            trailingSilenceDuration: 0.0005
        )

        XCTAssertEqual(prepared.count, 16)
        XCTAssertEqual(Array(prepared.prefix(original.count)), original)
        XCTAssertTrue(prepared.dropFirst(original.count).allSatisfy { $0 == 0 })
    }

    func testPrepareForTranscriptionTrimsLeadingSilenceAndKeepsPreroll() {
        let prepared = AudioBufferAccumulator.prepareForTranscription(
            repeating(0, count: 5)
                + repeating(0.02, count: 1),
            minimumDuration: 0,
            trailingSilenceDuration: 0
        )

        XCTAssertEqual(prepared.count, windowSampleCount * 4)
        XCTAssertTrue(Array(prepared.prefix(windowSampleCount * 3)).allSatisfy { $0 == 0 })
        XCTAssertTrue(Array(prepared.suffix(windowSampleCount)).allSatisfy { $0 == 0.02 })
    }

    func testPrepareForTranscriptionTrimsTrailingSilence() {
        let prepared = AudioBufferAccumulator.prepareForTranscription(
            repeating(0.02, count: 1)
                + repeating(0, count: 5),
            minimumDuration: 0,
            trailingSilenceDuration: 0
        )

        XCTAssertEqual(prepared.count, windowSampleCount)
        XCTAssertTrue(prepared.allSatisfy { $0 == 0.02 })
    }

    func testPrepareForTranscriptionPreservesMiddleSilence() {
        let prepared = AudioBufferAccumulator.prepareForTranscription(
            repeating(0, count: 5)
                + repeating(0.02, count: 1)
                + repeating(0, count: 4)
                + repeating(0.02, count: 1)
                + repeating(0, count: 5),
            minimumDuration: 0,
            trailingSilenceDuration: 0
        )

        XCTAssertEqual(prepared.count, windowSampleCount * 9)
        XCTAssertTrue(Array(prepared.prefix(windowSampleCount * 3)).allSatisfy { $0 == 0 })
        XCTAssertTrue(Array(prepared[(windowSampleCount * 4)..<(windowSampleCount * 8)]).allSatisfy { $0 == 0 })
        XCTAssertTrue(Array(prepared.suffix(windowSampleCount)).allSatisfy { $0 == 0.02 })
    }

    func testPrepareForTranscriptionLeavesFullySilentInputUnchangedBeforePadding() {
        let silent = repeating(0, count: 4)
        let prepared = AudioBufferAccumulator.prepareForTranscription(
            silent,
            minimumDuration: 0,
            trailingSilenceDuration: 0
        )

        XCTAssertEqual(prepared, silent)
    }

    func testPrepareForTranscriptionPadsVeryShortSpokenInputToMinimumDuration() {
        let prepared = AudioBufferAccumulator.prepareForTranscription(
            repeating(0.02, count: 1),
            minimumDuration: 1,
            trailingSilenceDuration: 0
        )

        XCTAssertEqual(prepared.count, 16_000)
        XCTAssertTrue(Array(prepared.prefix(windowSampleCount)).allSatisfy { $0 == 0.02 })
        XCTAssertTrue(prepared.dropFirst(windowSampleCount).allSatisfy { $0 == 0 })
    }

    func testPrepareForTranscriptionPreservesSpeechWithoutTrailingSilence() {
        let original = repeating(0, count: 2) + repeating(0.02, count: 2)
        let prepared = AudioBufferAccumulator.prepareForTranscription(
            original,
            minimumDuration: 0,
            trailingSilenceDuration: 0
        )

        XCTAssertEqual(prepared.count, windowSampleCount * 4)
        XCTAssertEqual(prepared, original)
    }

    private func repeating(_ sample: Float, count windows: Int) -> [Float] {
        Array(repeating: sample, count: windows * windowSampleCount)
    }
}
