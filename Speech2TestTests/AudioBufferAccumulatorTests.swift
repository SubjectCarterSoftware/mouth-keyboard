import AVFoundation
import XCTest
@testable import Speech2Test

final class AudioBufferAccumulatorTests: XCTestCase {

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
}
