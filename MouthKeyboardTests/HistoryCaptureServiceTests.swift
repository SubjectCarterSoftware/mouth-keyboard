import XCTest
@testable import TypeLessBuddy

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
