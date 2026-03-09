import AppKit
import XCTest
@testable import Speech2Text

final class ClipboardServiceTests: XCTestCase {

    var testPasteboard: NSPasteboard!
    var service: ClipboardService!

    override func setUp() {
        super.setUp()
        // Use a unique named pasteboard for isolation
        testPasteboard = NSPasteboard(name: .init("com.speech2test.test.\(UUID().uuidString)"))
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
}
