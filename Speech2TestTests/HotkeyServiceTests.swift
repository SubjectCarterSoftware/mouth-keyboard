import XCTest
import KeyboardShortcuts
@testable import Speech2Test

@MainActor
final class HotkeyServiceTests: XCTestCase {
    func testSingleTapArmsImmediately() {
        var armCount = 0
        let service = HotkeyService {
            armCount += 1
        }

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 1)
    }

    func testRepeatedSingleTapsArmEachTime() {
        var armCount = 0
        let service = HotkeyService {
            armCount += 1
        }

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 2)
    }

    func testDefaultActivationShortcutIsCommandShiftZ() {
        let shortcut = KeyboardShortcuts.getShortcut(for: .activate)

        XCTAssertEqual(shortcut?.key, .v)
        XCTAssertEqual(shortcut?.modifiers, [.control])
    }
}
