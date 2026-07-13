import XCTest
@testable import MouthKeyboard

final class NoteCaptureServiceTests: XCTestCase {
    private lazy var fixedDate = Date(timeIntervalSince1970: 1_716_390_645)

    func testSaveNewFileCreatesMarkdownNote() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = AssistantNoteConfiguration(
            mode: .newFile,
            folderPath: folderURL.path,
            appendFilePath: ""
        )
        let content = NoteCaptureContent(
            title: "Weekly planning",
            rawTranscription: "capture this planning update",
            assistantOutput: "- Finish the release checklist"
        )

        let savedURL = try service.saveNote(content: content, configuration: configuration)
        let contents = try String(contentsOf: savedURL, encoding: .utf8)

        XCTAssertTrue(savedURL.path.hasPrefix(folderURL.path))
        XCTAssertEqual(savedURL.pathExtension, "md")
        XCTAssertEqual(savedURL.lastPathComponent, "Weekly planning.md")
        XCTAssertEqual(
            contents,
            """
            # Weekly planning

            *Created: \(headingTimestamp)*

            ## Raw transcription

            capture this planning update

            ## Assistant output

            - Finish the release checklist
            """
        )
    }

    func testSaveNewFileUsesUniqueFilenameWhenTimestampPathAlreadyExists() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let existingURL = folderURL
            .appendingPathComponent("Note-\(fileNameTimestamp)")
            .appendingPathExtension("md")
        try "Existing".write(to: existingURL, atomically: true, encoding: .utf8)

        let configuration = AssistantNoteConfiguration(
            mode: .newFile,
            folderPath: folderURL.path,
            appendFilePath: ""
        )
        let content = NoteCaptureContent(
            title: nil,
            rawTranscription: "Captured output",
            assistantOutput: nil
        )

        let savedURL = try service.saveNote(content: content, configuration: configuration)

        XCTAssertEqual(savedURL.lastPathComponent, "Note-\(fileNameTimestamp)-1.md")
    }

    func testSaveNewFileIncludesReferencedContextsBetweenRawAndAssistantSections() throws {
        let folderURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = AssistantNoteConfiguration(
            mode: .newFile,
            folderPath: folderURL.path,
            appendFilePath: ""
        )
        let content = NoteCaptureContent(
            title: "Context capture",
            rawTranscription: "make a note of this selected text",
            referencedContexts: [
                NoteCaptureReferencedContext(
                    title: "Selected text",
                    content: "Original highlighted paragraph."
                ),
                NoteCaptureReferencedContext(
                    title: "Clipboard text",
                    content: "Copied supporting detail."
                ),
            ],
            assistantOutput: "Polished combined summary."
        )

        let savedURL = try service.saveNote(content: content, configuration: configuration)
        let contents = try String(contentsOf: savedURL, encoding: .utf8)

        XCTAssertEqual(
            contents,
            """
            # Context capture

            *Created: \(headingTimestamp)*

            ## Raw transcription

            make a note of this selected text

            ## Selected text

            Original highlighted paragraph.

            ## Clipboard text

            Copied supporting detail.

            ## Assistant output

            Polished combined summary.
            """
        )
        XCTAssertEqual(savedURL.lastPathComponent, "Context capture.md")
    }

    func testAppendToFileCreatesMissingFile() throws {
        let directoryURL = makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("notes.md")
        let service = makeService()
        let configuration = AssistantNoteConfiguration(
            mode: .appendToFile,
            folderPath: "",
            appendFilePath: fileURL.path
        )
        let content = NoteCaptureContent(
            title: nil,
            rawTranscription: "Captured output",
            assistantOutput: nil
        )

        let savedURL = try service.saveNote(content: content, configuration: configuration)
        let contents = try String(contentsOf: savedURL, encoding: .utf8)

        XCTAssertEqual(savedURL, fileURL)
        XCTAssertEqual(
            contents,
            """
            ## Note - \(headingTimestamp)

            *Created: \(headingTimestamp)*

            ### Raw transcription

            Captured output
            """
        )
    }

    func testAppendToFileAppendsWithSpacing() throws {
        let directoryURL = makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("notes.md")
        try "Existing entry".write(to: fileURL, atomically: true, encoding: .utf8)
        let service = makeService()
        let configuration = AssistantNoteConfiguration(
            mode: .appendToFile,
            folderPath: "",
            appendFilePath: fileURL.path
        )
        let content = NoteCaptureContent(
            title: "Action items",
            rawTranscription: "turn this into action items",
            assistantOutput: "- Follow up with design"
        )

        _ = try service.saveNote(content: content, configuration: configuration)
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(
            contents,
            """
            Existing entry

            ## Action items

            *Created: \(headingTimestamp)*

            ### Raw transcription

            turn this into action items

            ### Assistant output

            - Follow up with design
            """
        )
    }

    func testSaveNoteThrowsMissingDestinationWhenConfigurationIsIncomplete() {
        let service = makeService()
        let configuration = AssistantNoteConfiguration(
            mode: .newFile,
            folderPath: "",
            appendFilePath: ""
        )
        let content = NoteCaptureContent(
            title: nil,
            rawTranscription: "Captured output",
            assistantOutput: nil
        )

        XCTAssertThrowsError(try service.saveNote(content: content, configuration: configuration)) { error in
            XCTAssertEqual(error as? NoteCaptureError, .missingDestination)
        }
    }

    func testAppendToFileThrowsInvalidDestinationWhenTargetIsDirectory() throws {
        let directoryURL = makeTemporaryDirectory()
        let service = makeService()
        let configuration = AssistantNoteConfiguration(
            mode: .appendToFile,
            folderPath: "",
            appendFilePath: directoryURL.path
        )
        let content = NoteCaptureContent(
            title: nil,
            rawTranscription: "Captured output",
            assistantOutput: nil
        )

        XCTAssertThrowsError(try service.saveNote(content: content, configuration: configuration)) { error in
            guard case .invalidDestination(_) = error as? NoteCaptureError else {
                return XCTFail("Expected invalidDestination, got \(error)")
            }
        }
    }

    private var headingTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: fixedDate)
    }

    private var fileNameTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        return formatter.string(from: fixedDate)
    }

    private func makeService() -> NoteCaptureService {
        NoteCaptureService(now: { [self] in fixedDate })
    }

    private func makeTemporaryDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteCaptureServiceTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directoryURL
    }
}
