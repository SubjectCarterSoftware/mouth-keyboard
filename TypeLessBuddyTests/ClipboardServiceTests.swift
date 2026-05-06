import AppKit
import XCTest
@testable import TypeLessBuddy

final class ClipboardServiceTests: XCTestCase {

    var testPasteboard: NSPasteboard!
    var service: ClipboardService!

    override func setUp() {
        super.setUp()
        // Use a unique named pasteboard for isolation
        testPasteboard = NSPasteboard(name: .init("com.typelessbuddy.test.\(UUID().uuidString)"))
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
}
