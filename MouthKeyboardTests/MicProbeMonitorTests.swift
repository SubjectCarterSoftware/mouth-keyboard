import AVFoundation
import XCTest
@testable import TypeLessBuddy

final class MicProbeMonitorTests: XCTestCase {

    private func makeBuffer(
        amplitude: Float,
        frameCount: AVAudioFrameCount = 1024,
        sampleRate: Double = 44100
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameCount) {
                data[i] = sin(Float(i) * 0.1) * amplitude
            }
        }
        return buffer
    }

    func testZeroSignalBuffersProducesDeadVerdict() {
        var mockTime = Date(timeIntervalSince1970: 0)
        let monitor = MicProbeMonitor(
            deadThreshold: 1e-7,
            probeDuration: 0.4,
            dateProvider: { mockTime }
        )

        for _ in 0..<10 {
            monitor.process(buffer: makeBuffer(amplitude: 0))
            mockTime.addTimeInterval(0.05)
        }

        XCTAssertEqual(monitor.verdict, .dead)
    }

    func testNonZeroSignalProducesAliveVerdict() {
        let monitor = MicProbeMonitor(
            deadThreshold: 1e-7,
            probeDuration: 0.4,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        )

        monitor.process(buffer: makeBuffer(amplitude: 0.01))

        XCTAssertEqual(monitor.verdict, .alive)
    }

    func testMixedBuffersZeroThenSignalProducesAlive() {
        var mockTime = Date(timeIntervalSince1970: 0)
        let monitor = MicProbeMonitor(
            deadThreshold: 1e-7,
            probeDuration: 0.4,
            dateProvider: { mockTime }
        )

        for _ in 0..<5 {
            monitor.process(buffer: makeBuffer(amplitude: 0))
            mockTime.addTimeInterval(0.02)
        }
        XCTAssertEqual(monitor.verdict, .pending)

        monitor.process(buffer: makeBuffer(amplitude: 0.001))
        XCTAssertEqual(monitor.verdict, .alive)
    }

    func testVerdictStaysPendingBeforeProbeDurationElapses() {
        var mockTime = Date(timeIntervalSince1970: 0)
        let monitor = MicProbeMonitor(
            deadThreshold: 1e-7,
            probeDuration: 0.4,
            dateProvider: { mockTime }
        )

        for _ in 0..<5 {
            monitor.process(buffer: makeBuffer(amplitude: 0))
            mockTime.addTimeInterval(0.05)
        }

        XCTAssertEqual(monitor.verdict, .pending)
    }

    func testProcessingStopsAfterAliveVerdict() {
        var mockTime = Date(timeIntervalSince1970: 0)
        let monitor = MicProbeMonitor(
            deadThreshold: 1e-7,
            probeDuration: 0.4,
            dateProvider: { mockTime }
        )

        monitor.process(buffer: makeBuffer(amplitude: 0.5))
        XCTAssertEqual(monitor.verdict, .alive)

        mockTime.addTimeInterval(1.0)
        monitor.process(buffer: makeBuffer(amplitude: 0))
        XCTAssertEqual(monitor.verdict, .alive)
    }

    func testProcessingStopsAfterDeadVerdict() {
        var mockTime = Date(timeIntervalSince1970: 0)
        let monitor = MicProbeMonitor(
            deadThreshold: 1e-7,
            probeDuration: 0.4,
            dateProvider: { mockTime }
        )

        for _ in 0..<20 {
            monitor.process(buffer: makeBuffer(amplitude: 0))
            mockTime.addTimeInterval(0.05)
        }
        XCTAssertEqual(monitor.verdict, .dead)

        monitor.process(buffer: makeBuffer(amplitude: 0.5))
        XCTAssertEqual(monitor.verdict, .dead)
    }

    func testResetClearsState() {
        var mockTime = Date(timeIntervalSince1970: 0)
        let monitor = MicProbeMonitor(
            deadThreshold: 1e-7,
            probeDuration: 0.4,
            dateProvider: { mockTime }
        )

        monitor.process(buffer: makeBuffer(amplitude: 0.5))
        XCTAssertEqual(monitor.verdict, .alive)

        monitor.reset()
        XCTAssertEqual(monitor.verdict, .pending)

        for _ in 0..<20 {
            monitor.process(buffer: makeBuffer(amplitude: 0))
            mockTime.addTimeInterval(0.05)
        }
        XCTAssertEqual(monitor.verdict, .dead)
    }
}
