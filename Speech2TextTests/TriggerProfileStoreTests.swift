import XCTest
@testable import Speech2Text

final class TriggerProfileStoreTests: XCTestCase {
    func testDefaultProfileReturnedWhenStorageMissing() async {
        let store = TriggerProfileStore(storeURL: makeStoreURL().appendingPathComponent("TriggerProfileStore.json"))

        let loaded = await store.load()

        XCTAssertEqual(loaded.activeProfile, .default)
        XCTAssertEqual(loaded.activePrimary, AssistantDefaults.defaultAssistantName)
    }

    func testCustomPrimaryPersistsAcrossRelaunches() async throws {
        let storeURL = makeStoreURL().appendingPathComponent("TriggerProfileStore.json")
        let store1 = TriggerProfileStore(storeURL: storeURL)
        try await store1.save(
            TriggerProfile.defaultProfile
                .updatingCustom(primary: "Helios")
                .settingActiveProfile(.custom)
        )

        let store2 = TriggerProfileStore(storeURL: storeURL)
        let loaded = await store2.load()

        XCTAssertEqual(loaded.activeProfile, .custom)
        XCTAssertEqual(loaded.activePrimary, "Helios")
    }

    func testCustomPayloadRestoredAfterSwitchAwayAndBack() async throws {
        let storeURL = makeStoreURL().appendingPathComponent("TriggerProfileStore.json")
        let store = TriggerProfileStore(storeURL: storeURL)
        let custom = TriggerProfile.defaultProfile
            .updatingCustom(primary: "  HeLios  ")
        try await store.save(custom)
        try await store.save(custom.settingActiveProfile(.default))

        let reloadedOnDefault = await TriggerProfileStore(storeURL: storeURL).load()
        XCTAssertEqual(reloadedOnDefault.activeProfile, .default)
        XCTAssertEqual(reloadedOnDefault.activePrimary, AssistantDefaults.defaultAssistantName)
        XCTAssertEqual(reloadedOnDefault.customPrimary, "HeLios")

        let switchedBack = reloadedOnDefault.settingActiveProfile(.custom)
        XCTAssertEqual(switchedBack.activePrimary, "HeLios")
    }

    func testCorruptionFallsBackToDefaultProfile() async throws {
        let storeURL = makeStoreURL().appendingPathComponent("TriggerProfileStore.json")
        try Data("corrupted-json".utf8).write(to: storeURL, options: .atomic)

        let loaded = await TriggerProfileStore(storeURL: storeURL).load()

        XCTAssertEqual(loaded, .defaultProfile)

        let contents = try FileManager.default.contentsOfDirectory(atPath: storeURL.deletingLastPathComponent().path)
        XCTAssertTrue(contents.contains(where: { $0.hasPrefix("TriggerProfileStore.json.corrupt") }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testFailedSaveDoesNotReplaceLastKnownPersistedProfile() async throws {
        let tempDirectory = makeStoreURL()
        let storeURL = tempDirectory.appendingPathComponent("TriggerProfileStore.json")
        let store = TriggerProfileStore(storeURL: storeURL)
        let original = TriggerProfile.defaultProfile
            .updatingCustom(primary: "Athena")
            .settingActiveProfile(.custom)
        try await store.save(original)

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o555)],
            ofItemAtPath: tempDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: tempDirectory.path
            )
        }

        do {
            try await store.save(original.settingActiveProfile(.default))
            XCTFail("Expected save to fail in read-only directory")
        } catch {
            // expected
        }

        let reloaded = await TriggerProfileStore(storeURL: storeURL).load()
        XCTAssertEqual(reloaded.activeProfile, .custom)
        XCTAssertEqual(reloaded.activePrimary, "Athena")
    }

    private func makeStoreURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TriggerProfileStoreTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
