@testable import TypeLessBuddy
import XCTest

final class DictionaryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DictionaryStoreTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func storeURL() -> URL {
        tempDir.appendingPathComponent("DictionaryStore.json")
    }

    func testEmptyByDefault() async {
        let store = DictionaryStore(storeURL: storeURL())
        let data = await store.load()
        XCTAssertEqual(data, .empty)
        XCTAssertTrue(data.replacements.isEmpty)
    }

    func testPersistAndReload() async throws {
        let url = storeURL()
        let store = DictionaryStore(storeURL: url)

        var data = DictionaryData.empty
        data.replacements.append(WordReplacement(originals: ["gonna"], replacement: "going to"))

        try await store.save(data)

        let freshStore = DictionaryStore(storeURL: url)
        let loaded = await freshStore.load()
        XCTAssertEqual(loaded.replacements.count, 1)
        XCTAssertEqual(loaded.replacements.first?.originals, ["gonna"])
        XCTAssertEqual(loaded.replacements.first?.replacement, "going to")
    }

    func testCorruptFileReturnsEmptyAndQuarantines() {
        let url = storeURL()
        try! "not json".data(using: .utf8)!.write(to: url)

        let data = DictionaryStore.loadSynchronously(storeURL: url)
        XCTAssertEqual(data, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoadSynchronouslyMissingFile() {
        let data = DictionaryStore.loadSynchronously(storeURL: storeURL())
        XCTAssertEqual(data, .empty)
    }

    func testMultipleReplacementsPersist() async throws {
        let store = DictionaryStore(storeURL: storeURL())
        var data = DictionaryData.empty
        data.replacements = [
            WordReplacement(originals: ["gonna", "gona"], replacement: "going to"),
            WordReplacement(originals: ["wanna"], replacement: "want to"),
        ]
        try await store.save(data)

        let loaded = await store.load()
        XCTAssertEqual(loaded.replacements.count, 2)
    }
}
