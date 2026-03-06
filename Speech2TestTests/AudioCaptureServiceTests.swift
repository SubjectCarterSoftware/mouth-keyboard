import AVFoundation
import XCTest
@testable import Speech2Test

final class AudioCaptureServiceTests: XCTestCase {
    @MainActor
    func testStartInstallsTapWithoutOutputConnection() throws {
        let service = AudioCaptureService(engineStarter: { _ in }, checkAuthorization: { true })
        let levelMonitor = AudioLevelMonitor()

        try service.start(levelMonitor: levelMonitor)

        XCTAssertTrue(service.debugState.hasInstalledTap)
        XCTAssertEqual(service.debugState.outputConnectionPointCount, 0)
    }

    @MainActor
    func testStopRemovesTapAndSupportsRestart() throws {
        let service = AudioCaptureService(engineStarter: { _ in }, checkAuthorization: { true })

        try service.start(levelMonitor: AudioLevelMonitor())
        XCTAssertTrue(service.debugState.hasInstalledTap)

        service.stop()
        XCTAssertFalse(service.debugState.hasInstalledTap)

        try service.start(levelMonitor: AudioLevelMonitor())
        XCTAssertTrue(service.debugState.hasInstalledTap)
    }

    @MainActor
    func testAudioLevelMonitorStartsAtZero() {
        let monitor = AudioLevelMonitor()

        XCTAssertEqual(monitor.level, 0)
    }

    func testAudioLevelMonitorProcessesRMSLevel() async throws {
        let monitor = await MainActor.run { AudioLevelMonitor() }

        monitor.process(buffer: makeBuffer(sampleValue: 0.5))
        try await Task.sleep(nanoseconds: 100_000_000)

        let level = await MainActor.run { monitor.level }
        XCTAssertEqual(level, 0.5, accuracy: 0.01)
    }

    private func makeBuffer(sampleValue: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
        buffer.frameLength = 1_024

        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = sampleValue
        }

        return buffer
    }
}
