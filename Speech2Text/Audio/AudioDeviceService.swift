import AudioToolbox
import AVFoundation
import Combine
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

@MainActor
final class AudioDeviceService: ObservableObject {
    typealias DeviceEnumerator = () -> [AudioInputDevice]
    typealias AudioUnitSetter = (AudioUnit, AudioDeviceID) -> OSStatus

    static let shared = AudioDeviceService()

    @Published private(set) var availableDevices: [AudioInputDevice] = []

    private static let listenerQueue = DispatchQueue.main

    private let deviceEnumerator: DeviceEnumerator
    private let audioUnitSetter: AudioUnitSetter
    private var disconnectListener: DisconnectListener?

    init(
        deviceEnumerator: @escaping DeviceEnumerator = AudioDeviceService.enumerateInputDevices,
        audioUnitSetter: @escaping AudioUnitSetter = AudioDeviceService.defaultAudioUnitSetter
    ) {
        self.deviceEnumerator = deviceEnumerator
        self.audioUnitSetter = audioUnitSetter
    }

    func refresh() {
        availableDevices = deviceEnumerator()
    }

    func device(forUID uid: String) -> AudioInputDevice? {
        if let availableDevice = availableDevices.first(where: { $0.uid == uid }) {
            return availableDevice
        }

        return deviceEnumerator().first(where: { $0.uid == uid })
    }

    func setInputDevice(_ device: AudioInputDevice?, on engine: AVAudioEngine) throws {
        guard let device else {
            return
        }

        guard let audioUnit = engine.inputNode.audioUnit else {
            throw NSError(
                domain: "AudioDeviceService",
                code: Int(kAudioHardwareIllegalOperationError),
                userInfo: [NSLocalizedDescriptionKey: "The AVAudioEngine input node does not expose an AudioUnit yet."]
            )
        }

        let status = audioUnitSetter(audioUnit, device.id)
        guard status == noErr else {
            throw NSError(
                domain: "AudioDeviceService",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to switch to \(device.name) (\(status))."]
            )
        }
    }

    func registerDisconnectListener(for deviceUID: String, onDisconnect: @escaping () -> Void) {
        unregisterDisconnectListener()

        guard let deviceID = Self.deviceID(forUID: deviceUID) else {
            return
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard !Self.isDeviceAlive(deviceID) else {
                return
            }

            Task { @MainActor in
                onDisconnect()
                self?.unregisterDisconnectListener()
            }
        }

        var address = Self.deviceAliveAddress
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, Self.listenerQueue, block)
        guard status == noErr else {
            NSLog("AudioDeviceService failed to register disconnect listener for device \(deviceUID): \(status)")
            return
        }

        disconnectListener = DisconnectListener(deviceID: deviceID, block: block)
    }

    func unregisterDisconnectListener() {
        guard let disconnectListener else {
            return
        }

        var address = Self.deviceAliveAddress
        let status = AudioObjectRemovePropertyListenerBlock(
            disconnectListener.deviceID,
            &address,
            Self.listenerQueue,
            disconnectListener.block
        )
        if status != noErr {
            NSLog("AudioDeviceService failed to remove disconnect listener: \(status)")
        }

        self.disconnectListener = nil
    }

    private struct DisconnectListener {
        let deviceID: AudioDeviceID
        let block: AudioObjectPropertyListenerBlock
    }

    private static var systemDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var deviceAliveAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func enumerateInputDevices() -> [AudioInputDevice] {
        readDeviceIDs()
            .compactMap { deviceID in
                guard hasInputStreams(deviceID) else {
                    return nil
                }

                guard
                    let name = stringProperty(
                        selector: kAudioObjectPropertyName,
                        on: deviceID,
                        scope: kAudioObjectPropertyScopeGlobal
                    ),
                    let uid = stringProperty(
                        selector: kAudioDevicePropertyDeviceUID,
                        on: deviceID,
                        scope: kAudioObjectPropertyScopeGlobal
                    ),
                    !uid.isEmpty
                else {
                    return nil
                }

                return AudioInputDevice(id: deviceID, name: name, uid: uid)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func readDeviceIDs() -> [AudioDeviceID] {
        var address = systemDeviceAddress
        var dataSize: UInt32 = 0
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        var deviceIDs = Array(repeating: AudioDeviceID(), count: deviceCount)

        guard AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return false
        }

        return dataSize / UInt32(MemoryLayout<AudioStreamID>.stride) > 0
    }

    private static func stringProperty(
        selector: AudioObjectPropertySelector,
        on deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var cfString: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.stride)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &cfString) == noErr else {
            return nil
        }

        return cfString as String
    }

    private static func defaultAudioUnitSetter(_ audioUnit: AudioUnit, _ deviceID: AudioDeviceID) -> OSStatus {
        var mutableDeviceID = deviceID
        return AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.stride)
        )
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        enumerateInputDevices().first(where: { $0.uid == uid })?.id
    }

    private static func isDeviceAlive(_ deviceID: AudioDeviceID) -> Bool {
        var address = deviceAliveAddress
        var isAlive: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.stride)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isAlive) == noErr else {
            return false
        }

        return isAlive != 0
    }
}
