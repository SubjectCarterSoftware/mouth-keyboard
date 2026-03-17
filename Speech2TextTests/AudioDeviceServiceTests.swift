import AVFoundation
import XCTest
@testable import Speech2Text

@MainActor
final class AudioDeviceServiceTests: XCTestCase {
    func testAudioInputDeviceUsesAudioDeviceIDAsIdentifier() {
        let deviceID: AudioDeviceID = 42
        let device = AudioInputDevice(id: deviceID, name: "USB Microphone", uid: "usb-mic")

        XCTAssertEqual(device.id, deviceID)
    }

    func testSetInputDeviceWithNilDoesNotCallAudioUnitSetter() throws {
        var setterCallCount = 0
        let service = AudioDeviceService(
            deviceEnumerator: { [] },
            audioUnitSetter: { _, _ in
                setterCallCount += 1
                return noErr
            }
        )

        try service.setInputDevice(nil, on: AVAudioEngine())

        XCTAssertEqual(setterCallCount, 0)
    }

    func testRefreshReturnsRealInputDevicesWithoutSystemDefaultSentinel() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil)

        let service = AudioDeviceService()
        service.refresh()

        guard !service.availableDevices.isEmpty else {
            throw XCTSkip("No input devices available on this machine.")
        }

        XCTAssertFalse(service.availableDevices.contains(where: { $0.uid.isEmpty }))
        XCTAssertFalse(service.availableDevices.contains(where: { $0.name == "System Default" }))
    }

    func testCurrentDefaultInputDeviceUsesInjectedResolver() {
        let defaultDevice = AudioInputDevice(id: 11, name: "MacBook Pro Microphone", uid: "built-in-mic")
        let service = AudioDeviceService(
            deviceEnumerator: { [] },
            defaultInputDeviceResolver: { defaultDevice },
            audioUnitSetter: { _, _ in noErr }
        )

        XCTAssertEqual(service.currentDefaultInputDevice(), defaultDevice)
    }
}
