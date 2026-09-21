import AudioToolbox
import CoreAudio
import Foundation

/// Halves the default output device's volume while the microphone is
/// recording — so playback (music in the same headset, for example) pollutes
/// the capture less — and restores the previous volume once recording ends.
///
/// The pre-duck volume is persisted while ducked so a crash or force-quit
/// mid-recording can be repaired on the next launch. Restoration is skipped
/// when the user adjusted the volume themselves during the recording.
@MainActor
final class SystemAudioDuckingService {
    struct OutputDevice: Equatable {
        let id: AudioDeviceID
        let uid: String
    }

    struct Snapshot: Equatable {
        let deviceUID: String
        let preDuckVolume: Float32
        let appliedDuckedVolume: Float32
    }

    typealias DefaultOutputDeviceResolver = @MainActor () -> OutputDevice?
    typealias DeviceForUIDResolver = @MainActor (String) -> AudioDeviceID?
    typealias VolumeReader = @MainActor (AudioDeviceID) -> Float32?
    typealias VolumeWriter = @MainActor (AudioDeviceID, Float32) -> Bool

    static let shared = SystemAudioDuckingService()
    static let duckFactor: Float32 = 0.5

    /// Bluetooth devices quantize volume steps, so the read-back ducked value
    /// can differ slightly from what was written. Restores compare against the
    /// read-back value within this tolerance; a larger deviation means the
    /// user changed the volume mid-recording and their choice wins.
    private static let volumeMatchTolerance: Float32 = 0.04

    private enum SnapshotKeys {
        static let deviceUID = "duckingSnapshotDeviceUID"
        static let preDuckVolume = "duckingSnapshotPreDuckVolume"
        static let appliedDuckedVolume = "duckingSnapshotAppliedVolume"
    }

    private let defaults: UserDefaults
    private let defaultOutputDeviceResolver: DefaultOutputDeviceResolver
    private let deviceForUIDResolver: DeviceForUIDResolver
    private let volumeReader: VolumeReader
    private let volumeWriter: VolumeWriter
    private var activeSnapshot: Snapshot?

    init(
        userDefaults: UserDefaults = UserDefaults(suiteName: ShellPreferences.Keys.suiteName) ?? .standard,
        defaultOutputDeviceResolver: @escaping DefaultOutputDeviceResolver = SystemAudioDuckingService.defaultOutputDevice,
        deviceForUIDResolver: @escaping DeviceForUIDResolver = SystemAudioDuckingService.deviceID(forUID:),
        volumeReader: @escaping VolumeReader = SystemAudioDuckingService.readOutputVolume(of:),
        volumeWriter: @escaping VolumeWriter = SystemAudioDuckingService.writeOutputVolume(of:to:)
    ) {
        defaults = userDefaults
        self.defaultOutputDeviceResolver = defaultOutputDeviceResolver
        self.deviceForUIDResolver = deviceForUIDResolver
        self.volumeReader = volumeReader
        self.volumeWriter = volumeWriter
    }

    func duck() {
        guard activeSnapshot == nil else {
            return
        }

        guard let device = defaultOutputDeviceResolver(),
              let preDuckVolume = volumeReader(device.id) else {
            return
        }

        let target = min(max(preDuckVolume * Self.duckFactor, 0), 1)
        guard volumeWriter(device.id, target) else {
            return
        }

        let snapshot = Snapshot(
            deviceUID: device.uid,
            preDuckVolume: preDuckVolume,
            appliedDuckedVolume: volumeReader(device.id) ?? target
        )
        activeSnapshot = snapshot
        persist(snapshot)
    }

    func restore() {
        guard let snapshot = activeSnapshot else {
            return
        }

        activeSnapshot = nil
        restoreVolume(from: snapshot)
        clearPersistedSnapshot()
    }

    /// Repairs a duck left behind by a crash or force-quit while recording.
    /// Call once at app launch.
    func restoreStaleSnapshotIfNeeded() {
        guard activeSnapshot == nil, let snapshot = persistedSnapshot() else {
            return
        }

        restoreVolume(from: snapshot)
        clearPersistedSnapshot()
    }

    private func restoreVolume(from snapshot: Snapshot) {
        // Re-resolve by UID so the original device is restored even if the
        // system default changed mid-recording. A vanished device (unplugged
        // headset) simply drops the snapshot.
        guard let deviceID = deviceForUIDResolver(snapshot.deviceUID),
              let currentVolume = volumeReader(deviceID) else {
            return
        }

        guard abs(currentVolume - snapshot.appliedDuckedVolume) <= Self.volumeMatchTolerance else {
            return
        }

        _ = volumeWriter(deviceID, snapshot.preDuckVolume)
    }

    // MARK: - Snapshot persistence

    private func persist(_ snapshot: Snapshot) {
        defaults.set(snapshot.deviceUID, forKey: SnapshotKeys.deviceUID)
        defaults.set(snapshot.preDuckVolume, forKey: SnapshotKeys.preDuckVolume)
        defaults.set(snapshot.appliedDuckedVolume, forKey: SnapshotKeys.appliedDuckedVolume)
    }

    private func persistedSnapshot() -> Snapshot? {
        guard let deviceUID = defaults.string(forKey: SnapshotKeys.deviceUID),
              defaults.object(forKey: SnapshotKeys.preDuckVolume) != nil,
              defaults.object(forKey: SnapshotKeys.appliedDuckedVolume) != nil else {
            return nil
        }

        return Snapshot(
            deviceUID: deviceUID,
            preDuckVolume: defaults.float(forKey: SnapshotKeys.preDuckVolume),
            appliedDuckedVolume: defaults.float(forKey: SnapshotKeys.appliedDuckedVolume)
        )
    }

    private func clearPersistedSnapshot() {
        defaults.removeObject(forKey: SnapshotKeys.deviceUID)
        defaults.removeObject(forKey: SnapshotKeys.preDuckVolume)
        defaults.removeObject(forKey: SnapshotKeys.appliedDuckedVolume)
    }

    // MARK: - CoreAudio defaults

    private static var virtualMainVolumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func volumeScalarAddress(channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
    }

    /// Readable volume addresses in priority order: the virtual main volume
    /// (what the volume keys control), then the main-element scalar, then the
    /// first channel for devices that only expose per-channel volume.
    private static var candidateVolumeAddresses: [AudioObjectPropertyAddress] {
        [
            virtualMainVolumeAddress,
            volumeScalarAddress(channel: kAudioObjectPropertyElementMain),
            volumeScalarAddress(channel: 1),
        ]
    }

    private static func defaultOutputDevice() -> OutputDevice? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        guard let uid = deviceUID(of: deviceID), !uid.isEmpty else {
            return nil
        }

        return OutputDevice(id: deviceID, uid: uid)
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        var deviceIDs = Array(repeating: AudioDeviceID(), count: deviceCount)

        guard AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return nil
        }

        return deviceIDs.first(where: { deviceUID(of: $0) == uid })
    }

    private static func deviceUID(of deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var cfString: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>>.stride)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &cfString) == noErr else {
            return nil
        }

        guard let unmanaged = cfString else {
            return nil
        }

        let string = unmanaged.takeUnretainedValue() as String
        unmanaged.release()
        return string
    }

    private static func readOutputVolume(of deviceID: AudioDeviceID) -> Float32? {
        for candidate in candidateVolumeAddresses {
            var address = candidate
            guard AudioObjectHasProperty(deviceID, &address) else {
                continue
            }

            var volume = Float32(0)
            var dataSize = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume) == noErr {
                return volume
            }
        }

        return nil
    }

    private static func writeOutputVolume(of deviceID: AudioDeviceID, to volume: Float32) -> Bool {
        var target = min(max(volume, 0), 1)
        let dataSize = UInt32(MemoryLayout<Float32>.size)

        for candidate in candidateVolumeAddresses {
            var address = candidate
            var isSettable = DarwinBoolean(false)
            guard AudioObjectHasProperty(deviceID, &address),
                  AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
                  isSettable.boolValue else {
                continue
            }

            guard AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &target) == noErr else {
                continue
            }

            // Per-channel devices need the second channel kept in step.
            if address.mElement == 1 {
                var secondChannel = volumeScalarAddress(channel: 2)
                if AudioObjectHasProperty(deviceID, &secondChannel) {
                    _ = AudioObjectSetPropertyData(deviceID, &secondChannel, 0, nil, dataSize, &target)
                }
            }

            return true
        }

        return false
    }
}
