import AVFoundation
import XCTest
@testable import Speech2Text

final class VoiceActivityDetectorTests: XCTestCase {

    func makeBuffer(silence: Bool, frameCount: AVAudioFrameCount = 4410, sampleRate: Double = 44100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        if let data = buffer.floatChannelData?[0] {
            let amplitude: Float = silence ? 0.0001 : 0.5 // tiny amplitude vs large amplitude
            for i in 0..<Int(frameCount) {
                // simple wave
                data[i] = sin(Float(i) * 0.1) * amplitude
            }
        }
        return buffer
    }

    func testDetectorDropsContinuousSilence() {
        let accumulator = AudioBufferAccumulator()
        let vad = VoiceActivityDetector(destination: accumulator, silenceThresholdDB: -45.0, preRollDuration: 0.5, trailingSilenceDuration: 0.5)
        
        // 10 buffers of 0.1s silence each = 1.0s total silence
        for _ in 0..<10 {
            vad.append(makeBuffer(silence: true))
        }
        
        // Accumulator should be empty
        XCTAssertEqual(accumulator.totalFrameCount, 0)
    }

    func testDetectorEmitsSpeechAndPreRoll() {
        let accumulator = AudioBufferAccumulator()
        let vad = VoiceActivityDetector(destination: accumulator, silenceThresholdDB: -45.0, preRollDuration: 0.5, trailingSilenceDuration: 0.5)
        
        // Send 1.0s of silence (10 buffers of 0.1s)
        for _ in 0..<10 {
            vad.append(makeBuffer(silence: true))
        }
        
        // Pre-roll max is 0.5s, so we expect exactly 5 buffers to be preserved and emitted.
        
        // Send 1 buffer of speech (0.1s)
        vad.append(makeBuffer(silence: false))
        
        // Should emit 5 pre-roll buffers + 1 speech buffer = 6 buffers total
        // 6 * 4410 = 26460 frames
        XCTAssertEqual(accumulator.totalFrameCount, 26460)
    }

    func testDetectorMaintainsTrailingSilence() {
        let accumulator = AudioBufferAccumulator()
        var mockTime = Date(timeIntervalSince1970: 0)
        let vad = VoiceActivityDetector(
            destination: accumulator,
            silenceThresholdDB: -45.0,
            preRollDuration: 0.1,
            trailingSilenceDuration: 0.2,
            dateProvider: { mockTime }
        )
        
        // 1 buffer speech (0.1s)
        vad.append(makeBuffer(silence: false))
        
        // We have 1 buffer speech + 0 buffers pre-roll (since it was empty) = 1 buffer emitted
        XCTAssertEqual(accumulator.totalFrameCount, 4410)
        
        // Advance time by 0.1s (within trailing window)
        mockTime.addTimeInterval(0.1)
        vad.append(makeBuffer(silence: true))
        XCTAssertEqual(accumulator.totalFrameCount, 8820)
        
        // Advance time by 0.15s (total 0.25s since speech, exceeding 0.2s trailing window)
        mockTime.addTimeInterval(0.15)
        vad.append(makeBuffer(silence: true))
        
        // Accumulator should not have increased because trailing window expired
        XCTAssertEqual(accumulator.totalFrameCount, 8820)
    }
}
