import XCTest
@testable import MouthKeyboard

final class HistoryCaptureServiceTests: XCTestCase {
    private var currentDate = Date(timeIntervalSince1970: 1_716_390_645)

    func testSaveRawEntryCreatesTextFile() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "plain transcript",
                assistantOutput: nil
            ),
            configuration: HistoryConfiguration(
                isEnabled: true,
                folderPath: folderURL.path,
                storageLimitMB: 500
            )
        )

        let contents = try String(contentsOf: savedURL, encoding: .utf8)
        XCTAssertTrue(savedURL.path.hasPrefix(folderURL.path))
        XCTAssertEqual(savedURL.pathExtension, "txt")
        XCTAssertEqual(
            contents,
            """
            Created: \(headingTimestamp)
            Mode: Raw

            Raw transcription:
            plain transcript
            """
        )
    }

    func testSaveAssistantEntryIncludesAssistantSection() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "buddy rewrite this",
                assistantOutput: "Rewritten output"
            ),
            configuration: HistoryConfiguration(
                isEnabled: true,
                folderPath: folderURL.path,
                storageLimitMB: 500
            )
        )

        let contents = try String(contentsOf: savedURL, encoding: .utf8)
        XCTAssertEqual(
            contents,
            """
            Created: \(headingTimestamp)
            Mode: Assistant

            Raw transcription:
            buddy rewrite this

            Assistant output:
            Rewritten output
            """
        )
    }

    func testListEntriesReturnsNewestFirst() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(
            isEnabled: true,
            folderPath: folderURL.path,
            storageLimitMB: 500
        )

        _ = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "first", assistantOutput: nil),
            configuration: configuration
        )

        currentDate = currentDate.addingTimeInterval(5)

        _ = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "second", assistantOutput: "done"),
            configuration: configuration
        )

        let entries = try service.listEntries(configuration: configuration)
        XCTAssertEqual(entries.map(\.previewText), ["second", "first"])
        XCTAssertEqual(entries.map(\.mode), [.assistant, .raw])
    }

    func testSaveEntryPrunesOldestHistoryFilesWhenOverCap() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(
            isEnabled: true,
            folderPath: folderURL.path,
            storageLimitMB: 1
        )

        let firstText = String(repeating: "a", count: 700_000)
        let secondText = String(repeating: "b", count: 700_000)

        let firstURL = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: firstText, assistantOutput: nil),
            configuration: configuration
        )

        currentDate = currentDate.addingTimeInterval(5)

        let secondURL = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: secondText, assistantOutput: nil),
            configuration: configuration
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testPruningLeavesNonHistoryFilesUntouched() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(
            isEnabled: true,
            folderPath: folderURL.path,
            storageLimitMB: 1
        )
        let nonHistoryURL = folderURL.appendingPathComponent("keep-me.txt")
        try "manual file".write(to: nonHistoryURL, atomically: true, encoding: .utf8)

        _ = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: String(repeating: "a", count: 520_000),
                assistantOutput: nil
            ),
            configuration: configuration
        )
        currentDate = currentDate.addingTimeInterval(5)
        _ = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: String(repeating: "b", count: 700_000),
                assistantOutput: nil
            ),
            configuration: configuration
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: nonHistoryURL.path))
    }

    func testOversizedNewEntryStillSurvives() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(
            isEnabled: true,
            folderPath: folderURL.path,
            storageLimitMB: 1
        )

        let smallerURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: String(repeating: "a", count: 100_000),
                assistantOutput: nil
            ),
            configuration: configuration
        )

        currentDate = currentDate.addingTimeInterval(5)

        let oversizedURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: String(repeating: "z", count: 1_500_000),
                assistantOutput: nil
            ),
            configuration: configuration
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: smallerURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oversizedURL.path))
    }

    func testLoadEntryDetailSplitsRawAndAssistant() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "buddy rewrite this", assistantOutput: "Rewritten output"),
            configuration: configuration
        )

        let detail = try service.loadEntryDetail(at: savedURL)
        XCTAssertEqual(detail.mode, .assistant)
        XCTAssertEqual(detail.rawTranscription, "buddy rewrite this")
        XCTAssertEqual(detail.assistantOutput, "Rewritten output")
        XCTAssertEqual(detail.primaryText, "Rewritten output")
    }

    func testLoadEntryDetailRawOnly() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "plain transcript", assistantOutput: nil),
            configuration: configuration
        )

        let detail = try service.loadEntryDetail(at: savedURL)
        XCTAssertEqual(detail.mode, .raw)
        XCTAssertEqual(detail.rawTranscription, "plain transcript")
        XCTAssertNil(detail.assistantOutput)
        XCTAssertEqual(detail.primaryText, "plain transcript")
    }

    func testDeleteEntryRemovesFile() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "delete me", assistantOutput: nil),
            configuration: configuration
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))

        try service.deleteEntry(at: savedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path))
    }

    func testDeleteEntryRejectsNonHistoryFile() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let foreignURL = folderURL.appendingPathComponent("keep-me.txt")
        try "manual file".write(to: foreignURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try service.deleteEntry(at: foreignURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignURL.path))
    }

    func testDeleteAllEntriesLeavesNonHistoryFiles() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)
        let foreignURL = folderURL.appendingPathComponent("keep-me.txt")
        try "manual file".write(to: foreignURL, atomically: true, encoding: .utf8)

        _ = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "one", assistantOutput: nil),
            configuration: configuration
        )
        currentDate = currentDate.addingTimeInterval(5)
        _ = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "two", assistantOutput: nil),
            configuration: configuration
        )

        try service.deleteAllEntries(configuration: configuration)

        XCTAssertTrue(try service.listEntries(configuration: configuration).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignURL.path))
    }

    func testStorageUsageCountsHistoryFiles() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        XCTAssertEqual(try service.storageUsage(configuration: configuration), HistoryUsage(totalBytes: 0, entryCount: 0))

        _ = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "one", assistantOutput: nil),
            configuration: configuration
        )
        currentDate = currentDate.addingTimeInterval(5)
        _ = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "two", assistantOutput: nil),
            configuration: configuration
        )

        let usage = try service.storageUsage(configuration: configuration)
        XCTAssertEqual(usage.entryCount, 2)
        XCTAssertGreaterThan(usage.totalBytes, 0)
    }

    // MARK: - Screenshots

    func testSaveEntryWritesScreenshotsToSiblingFolder() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "with screenshots",
                assistantOutput: nil,
                screenshots: [pngData(byte: 0x01), pngData(byte: 0x02)]
            ),
            configuration: HistoryConfiguration(
                isEnabled: true,
                folderPath: folderURL.path,
                storageLimitMB: 500
            )
        )

        let contents = try String(contentsOf: savedURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("Screenshots: 2"))

        let screenshotsFolder = screenshotsFolderURL(for: savedURL)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotsFolder.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotsFolder.appendingPathComponent("1.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotsFolder.appendingPathComponent("2.png").path))
    }

    func testSaveEntryWithoutScreenshotsCreatesNoFolder() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "plain", assistantOutput: nil),
            configuration: HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)
        )

        let contents = try String(contentsOf: savedURL, encoding: .utf8)
        XCTAssertFalse(contents.contains("Screenshots:"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshotsFolderURL(for: savedURL).path))
    }

    func testEmptyTranscriptWithScreenshotsSavesAndPreviewsAsScreenshotCount() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        let twoScreenshotsURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "",
                assistantOutput: nil,
                screenshots: [pngData(byte: 0x01), pngData(byte: 0x02)]
            ),
            configuration: configuration
        )

        currentDate = currentDate.addingTimeInterval(5)

        let oneScreenshotURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "   ",
                assistantOutput: nil,
                screenshots: [pngData(byte: 0x03)]
            ),
            configuration: configuration
        )

        let entries = try service.listEntries(configuration: configuration)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.fileURL.lastPathComponent, $0) })

        XCTAssertEqual(byName[twoScreenshotsURL.lastPathComponent]?.previewText, "2 screenshots")
        XCTAssertEqual(byName[twoScreenshotsURL.lastPathComponent]?.screenshotCount, 2)
        XCTAssertEqual(byName[oneScreenshotURL.lastPathComponent]?.previewText, "1 screenshot")
        XCTAssertEqual(byName[oneScreenshotURL.lastPathComponent]?.screenshotCount, 1)
    }

    func testLoadEntryDetailReturnsScreenshotURLsInNumericOrder() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        let screenshots = (1...11).map { pngData(byte: UInt8($0)) }
        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "many shots", assistantOutput: nil, screenshots: screenshots),
            configuration: configuration
        )

        let detail = try service.loadEntryDetail(at: savedURL)
        XCTAssertEqual(
            detail.screenshotURLs.map(\.lastPathComponent),
            (1...11).map { "\($0).png" }
        )
    }

    func testDeleteEntryRemovesScreenshotsFolder() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "delete me", assistantOutput: nil, screenshots: [pngData(byte: 0x01)]),
            configuration: configuration
        )
        let screenshotsFolder = screenshotsFolderURL(for: savedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotsFolder.path))

        try service.deleteEntry(at: savedURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshotsFolder.path))
    }

    func testDeleteAllEntriesRemovesFoldersIncludingOrphans() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "one", assistantOutput: nil, screenshots: [pngData(byte: 0x01)]),
            configuration: configuration
        )
        let screenshotsFolder = screenshotsFolderURL(for: savedURL)

        let orphanFolder = folderURL.appendingPathComponent("History-orphan-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: orphanFolder, withIntermediateDirectories: true)
        try pngData(byte: 0x09).write(to: orphanFolder.appendingPathComponent("1.png"))

        try service.deleteAllEntries(configuration: configuration)

        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshotsFolder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanFolder.path))
    }

    func testStorageUsageIncludesImageBytesButEntryCountExcludesFolders() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        _ = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "one",
                assistantOutput: nil,
                screenshots: [Data(repeating: 0x01, count: 10_000)]
            ),
            configuration: configuration
        )

        let usage = try service.storageUsage(configuration: configuration)
        XCTAssertEqual(usage.entryCount, 1)
        XCTAssertGreaterThanOrEqual(usage.totalBytes, 10_000)
    }

    func testPruningDeletesOldEntryTextAndFolderTogetherCountingImageBytes() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 1)

        let firstURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "first",
                assistantOutput: nil,
                screenshots: [Data(repeating: 0x01, count: 700_000)]
            ),
            configuration: configuration
        )
        let firstScreenshotsFolder = screenshotsFolderURL(for: firstURL)

        currentDate = currentDate.addingTimeInterval(5)

        let secondURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "second",
                assistantOutput: nil,
                screenshots: [Data(repeating: 0x02, count: 700_000)]
            ),
            configuration: configuration
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstScreenshotsFolder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testListEntriesIgnoresScreenshotFolders() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        _ = try service.saveEntry(
            content: HistoryCaptureContent(rawTranscription: "one", assistantOutput: nil, screenshots: [pngData(byte: 0x01)]),
            configuration: configuration
        )

        let entries = try service.listEntries(configuration: configuration)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries.allSatisfy { $0.fileURL.pathExtension == "txt" })
    }

    // MARK: - Attached files

    func testSaveEntryWritesAttachedFileHeaderLines() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "with files",
                assistantOutput: nil,
                attachedFilePaths: ["/tmp/one.pdf", "/tmp/two.zip"]
            ),
            configuration: HistoryConfiguration(
                isEnabled: true,
                folderPath: folderURL.path,
                storageLimitMB: 500
            )
        )

        let contents = try String(contentsOf: savedURL, encoding: .utf8)
        XCTAssertEqual(
            contents,
            """
            Created: \(headingTimestamp)
            Mode: Raw
            Attached file: /tmp/one.pdf
            Attached file: /tmp/two.zip

            Raw transcription:
            with files
            """
        )

        let detail = try service.loadEntryDetail(at: savedURL)
        XCTAssertEqual(detail.attachedFilePaths, ["/tmp/one.pdf", "/tmp/two.zip"])
        XCTAssertEqual(detail.rawTranscription, "with files")

        let entries = try service.listEntries(configuration: HistoryConfiguration(
            isEnabled: true,
            folderPath: folderURL.path,
            storageLimitMB: 500
        ))
        XCTAssertEqual(entries.first?.attachedFileCount, 2)
    }

    func testSaveEntryWithScreenshotsAndAttachedFilesRoundTripsBoth() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "mixed attachments",
                assistantOutput: nil,
                screenshots: [pngData(byte: 0x01)],
                attachedFilePaths: ["/tmp/one.pdf"]
            ),
            configuration: configuration
        )

        let contents = try String(contentsOf: savedURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("Screenshots: 1"))
        XCTAssertTrue(contents.contains("Attached file: /tmp/one.pdf"))

        let detail = try service.loadEntryDetail(at: savedURL)
        XCTAssertEqual(detail.screenshotURLs.count, 1)
        XCTAssertEqual(detail.attachedFilePaths, ["/tmp/one.pdf"])

        let entries = try service.listEntries(configuration: configuration)
        XCTAssertEqual(entries.first?.screenshotCount, 1)
        XCTAssertEqual(entries.first?.attachedFileCount, 1)
    }

    func testEmptyTranscriptWithAttachmentsPreviewsCombinedCounts() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = HistoryConfiguration(isEnabled: true, folderPath: folderURL.path, storageLimitMB: 500)

        let fileOnlyURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "",
                assistantOutput: nil,
                attachedFilePaths: ["/tmp/one.pdf"]
            ),
            configuration: configuration
        )

        currentDate = currentDate.addingTimeInterval(5)

        let mixedURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "",
                assistantOutput: nil,
                screenshots: [pngData(byte: 0x01), pngData(byte: 0x02)],
                attachedFilePaths: ["/tmp/one.pdf"]
            ),
            configuration: configuration
        )

        currentDate = currentDate.addingTimeInterval(5)

        let twoFilesURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "",
                assistantOutput: nil,
                attachedFilePaths: ["/tmp/one.pdf", "/tmp/two.zip"]
            ),
            configuration: configuration
        )

        let entries = try service.listEntries(configuration: configuration)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.fileURL.lastPathComponent, $0) })

        XCTAssertEqual(byName[fileOnlyURL.lastPathComponent]?.previewText, "1 file")
        XCTAssertEqual(byName[mixedURL.lastPathComponent]?.previewText, "2 screenshots, 1 file")
        XCTAssertEqual(byName[twoFilesURL.lastPathComponent]?.previewText, "2 files")
    }

    func testAttachedFileHeaderLinesDoNotAffectRawAndAssistantParsing() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()

        let savedURL = try service.saveEntry(
            content: HistoryCaptureContent(
                rawTranscription: "buddy rewrite this",
                assistantOutput: "Rewritten output",
                attachedFilePaths: ["/tmp/one.pdf"]
            ),
            configuration: HistoryConfiguration(
                isEnabled: true,
                folderPath: folderURL.path,
                storageLimitMB: 500
            )
        )

        let detail = try service.loadEntryDetail(at: savedURL)
        XCTAssertEqual(detail.mode, .assistant)
        XCTAssertEqual(detail.rawTranscription, "buddy rewrite this")
        XCTAssertEqual(detail.assistantOutput, "Rewritten output")
        XCTAssertEqual(detail.attachedFilePaths, ["/tmp/one.pdf"])
    }

    private func pngData(byte: UInt8) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, byte])
    }

    private func screenshotsFolderURL(for fileURL: URL) -> URL {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(stem)-screenshots", isDirectory: true)
    }

    private var headingTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: currentDate)
    }

    private func makeService() -> HistoryCaptureService {
        HistoryCaptureService(now: { [self] in currentDate })
    }

    private func makeTemporaryDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryCaptureServiceTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }
}

/// Covers the "Copy with images" helper on `HistorySettingsViewModel` and the
/// row-indicator helper on `HistoryAttachmentIndicators` — both pure
/// functions pulled out of their views specifically so this logic doesn't
/// need a live SwiftUI hierarchy or the real clipboard to test.
final class HistoryAttachmentCopyHelpersTests: XCTestCase {
    func testAttachmentsForCopyOrdersScreenshotsBeforeFiles() {
        let screenshotURL = URL(fileURLWithPath: "/tmp/history/shot.png")
        let fileURL = URL(fileURLWithPath: "/tmp/history/report.pdf")
        let detail = HistoryEntryDetail(
            createdAt: nil,
            mode: .raw,
            rawTranscription: "hello",
            assistantOutput: nil,
            screenshotURLs: [screenshotURL],
            attachedFilePaths: [fileURL.path]
        )

        let attachments = HistorySettingsViewModel.attachmentsForCopy(from: detail, fileExists: { _ in true })

        XCTAssertEqual(attachments.count, 2)
        guard case .file(let firstURL) = attachments[0], case .file(let secondURL) = attachments[1] else {
            return XCTFail("Expected both attachments to be .file references")
        }
        XCTAssertEqual(firstURL, screenshotURL)
        XCTAssertEqual(secondURL, fileURL)
    }

    func testAttachmentsForCopySkipsMissingFiles() {
        let missingScreenshot = URL(fileURLWithPath: "/tmp/history/gone.png")
        let presentFile = URL(fileURLWithPath: "/tmp/history/present.pdf")
        let missingFile = URL(fileURLWithPath: "/tmp/history/missing.pdf")
        let detail = HistoryEntryDetail(
            createdAt: nil,
            mode: .raw,
            rawTranscription: "hello",
            assistantOutput: nil,
            screenshotURLs: [missingScreenshot],
            attachedFilePaths: [presentFile.path, missingFile.path]
        )

        let attachments = HistorySettingsViewModel.attachmentsForCopy(from: detail) { path in
            path == presentFile.path
        }

        XCTAssertEqual(attachments.count, 1)
        guard case .file(let url) = attachments.first else {
            return XCTFail("Expected a .file attachment")
        }
        XCTAssertEqual(url, presentFile)
    }

    func testAttachmentsForCopyIsEmptyWhenNothingCollected() {
        let detail = HistoryEntryDetail(createdAt: nil, mode: .raw, rawTranscription: "hello", assistantOutput: nil)

        let attachments = HistorySettingsViewModel.attachmentsForCopy(from: detail, fileExists: { _ in true })

        XCTAssertTrue(attachments.isEmpty)
    }

    func testHistoryAttachmentIndicatorsIncludesBothWhenBothCountsArePositive() {
        let indicators = HistoryAttachmentIndicators.indicators(screenshotCount: 2, attachedFileCount: 1)

        XCTAssertEqual(
            indicators,
            [
                HistoryAttachmentIndicator(systemImage: "camera.fill", count: 2),
                HistoryAttachmentIndicator(systemImage: "paperclip", count: 1),
            ]
        )
    }

    func testHistoryAttachmentIndicatorsOmitsZeroCounts() {
        XCTAssertEqual(
            HistoryAttachmentIndicators.indicators(screenshotCount: 0, attachedFileCount: 3),
            [HistoryAttachmentIndicator(systemImage: "paperclip", count: 3)]
        )
        XCTAssertEqual(
            HistoryAttachmentIndicators.indicators(screenshotCount: 5, attachedFileCount: 0),
            [HistoryAttachmentIndicator(systemImage: "camera.fill", count: 5)]
        )
        XCTAssertEqual(
            HistoryAttachmentIndicators.indicators(screenshotCount: 0, attachedFileCount: 0),
            []
        )
    }
}
