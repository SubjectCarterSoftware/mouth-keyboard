import XCTest
@testable import MouthKeyboard

/// `ManualSleeper` and `ActivationStoreMockClipboard` are declared (internal,
/// not private) in ActivationStoreTests.swift and reused here so clipboard
/// arrivals can be driven deterministically by virtual time.
@MainActor
final class RecordingScreenshotCollectorTests: XCTestCase {
    private var clipboard: ActivationStoreMockClipboard!
    private var sleeper: ManualSleeper!
    private var collector: RecordingScreenshotCollector!

    override func setUp() {
        super.setUp()
        clipboard = ActivationStoreMockClipboard()
        sleeper = ManualSleeper()
    }

    override func tearDown() {
        collector?.stop()
        collector = nil
        clipboard = nil
        sleeper = nil
        super.tearDown()
    }

    func testBaselineChangeCountIsIgnored() async {
        clipboard.stubbedChangeCount = 5
        clipboard.stubbedCollectableAttachments = [.image(Data([1, 2, 3]))]
        collector = makeCollector()
        collector.start(baselineChangeCount: 5)

        await tick()

        XCTAssertEqual(collector.count, 0)
    }

    func testNewImageIsCounted() async {
        let imageData = Data([1, 2, 3])
        collector = makeCollector()
        var changes: [Int] = []
        collector.onChange = { count, _ in changes.append(count) }
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(imageData)]
        await tick()

        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(changes, [1])
    }

    func testTextCopyIsIgnored() async {
        collector = makeCollector()
        collector.start(baselineChangeCount: 0)

        // A change with no eligible attachment (e.g. a plain text copy) leaves
        // `readCollectableAttachments` returning [].
        clipboard.stubbedChangeCount = 1
        await tick()

        XCTAssertEqual(collector.count, 0)
    }

    func testDuplicateImageTriggersOnDuplicateAndIsNotCounted() async {
        let imageData = Data([9, 9, 9])
        collector = makeCollector()
        var duplicateCount = 0
        collector.onDuplicate = { duplicateCount += 1 }
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(imageData)]
        await tick()
        XCTAssertEqual(collector.count, 1)

        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(imageData)]
        await tick()

        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(duplicateCount, 1)
    }

    func testDuplicateFileByPathIsSkipped() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("document.pdf")
        try Data("pdf".utf8).write(to: fileURL)

        collector = makeCollector()
        var duplicateCount = 0
        collector.onDuplicate = { duplicateCount += 1 }
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.file(fileURL)]
        await tick()
        XCTAssertEqual(collector.count, 1)

        // The same path, resolved through a symlink, is still a duplicate.
        let symlinkURL = directory.appendingPathComponent("alias.pdf")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: fileURL)

        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.file(symlinkURL)]
        await tick()

        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(duplicateCount, 1)
    }

    func testCapEnforcedAcrossKinds() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("document.pdf")
        try Data("pdf".utf8).write(to: fileURL)

        collector = makeCollector(maxCount: 2)
        var fullCount = 0
        collector.onFull = { fullCount += 1 }
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(Data([1]))]
        await tick()

        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.file(fileURL)]
        await tick()

        clipboard.stubbedChangeCount = 3
        clipboard.stubbedCollectableAttachments = [.image(Data([2]))]
        await tick()

        XCTAssertEqual(collector.count, 2)
        XCTAssertEqual(fullCount, 1)
    }

    func testMultiFileCopyAddsEachFile() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("one.pdf")
        let secondURL = directory.appendingPathComponent("two.zip")
        try Data("one".utf8).write(to: firstURL)
        try Data("two".utf8).write(to: secondURL)

        collector = makeCollector()
        var changes: [Int] = []
        collector.onChange = { count, _ in changes.append(count) }
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.file(firstURL), .file(secondURL)]
        await tick()

        XCTAssertEqual(collector.count, 2)
        XCTAssertEqual(changes, [1, 2])
    }

    func testIncludesFilesBecomesTrueOnlyForNonImageFiles() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("photo.png")
        try Data("png".utf8).write(to: imageURL)

        collector = makeCollector()
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.file(imageURL)]
        await tick()
        XCTAssertFalse(collector.includesFiles)

        let pdfURL = directory.appendingPathComponent("document.pdf")
        try Data("pdf".utf8).write(to: pdfURL)
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.file(pdfURL)]
        await tick()

        XCTAssertTrue(collector.includesFiles)
    }

    func testStopReturnsAttachmentsInOrderAndStopsPolling() async {
        let first = Data([1])
        let second = Data([2])
        collector = makeCollector()
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(first)]
        await tick()

        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(second)]
        await tick()

        let stopped = collector.stop()
        XCTAssertEqual(stopped, [.image(first), .image(second)])
        XCTAssertFalse(collector.isRunning)

        // Further clipboard changes shouldn't be picked up once stopped.
        clipboard.stubbedChangeCount = 3
        clipboard.stubbedCollectableAttachments = [.image(Data([3]))]
        await tick()

        XCTAssertEqual(collector.count, 2)
    }

    func testRemoveLastDropsNewestAndForgetsItsKeySoReCopyingReAddsIt() async {
        let first = Data([1])
        let second = Data([2])
        collector = makeCollector()
        var changes: [Int] = []
        var includesFilesValues: [Bool] = []
        collector.onChange = { count, includesFiles in
            changes.append(count)
            includesFilesValues.append(includesFiles)
        }
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(first)]
        await tick()
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(second)]
        await tick()
        XCTAssertEqual(collector.count, 2)

        let removed = collector.removeLast()
        XCTAssertEqual(removed, .image(second))
        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(changes.last, 1)
        XCTAssertEqual(includesFilesValues.last, false)

        // Re-copying the same (now-forgotten) image re-adds it rather than
        // being treated as a duplicate.
        clipboard.stubbedChangeCount = 3
        clipboard.stubbedCollectableAttachments = [.image(second)]
        await tick()
        XCTAssertEqual(collector.count, 2)
        XCTAssertEqual(collector.stop(), [.image(first), .image(second)])
    }

    func testRemoveLastOnEmptyCollectorIsANoOp() async {
        collector = makeCollector()
        var changeCount = 0
        collector.onChange = { _, _ in changeCount += 1 }
        collector.start(baselineChangeCount: 0)

        XCTAssertNil(collector.removeLast())
        XCTAssertEqual(collector.count, 0)
        XCTAssertEqual(changeCount, 0)
    }

    func testRemoveLastRecomputesIncludesFilesWhenLastNonImageFileIsRemoved() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdfURL = directory.appendingPathComponent("document.pdf")
        try Data("pdf".utf8).write(to: pdfURL)

        collector = makeCollector()
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(Data([1]))]
        await tick()

        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.file(pdfURL)]
        await tick()
        XCTAssertTrue(collector.includesFiles)

        // Removing the trailing (non-image) file drops `includesFiles` back
        // to false since only the image remains.
        collector.removeLast()
        XCTAssertFalse(collector.includesFiles)
        XCTAssertEqual(collector.count, 1)
    }

    func testRemoveLastWorksAfterStop() async {
        collector = makeCollector()
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(Data([1]))]
        await tick()
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.image(Data([2]))]
        await tick()

        let stopped = collector.stop()
        XCTAssertEqual(stopped.count, 2)

        let removed = collector.removeLast()
        XCTAssertEqual(removed, .image(Data([2])))
        XCTAssertEqual(collector.count, 1)
        XCTAssertFalse(collector.isRunning)
    }

    func testClearCollectedEmptiesEverythingAndForgetsAllKeys() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdfURL = directory.appendingPathComponent("document.pdf")
        try Data("pdf".utf8).write(to: pdfURL)
        let imageData = Data([1, 2, 3])

        collector = makeCollector()
        var changes: [(Int, Bool)] = []
        collector.onChange = { count, includesFiles in changes.append((count, includesFiles)) }
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(imageData)]
        await tick()
        clipboard.stubbedChangeCount = 2
        clipboard.stubbedCollectableAttachments = [.file(pdfURL)]
        await tick()
        XCTAssertEqual(collector.count, 2)
        XCTAssertTrue(collector.includesFiles)

        collector.clearCollected()
        XCTAssertEqual(collector.count, 0)
        XCTAssertFalse(collector.includesFiles)
        XCTAssertEqual(changes.last?.0, 0)
        XCTAssertEqual(changes.last?.1, false)
        // Still recording — the poll loop is untouched by a clear.
        XCTAssertTrue(collector.isRunning)

        // Both the image and the file are re-collectable since their dedupe
        // keys were forgotten too.
        clipboard.stubbedChangeCount = 3
        clipboard.stubbedCollectableAttachments = [.image(imageData), .file(pdfURL)]
        await tick()
        XCTAssertEqual(collector.count, 2)
        XCTAssertTrue(collector.includesFiles)
    }

    func testClearCollectedWorksAfterStop() async {
        collector = makeCollector()
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(Data([1]))]
        await tick()

        _ = collector.stop()
        XCTAssertEqual(collector.count, 1)

        collector.clearCollected()
        XCTAssertEqual(collector.count, 0)
        XCTAssertFalse(collector.isRunning)
    }

    func testResetClears() async {
        collector = makeCollector()
        collector.start(baselineChangeCount: 0)

        clipboard.stubbedChangeCount = 1
        clipboard.stubbedCollectableAttachments = [.image(Data([1]))]
        await tick()
        XCTAssertEqual(collector.count, 1)

        collector.reset()

        XCTAssertEqual(collector.count, 0)
        XCTAssertFalse(collector.isRunning)
        XCTAssertFalse(collector.includesFiles)
    }

    // MARK: - Test helpers

    private let pollInterval: TimeInterval = 0.05

    private func makeCollector(maxCount: Int = 20) -> RecordingScreenshotCollector {
        RecordingScreenshotCollector(
            clipboard: clipboard,
            sleeper: sleeper,
            pollInterval: pollInterval,
            maxCount: maxCount
        )
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingScreenshotCollectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Advances virtual time by one poll tick and gives the background loop a
    /// brief real-time window to react and settle. The leading sleep gives the
    /// loop's `Task` a moment to actually reach its `sleeper.sleep` call before
    /// virtual time moves past it (otherwise the advance can land before the
    /// loop has parked, and it would need a whole extra interval to catch up).
    private func tick() async {
        try? await Task.sleep(nanoseconds: 5_000_000)
        sleeper.advance(by: pollInterval)
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}
