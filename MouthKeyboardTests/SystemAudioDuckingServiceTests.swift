import CoreAudio
import XCTest
@testable import MouthKeyboard

@MainActor
final class SystemAudioDuckingServiceTests: XCTestCase {
    private let deviceID = AudioDeviceID(42)
    private let deviceUID = "test-output-device"

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SystemAudioDuckingServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeService(
        currentVolume: @escaping () -> Float32?,
        deviceHasVanished: @escaping () -> Bool = { false },
        onWrite: @escaping (Float32) -> Bool = { _ in true }
    ) -> SystemAudioDuckingService {
        SystemAudioDuckingService(
            userDefaults: defaults,
            defaultOutputDeviceResolver: { [deviceID, deviceUID] in
                SystemAudioDuckingService.OutputDevice(id: deviceID, uid: deviceUID)
            },
            deviceForUIDResolver: { [deviceID, deviceUID] uid in
                if deviceHasVanished() {
                    return nil
                }
                return uid == deviceUID ? deviceID : nil
            },
            volumeReader: { _ in currentVolume() },
            volumeWriter: { _, value in onWrite(value) }
        )
    }

    func testDuckWritesHalvedVolumeAndPersistsSnapshot() {
        var volume: Float32 = 0.8
        var writes: [Float32] = []
        let service = makeService(
            currentVolume: { volume },
            onWrite: { value in
                writes.append(value)
                volume = value
                return true
            }
        )

        service.duck()

        XCTAssertEqual(writes, [0.4])
        XCTAssertEqual(defaults.string(forKey: "duckingSnapshotDeviceUID"), deviceUID)
        XCTAssertEqual(defaults.float(forKey: "duckingSnapshotPreDuckVolume"), 0.8)
        XCTAssertEqual(defaults.float(forKey: "duckingSnapshotAppliedVolume"), 0.4)
    }

    func testDuckTwiceOnlyWritesOnce() {
        var volume: Float32 = 0.8
        var writeCount = 0
        let service = makeService(
            currentVolume: { volume },
            onWrite: { value in
                writeCount += 1
                volume = value
                return true
            }
        )

        service.duck()
        service.duck()

        XCTAssertEqual(writeCount, 1)
    }

    func testRestoreWritesBackPreDuckVolumeAndClearsSnapshot() {
        var volume: Float32 = 0.8
        var writes: [Float32] = []
        let service = makeService(
            currentVolume: { volume },
            onWrite: { value in
                writes.append(value)
                volume = value
                return true
            }
        )

        service.duck()
        service.restore()

        XCTAssertEqual(writes, [0.4, 0.8])
        XCTAssertNil(defaults.string(forKey: "duckingSnapshotDeviceUID"))
        XCTAssertNil(defaults.object(forKey: "duckingSnapshotPreDuckVolume"))
        XCTAssertNil(defaults.object(forKey: "duckingSnapshotAppliedVolume"))
    }

    func testRestoreLeavesUserAdjustedVolumeAlone() {
        var volume: Float32 = 0.8
        var writes: [Float32] = []
        let service = makeService(
            currentVolume: { volume },
            onWrite: { value in
                writes.append(value)
                volume = value
                return true
            }
        )

        service.duck()
        volume = 1.0 // user cranked the volume mid-recording
        service.restore()

        XCTAssertEqual(writes, [0.4])
        XCTAssertNil(defaults.string(forKey: "duckingSnapshotDeviceUID"))
    }

    func testRestoreWithoutDuckIsNoOp() {
        var writeCount = 0
        let service = makeService(
            currentVolume: { 0.8 },
            onWrite: { _ in
                writeCount += 1
                return true
            }
        )

        service.restore()

        XCTAssertEqual(writeCount, 0)
    }

    func testDuckIsNoOpWhenVolumeWriteFails() {
        let service = makeService(
            currentVolume: { 0.8 },
            onWrite: { _ in false }
        )

        service.duck()

        XCTAssertNil(defaults.string(forKey: "duckingSnapshotDeviceUID"))
    }

    func testDuckIsNoOpWhenVolumeIsUnreadable() {
        var writeCount = 0
        let service = makeService(
            currentVolume: { nil },
            onWrite: { _ in
                writeCount += 1
                return true
            }
        )

        service.duck()

        XCTAssertEqual(writeCount, 0)
        XCTAssertNil(defaults.string(forKey: "duckingSnapshotDeviceUID"))
    }

    func testRestoreStaleSnapshotRestoresPersistedVolume() {
        defaults.set(deviceUID, forKey: "duckingSnapshotDeviceUID")
        defaults.set(Float32(0.9), forKey: "duckingSnapshotPreDuckVolume")
        defaults.set(Float32(0.45), forKey: "duckingSnapshotAppliedVolume")

        var volume: Float32 = 0.45
        var writes: [Float32] = []
        let service = makeService(
            currentVolume: { volume },
            onWrite: { value in
                writes.append(value)
                volume = value
                return true
            }
        )

        service.restoreStaleSnapshotIfNeeded()

        XCTAssertEqual(writes, [0.9])
        XCTAssertNil(defaults.string(forKey: "duckingSnapshotDeviceUID"))
    }

    func testRestoreClearsSnapshotWhenOriginalDeviceVanished() {
        var volume: Float32 = 0.8
        var writes: [Float32] = []
        var deviceVanished = false
        let service = makeService(
            currentVolume: { volume },
            deviceHasVanished: { deviceVanished },
            onWrite: { value in
                writes.append(value)
                volume = value
                return true
            }
        )

        service.duck()
        deviceVanished = true // headset unplugged mid-recording
        service.restore()

        XCTAssertEqual(writes, [0.4])
        XCTAssertNil(defaults.string(forKey: "duckingSnapshotDeviceUID"))
        XCTAssertNil(defaults.object(forKey: "duckingSnapshotPreDuckVolume"))
    }
}
