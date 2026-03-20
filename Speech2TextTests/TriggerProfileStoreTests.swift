import XCTest
@testable import Speech2Text

final class TriggerProfileStoreTests: XCTestCase {
    func testDefaultZeusOnMissingStorage() async {
        let store = TriggerProfileStore(storeURL: makeStoreURL().appendingPathComponent("TriggerProfileStore.json"))

        let loaded = await store.load()

        XCTAssertEqual(loaded.activeProfile, .zeus)
        XCTAssertEqual(loaded.activeAliases, ["zeus"])
    }

    func testPresetPersistenceSurvivesRelaunch() async throws {
        let storeURL = makeStoreURL().appendingPathComponent("TriggerProfileStore.json")
        let store1 = TriggerProfileStore(storeURL: storeURL)
        try await store1.save(
            TriggerProfile.defaultProfile
                .updatingCustom(primary: "Helios", aliases: ["hello"])
                .settingActiveProfile(.atlas)
        )

        let store2 = TriggerProfileStore(storeURL: storeURL)
        let loaded = await store2.load()

        XCTAssertEqual(loaded.activeProfile, .atlas)
        XCTAssertEqual(loaded.activeAliases, ["atlas"])
    }

    func testCustomPayloadRestoredAfterSwitchAwayAndBack() async throws {
        let storeURL = makeStoreURL().appendingPathComponent("TriggerProfileStore.json")
        let store = TriggerProfileStore(storeURL: storeURL)
        let custom = TriggerProfile.defaultProfile
            .updatingCustom(primary: "  HeLios  ", aliases: ["hello zeus", "HELIOS"])
        try await store.save(custom)
        try await store.save(custom.settingActiveProfile(.gaia))

        let reloadedAfterPreset = await TriggerProfileStore(storeURL: storeURL).load()
        XCTAssertEqual(reloadedAfterPreset.activeProfile, .gaia)
        XCTAssertEqual(reloadedAfterPreset.customPrimary, "Helios")
        XCTAssertEqual(reloadedAfterPreset.customAliases, ["hello zeus"])

        let switchedBack = reloadedAfterPreset.settingActiveProfile(.custom)
        XCTAssertEqual(switchedBack.activeAliases, ["helios", "hello zeus"])
    }

    func testCorruptionFallbackToZeus() async throws {
        let storeURL = makeStoreURL().appendingPathComponent("TriggerProfileStore.json")
        try Data("corrupted-json".utf8).write(to: storeURL, options: .atomic)

        let loaded = await TriggerProfileStore(storeURL: storeURL).load()

        XCTAssertEqual(loaded, .defaultProfile)
    }

    func testFailedSaveDoesNotReplaceLastKnownPersistedProfile() async throws {
        let tempDirectory = makeStoreURL()
        let storeURL = tempDirectory.appendingPathComponent("TriggerProfileStore.json")
        let store = TriggerProfileStore(storeURL: storeURL)
        let original = TriggerProfile.defaultProfile
            .updatingCustom(primary: "Athena", aliases: ["assistant athena"])
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
            try await store.save(original.settingActiveProfile(.atlas))
            XCTFail("Expected save to fail in read-only directory")
        } catch {
            // expected
        }

        let reloaded = await TriggerProfileStore(storeURL: storeURL).load()
        XCTAssertEqual(reloaded.activeProfile, .custom)
        XCTAssertEqual(reloaded.activeAliases, ["athena", "assistant athena"])
    }

    private func makeStoreURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TriggerProfileStoreTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
