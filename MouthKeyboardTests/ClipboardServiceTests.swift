import AppKit
import XCTest
@testable import MouthKeyboard

final class ClipboardServiceTests: XCTestCase {

    var testPasteboard: NSPasteboard!
    var service: ClipboardService!

    override func setUp() {
        super.setUp()
        // Use a unique named pasteboard for isolation
        testPasteboard = NSPasteboard(name: .init("com.mouthkeyboard.test.\(UUID().uuidString)"))
        testPasteboard.clearContents()
        service = ClipboardService(pasteboard: testPasteboard)
    }

    override func tearDown() {
        testPasteboard.releaseGlobally()
        super.tearDown()
    }

    func testWriteToClipboardReturnsTrue() {
        let result = service.writeToClipboard("hello")
        XCTAssertTrue(result)
    }

    func testWriteToClipboardPasteboardContainsText() {
        service.writeToClipboard("test text")
        let contents = testPasteboard.string(forType: .string)
        XCTAssertEqual(contents, "test text")
    }

    func testWritingNewTextReplacesOldText() {
        service.writeToClipboard("first")
        service.writeToClipboard("second")
        let contents = testPasteboard.string(forType: .string)
        XCTAssertEqual(contents, "second")
    }

    func testSnapshotAndRestorePreservesTextAndHtml() throws {
        let originalItem = NSPasteboardItem()
        originalItem.setString("plain text", forType: .string)
        originalItem.setString("<b>plain text</b>", forType: .html)
        XCTAssertTrue(testPasteboard.writeObjects([originalItem]))

        let snapshot = service.snapshotCurrentClipboard()
        let receipt = try XCTUnwrap(service.writeTemporaryText("temporary text"))

        XCTAssertEqual(testPasteboard.string(forType: .string), "temporary text")
        XCTAssertTrue(service.restoreClipboard(from: snapshot, ifUnchangedSince: receipt))
        XCTAssertEqual(testPasteboard.string(forType: .string), "plain text")
        XCTAssertEqual(testPasteboard.string(forType: .html), "<b>plain text</b>")
    }

    func testRestoreSkipsWhenClipboardChangedAfterTemporaryWrite() throws {
        service.writeToClipboard("original")
        let snapshot = service.snapshotCurrentClipboard()
        let receipt = try XCTUnwrap(service.writeTemporaryText("temporary"))

        testPasteboard.clearContents()
        testPasteboard.setString("user changed clipboard", forType: .string)

        XCTAssertFalse(service.restoreClipboard(from: snapshot, ifUnchangedSince: receipt))
        XCTAssertEqual(testPasteboard.string(forType: .string), "user changed clipboard")
    }

    // MARK: - readCollectableAttachments

    func testPNGOnlyCopyIsAcceptedAsImageAttachment() throws {
        let item = NSPasteboardItem()
        item.setData(makeTestPNGData(), forType: .png)
        XCTAssertTrue(testPasteboard.writeObjects([item]))

        let attachments = service.readCollectableAttachments()
        XCTAssertEqual(attachments.count, 1)
        guard case .image(let data) = attachments.first else {
            return XCTFail("Expected a .image attachment")
        }
        XCTAssertTrue(Self.hasPNGSignature(data))
    }

    func testPNGWithStringIsRejected() {
        let item = NSPasteboardItem()
        item.setData(makeTestPNGData(), forType: .png)
        item.setString("some caption", forType: .string)
        XCTAssertTrue(testPasteboard.writeObjects([item]))

        XCTAssertEqual(service.readCollectableAttachments(), [])
    }

    func testConcealedCopyIsRejected() {
        let item = NSPasteboardItem()
        item.setData(makeTestPNGData(), forType: .png)
        item.setString("1", forType: ClipboardService.concealedType)
        XCTAssertTrue(testPasteboard.writeObjects([item]))

        XCTAssertEqual(service.readCollectableAttachments(), [])
    }

    func testFinderCopyOfTwoFilesReturnsTwoFileAttachments() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let pdfURL = directory.appendingPathComponent("document.pdf")
        let pngURL = directory.appendingPathComponent("image.png")
        try Data("not a real pdf".utf8).write(to: pdfURL)
        try makeTestPNGData().write(to: pngURL)

        let pdfItem = NSPasteboardItem()
        pdfItem.setString(pdfURL.absoluteString, forType: .fileURL)
        pdfItem.setString(pdfURL.lastPathComponent, forType: .string)
        let pngItem = NSPasteboardItem()
        pngItem.setString(pngURL.absoluteString, forType: .fileURL)
        pngItem.setString(pngURL.lastPathComponent, forType: .string)
        // A Finder copy also carries the filenames as plain text on their own
        // items; that shouldn't disqualify the file URLs from being collected.
        XCTAssertTrue(testPasteboard.writeObjects([pdfItem, pngItem]))

        let attachments = service.readCollectableAttachments()
        XCTAssertEqual(attachments.count, 2)
        XCTAssertEqual(attachments, [.file(pdfURL), .file(pngURL)])
    }

    func testDirectoryFileURLIsSkipped() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = NSPasteboardItem()
        item.setString(directory.absoluteString, forType: .fileURL)
        XCTAssertTrue(testPasteboard.writeObjects([item]))

        XCTAssertEqual(service.readCollectableAttachments(), [])
    }

    func testOversizeFileIsSkipped() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("big.bin")
        try Data(repeating: 0x01, count: 32).write(to: fileURL)

        let limitedService = ClipboardService(pasteboard: testPasteboard, maxCollectableFileBytes: 8)
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        XCTAssertTrue(testPasteboard.writeObjects([item]))

        XCTAssertEqual(limitedService.readCollectableAttachments(), [])
    }

    func testMissingFileURLIsSkipped() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardServiceTests-missing-\(UUID().uuidString).pdf")

        let item = NSPasteboardItem()
        item.setString(missingURL.absoluteString, forType: .fileURL)
        XCTAssertTrue(testPasteboard.writeObjects([item]))

        XCTAssertEqual(service.readCollectableAttachments(), [])
    }

    func testTIFFIsConvertedToPNGImageAttachment() throws {
        let item = NSPasteboardItem()
        item.setData(makeTestTIFFData(), forType: .tiff)
        XCTAssertTrue(testPasteboard.writeObjects([item]))

        let attachments = service.readCollectableAttachments()
        guard case .image(let data) = attachments.first, attachments.count == 1 else {
            return XCTFail("Expected a single .image attachment")
        }
        XCTAssertTrue(Self.hasPNGSignature(data))
    }

    func testOversizeImageIsRejected() {
        // Inject a tiny cap so the test doesn't need to allocate a real 25MB image.
        let limitedService = ClipboardService(pasteboard: testPasteboard, maxCollectableScreenshotBytes: 8)

        let item = NSPasteboardItem()
        item.setData(makeTestPNGData(), forType: .png)
        XCTAssertTrue(testPasteboard.writeObjects([item]))

        XCTAssertEqual(limitedService.readCollectableAttachments(), [])
    }

    // MARK: - writeAttachments / writeTextAndAttachments

    func testWriteAttachmentsWritesOneFileURLItemPerAttachment() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStoreDirectory = directory.appendingPathComponent("attachments", isDirectory: true)
        let attachmentFileStore = AttachmentFileStore(baseDirectory: fileStoreDirectory)
        let service = ClipboardService(pasteboard: testPasteboard, attachmentFileStore: attachmentFileStore)

        let existingFileURL = directory.appendingPathComponent("existing.pdf")
        try Data("pdf".utf8).write(to: existingFileURL)

        let image1 = makeTestPNGData()
        let image2 = makeTestPNGData()
        let receipt = service.writeAttachments([.file(existingFileURL), .image(image1), .image(image2)])
        XCTAssertNotNil(receipt)

        let items = try XCTUnwrap(testPasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 3)

        let urls = items.map { URL(string: $0.string(forType: .fileURL) ?? "") }
        XCTAssertEqual(urls[0], existingFileURL)

        let imageURL1 = try XCTUnwrap(urls[1])
        let imageURL2 = try XCTUnwrap(urls[2])
        XCTAssertEqual(imageURL1.lastPathComponent, "Screenshot 1.png")
        XCTAssertEqual(imageURL2.lastPathComponent, "Screenshot 2.png")
        XCTAssertEqual(try Data(contentsOf: imageURL1), image1)
        XCTAssertEqual(try Data(contentsOf: imageURL2), image2)
    }

    func testWriteAttachmentsCleansUpBatchesOlderThanOneHour() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileStoreDirectory = directory.appendingPathComponent("attachments", isDirectory: true)

        var currentDate = Date()
        let attachmentFileStore = AttachmentFileStore(baseDirectory: fileStoreDirectory, now: { currentDate })
        let service = ClipboardService(pasteboard: testPasteboard, attachmentFileStore: attachmentFileStore)

        _ = service.writeAttachments([.image(makeTestPNGData())])
        let firstBatchDirectories = try FileManager.default.contentsOfDirectory(
            at: fileStoreDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(firstBatchDirectories.count, 1)

        // Advance virtual time by more than an hour and write a second batch;
        // the sweep that runs on this write should remove the first batch.
        currentDate = currentDate.addingTimeInterval(61 * 60)
        _ = service.writeAttachments([.image(makeTestPNGData())])

        let remainingDirectories = try FileManager.default.contentsOfDirectory(
            at: fileStoreDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(remainingDirectories.count, 1)
        XCTAssertNotEqual(remainingDirectories.first, firstBatchDirectories.first)
    }

    func testWriteTextAndAttachmentsWritesTextItemFirstThenFileItems() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: fileURL)

        let receipt = service.writeTextAndAttachments(text: "Some dictated text", attachments: [.file(fileURL)])
        XCTAssertNotNil(receipt)

        let items = try XCTUnwrap(testPasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].string(forType: .string), "Some dictated text")
        XCTAssertNil(items[0].string(forType: .fileURL))
        XCTAssertEqual(items[1].string(forType: .fileURL), fileURL.absoluteString)
    }

    func testWriteTextAndAttachmentsHandlesEmptyText() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: fileURL)

        let receipt = service.writeTextAndAttachments(text: "", attachments: [.file(fileURL)])
        XCTAssertNotNil(receipt)

        let items = try XCTUnwrap(testPasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].string(forType: .fileURL), fileURL.absoluteString)
    }

    // MARK: - Test helpers

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeTestPNGData() -> Data {
        guard let bitmap = NSBitmapImageRep(data: makeTestTIFFData()),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to build test PNG data")
            return Data()
        }
        return png
    }

    private func makeTestTIFFData() -> Data {
        let size = NSSize(width: 4, height: 4)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image.tiffRepresentation ?? Data()
    }

    private static func hasPNGSignature(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.starts(with: signature)
    }
}
