import XCTest
@testable import Speech2Text

class UserIntentStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempStore() -> UserIntentStore {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        return UserIntentStore(storeURL: tmpURL)
    }

    private func makeBuiltInEntry(mode: ConvertMode = .email) -> UserIntentEntry {
        UserIntentEntry(
            id: mode.rawValue,
            modeName: mode.rawValue,
            systemPrompt: "Custom prompt for \(mode.rawValue)",
            phrasePatterns: ["pattern one", "pattern two"],
            keywordSignal: "signal",
            isBuiltIn: true
        )
    }

    private func makeCustomEntry(id: String = UUID().uuidString) -> UserIntentEntry {
        UserIntentEntry(
            id: id,
            modeName: "My Custom Mode",
            systemPrompt: "Do something custom",
            phrasePatterns: ["custom pattern"],
            keywordSignal: "custom",
            isBuiltIn: false
        )
    }

    // MARK: - Tests

    func testEmptyStoreReturnsNoEntries() async {
        let store = makeTempStore()
        let entries = await store.allEntries()
        XCTAssertTrue(entries.isEmpty, "Expected empty store to return no entries, got \(entries.count)")
    }

    func testSaveAndReloadBuiltInOverride() async throws {
        let store = makeTempStore()
        let entry = makeBuiltInEntry(mode: .email)

        try await store.addOrUpdateBuiltInOverride(entry)

        // Create a second store pointing to the same URL to verify disk persistence
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        // Use the same store to reload
        let entries = await store.allEntries()
        XCTAssertEqual(entries.count, 1)
        let loaded = entries.first
        XCTAssertEqual(loaded?.id, entry.id)
        XCTAssertEqual(loaded?.systemPrompt, entry.systemPrompt)
        XCTAssertEqual(loaded?.phrasePatterns, entry.phrasePatterns)
        XCTAssertEqual(loaded?.isBuiltIn, true)
    }

    func testRoundTripBuiltInOverride() async throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        let store1 = UserIntentStore(storeURL: tmpURL)
        let entry = makeBuiltInEntry(mode: .slack)

        try await store1.addOrUpdateBuiltInOverride(entry)

        // Load from a fresh actor at the same URL to verify disk persistence
        let store2 = UserIntentStore(storeURL: tmpURL)
        let entries = await store2.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, entry.id)
        XCTAssertEqual(entries.first?.systemPrompt, entry.systemPrompt)
        XCTAssertEqual(entries.first?.phrasePatterns, entry.phrasePatterns)
        XCTAssertEqual(entries.first?.isBuiltIn, true)
    }

    func testRoundTripCustomMode() async throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        let store1 = UserIntentStore(storeURL: tmpURL)
        let entry = makeCustomEntry()

        try await store1.addOrUpdateCustomMode(entry)

        let store2 = UserIntentStore(storeURL: tmpURL)
        let entries = await store2.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, entry.id)
        XCTAssertEqual(entries.first?.isBuiltIn, false)
    }

    func testResetBuiltInRemovesEntry() async throws {
        let store = makeTempStore()
        let entry = makeBuiltInEntry(mode: .email)
        try await store.addOrUpdateBuiltInOverride(entry)

        try await store.resetBuiltIn(mode: .email)

        let entries = await store.allEntries()
        XCTAssertFalse(
            entries.contains(where: { $0.id == ConvertMode.email.rawValue }),
            "Email entry should be removed after resetBuiltIn"
        )
    }

    func testResetBuiltInPersistsToDisk() async throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        let store1 = UserIntentStore(storeURL: tmpURL)
        let entry = makeBuiltInEntry(mode: .email)
        try await store1.addOrUpdateBuiltInOverride(entry)
        try await store1.resetBuiltIn(mode: .email)

        let store2 = UserIntentStore(storeURL: tmpURL)
        let entries = await store2.allEntries()
        XCTAssertFalse(
            entries.contains(where: { $0.id == ConvertMode.email.rawValue }),
            "Email entry should not be present after reset and reload"
        )
    }

    func testAddOrUpdateCustomModeUpdatesInPlace() async throws {
        let store = makeTempStore()
        let id = UUID().uuidString
        let original = UserIntentEntry(
            id: id, modeName: "Mode", systemPrompt: "Original", phrasePatterns: [], keywordSignal: "", isBuiltIn: false
        )
        let updated = UserIntentEntry(
            id: id, modeName: "Mode", systemPrompt: "Updated", phrasePatterns: ["p1"], keywordSignal: "k1", isBuiltIn: false
        )

        try await store.addOrUpdateCustomMode(original)
        try await store.addOrUpdateCustomMode(updated)

        let entries = await store.allEntries()
        let matching = entries.filter { $0.id == id }
        XCTAssertEqual(matching.count, 1, "Should have exactly one entry for id (no duplicate)")
        XCTAssertEqual(matching.first?.systemPrompt, "Updated")
    }

    func testDeleteCustomModeRemovesEntry() async throws {
        let store = makeTempStore()
        let entry = makeCustomEntry()

        try await store.addOrUpdateCustomMode(entry)
        try await store.deleteCustomMode(id: entry.id)

        let entries = await store.allEntries()
        XCTAssertFalse(entries.contains(where: { $0.id == entry.id }), "Deleted entry should not appear")
    }

    func testAppSupportDirectoryCreatedOnWrite() async throws {
        // Use a nested tmp path that does not yet exist
        let nestedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("SubDir", isDirectory: true)
        let storeURL = nestedDir.appendingPathComponent("IntentStore.json")

        let store = UserIntentStore(storeURL: storeURL)
        let entry = makeCustomEntry()

        // Writing should create intermediate directories without error
        try await store.addOrUpdateCustomMode(entry)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storeURL.path),
            "Store file should have been created at nested path"
        )
    }
}
