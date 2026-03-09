import XCTest
import KeyboardShortcuts
@testable import Speech2Text

@MainActor
final class HotkeyServiceTests: XCTestCase {
    func testSingleTapArmsImmediately() {
        var armCount = 0
        let service = HotkeyService(
            currentState: { .idle },
            onArm: {
                armCount += 1
            },
            now: { 0 }
        )

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 1)
    }

    func testRepeatedSingleTapsWithinMinimumIntervalArmOnlyOnce() {
        var armCount = 0
        var timestamps = [0.0, 0.1].makeIterator()
        let service = HotkeyService(
            minimumActivationInterval: 0.35,
            currentState: { .idle },
            onArm: {
                armCount += 1
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 1)
    }

    func testRepeatedSingleTapsAfterMinimumIntervalArmEachTime() {
        var armCount = 0
        var timestamps = [0.0, 0.5].makeIterator()
        let service = HotkeyService(
            minimumActivationInterval: 0.35,
            currentState: { .idle },
            onArm: {
                armCount += 1
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 2)
    }

    func testStopClearsRepeatGuard() {
        var armCount = 0
        var timestamps = [0.0, 0.1].makeIterator()
        let service = HotkeyService(
            minimumActivationInterval: 0.35,
            currentState: { .idle },
            onArm: {
                armCount += 1
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(service.handleKeyDown())
        service.stop()
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 2)
    }

    func testRepeatedSingleTapsWhileRecordingStillArmEachTime() {
        var armCount = 0
        var timestamps = [0.0, 0.1].makeIterator()
        let service = HotkeyService(
            minimumActivationInterval: 0.35,
            currentState: { .recording },
            onArm: {
                armCount += 1
            },
            now: {
                timestamps.next() ?? 0
            }
        )

        XCTAssertTrue(service.handleKeyDown())
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 2)
    }

    func testDefaultActivationShortcutIsControlV() {
        let shortcut = KeyboardShortcuts.getShortcut(for: .activate)

        XCTAssertEqual(shortcut?.key, .v)
        XCTAssertEqual(shortcut?.modifiers, [.control])
    }
}
