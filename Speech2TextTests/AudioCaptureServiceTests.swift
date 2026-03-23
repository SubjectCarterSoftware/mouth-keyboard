import AVFoundation
import XCTest
@testable import Speech2Text

final class AudioCaptureServiceTests: XCTestCase {
    @MainActor
    func testDeniedMicrophoneAuthorizationThrowsTypedError() {
        let service = AudioCaptureService(
            engineStarter: { _ in },
            authorizationStatusProvider: { .denied },
            hasDefaultInputDeviceProvider: { true }
        )

        XCTAssertThrowsError(try service.start(levelMonitor: AudioLevelMonitor())) { error in
            guard case AudioCaptureError.microphonePermissionDenied = error else {
                return XCTFail("Expected microphonePermissionDenied, got \(error)")
            }
        }
    }

    @MainActor
    func testMissingSelectedDeviceFallsBackToSystemDefaultAndPreservesStoredUID() throws {
        let preferences = makePreferences()
        preferences.micDeviceUID = "missing-device"
        let defaultDevice = AudioInputDevice(id: 7, name: "MacBook Pro Microphone", uid: "built-in-mic")
        var appliedDeviceIDs: [AudioDeviceID] = []
        let audioDeviceService = AudioDeviceService(
            deviceEnumerator: { [] },
            defaultInputDeviceResolver: { defaultDevice },
            audioUnitSetter: { _, deviceID in
                appliedDeviceIDs.append(deviceID)
                return noErr
            }
        )
        let service = AudioCaptureService(
            preferences: preferences,
            audioDeviceService: audioDeviceService,
            engineStarter: { _ in },
            authorizationStatusProvider: { .authorized },
            hasDefaultInputDeviceProvider: { true }
        )

        try service.start(levelMonitor: AudioLevelMonitor())

        XCTAssertEqual(preferences.micDeviceUID, "missing-device")
        XCTAssertEqual(appliedDeviceIDs, [defaultDevice.id])
    }

    @MainActor
    func testStartInstallsTapWithoutOutputConnection() throws {
        let service = AudioCaptureService(
            preferences: makePreferences(),
            engineStarter: { _ in },
            authorizationStatusProvider: { .authorized }
        )
        let levelMonitor = AudioLevelMonitor()

        try service.start(levelMonitor: levelMonitor)

        XCTAssertTrue(service.debugState.hasInstalledTap)
        XCTAssertEqual(service.debugState.outputConnectionPointCount, 0)
    }

    @MainActor
    func testStopRemovesTapAndSupportsRestart() throws {
        let service = AudioCaptureService(
            preferences: makePreferences(),
            engineStarter: { _ in },
            authorizationStatusProvider: { .authorized }
        )

        try service.start(levelMonitor: AudioLevelMonitor())
        XCTAssertTrue(service.debugState.hasInstalledTap)

        service.stop()
        XCTAssertFalse(service.debugState.hasInstalledTap)

        try service.start(levelMonitor: AudioLevelMonitor())
        XCTAssertTrue(service.debugState.hasInstalledTap)
    }

    @MainActor
    func testStartThrowsWhenCaptureAlreadyActive() throws {
        let service = AudioCaptureService(
            preferences: makePreferences(),
            engineStarter: { _ in },
            authorizationStatusProvider: { .authorized }
        )
        try service.start(levelMonitor: AudioLevelMonitor())

        XCTAssertThrowsError(try service.start(levelMonitor: AudioLevelMonitor())) { error in
            guard case AudioCaptureError.captureBusy = error else {
                return XCTFail("Expected captureBusy, got \(error)")
            }
        }
    }

    @MainActor
    func testSelectedDeviceDisconnectReportsTypedFailureInsteadOfFallback() throws {
        let preferences = makePreferences()
        preferences.micDeviceUID = "usb-mic"
        let device = AudioInputDevice(id: 1, name: "USB Mic", uid: "usb-mic")
        let audioDeviceService = AudioDeviceService(
            deviceEnumerator: { [device] },
            audioUnitSetter: { _, _ in noErr }
        )
        let service = AudioCaptureService(
            preferences: preferences,
            audioDeviceService: audioDeviceService,
            engineStarter: { _ in },
            authorizationStatusProvider: { .authorized },
            hasDefaultInputDeviceProvider: { true }
        )
        let levelMonitor = AudioLevelMonitor()
        var reportedError: AudioCaptureError?
        service.onCaptureFailure = { error in
            reportedError = error
        }

        try service.start(levelMonitor: levelMonitor)
        XCTAssertTrue(service.debugState.hasInstalledTap)

        service.simulateSelectedDeviceDisconnectForTesting()

        XCTAssertFalse(service.debugState.hasInstalledTap)
        XCTAssertEqual(preferences.micDeviceUID, "usb-mic")
        guard case AudioCaptureError.selectedInputDisconnected? = reportedError else {
            return XCTFail("Expected selectedInputDisconnected, got \(String(describing: reportedError))")
        }
    }

    @MainActor
    func testSystemDefaultIsUsedWhenNoPreferredDeviceIsSelected() throws {
        let defaultDevice = AudioInputDevice(id: 3, name: "MacBook Pro Microphone", uid: "built-in-mic")
        var appliedDeviceIDs: [AudioDeviceID] = []
        let service = AudioCaptureService(
            preferences: makePreferences(),
            audioDeviceService: AudioDeviceService(
                deviceEnumerator: { [defaultDevice] },
                defaultInputDeviceResolver: { defaultDevice },
                audioUnitSetter: { _, deviceID in
                    appliedDeviceIDs.append(deviceID)
                    return noErr
                }
            ),
            engineStarter: { _ in },
            authorizationStatusProvider: { .authorized },
            hasDefaultInputDeviceProvider: { true }
        )

        try service.start(levelMonitor: AudioLevelMonitor())

        XCTAssertEqual(appliedDeviceIDs, [defaultDevice.id])
    }

    @MainActor
    func testPreferredDeviceWinsOverSystemDefaultWhenAvailable() throws {
        let preferences = makePreferences()
        preferences.micDeviceUID = "usb-mic"
        let preferredDevice = AudioInputDevice(id: 1, name: "USB Mic", uid: "usb-mic")
        let defaultDevice = AudioInputDevice(id: 3, name: "MacBook Pro Microphone", uid: "built-in-mic")
        var appliedDeviceIDs: [AudioDeviceID] = []
        let service = AudioCaptureService(
            preferences: preferences,
            audioDeviceService: AudioDeviceService(
                deviceEnumerator: { [preferredDevice, defaultDevice] },
                defaultInputDeviceResolver: { defaultDevice },
                audioUnitSetter: { _, deviceID in
                    appliedDeviceIDs.append(deviceID)
                    return noErr
                }
            ),
            engineStarter: { _ in },
            authorizationStatusProvider: { .authorized },
            hasDefaultInputDeviceProvider: { true }
        )

        try service.start(levelMonitor: AudioLevelMonitor())

        XCTAssertEqual(appliedDeviceIDs, [preferredDevice.id])
    }

    @MainActor
    func testServiceThrowsUnavailableWhenNoPreferredOrSystemDefaultDeviceExists() throws {
        let preferences = makePreferences()
        preferences.micDeviceUID = "missing-device"
        let audioDeviceService = AudioDeviceService(
            deviceEnumerator: { [] },
            defaultInputDeviceResolver: { nil },
            audioUnitSetter: { _, _ in noErr }
        )
        let service = AudioCaptureService(
            preferences: preferences,
            audioDeviceService: audioDeviceService,
            engineStarter: { _ in },
            authorizationStatusProvider: { .authorized },
            hasDefaultInputDeviceProvider: { false }
        )

        XCTAssertThrowsError(try service.start(levelMonitor: AudioLevelMonitor())) { error in
            guard case AudioCaptureError.noUsableInputDevice = error else {
                return XCTFail("Expected noUsableInputDevice, got \(error)")
            }
        }
    }

    @MainActor
    func testAudioLevelMonitorStartsAtZero() {
        let monitor = AudioLevelMonitor()

        XCTAssertEqual(monitor.level, 0)
    }

    func testAudioLevelMonitorProcessesRMSLevel() async throws {
        let monitor = await MainActor.run { AudioLevelMonitor() }

        // -45 dB sits at the midpoint of the monitor's -80...-10 dB normalization window.
        monitor.process(buffer: makeBuffer(sampleValue: 0.005623413))
        try await Task.sleep(nanoseconds: 100_000_000)

        let level = await MainActor.run { monitor.level }
        XCTAssertEqual(level, 0.5, accuracy: 0.01)
    }

    func testSilenceWarningFlagActivatesAndClears() async throws {
        var currentTime = Date()
        let monitor = await MainActor.run {
            AudioLevelMonitor(now: { currentTime })
        }

        let silentBuffer = makeBuffer(sampleValue: 0.0)
        monitor.process(buffer: silentBuffer)
        try await Task.sleep(nanoseconds: 20_000_000)

        currentTime = currentTime.addingTimeInterval(46)
        monitor.process(buffer: silentBuffer)
        try await Task.sleep(nanoseconds: 20_000_000)

        let warningActive = await MainActor.run { monitor.silenceWarningActive }
        XCTAssertTrue(warningActive)

        let loudBuffer = makeBuffer(sampleValue: 0.2)
        monitor.process(buffer: loudBuffer)
        try await Task.sleep(nanoseconds: 20_000_000)

        let warningCleared = await MainActor.run { monitor.silenceWarningActive }
        XCTAssertFalse(warningCleared)
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

    @MainActor
    private func makePreferences() -> ShellPreferences {
        let suiteName = "AudioCaptureServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return ShellPreferences(userDefaults: defaults)
    }
}
