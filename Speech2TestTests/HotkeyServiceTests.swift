import XCTest
import KeyboardShortcuts
@testable import Speech2Test

@MainActor
final class HotkeyServiceTests: XCTestCase {
    func testDoubleTapWithinWindowArmsOnce() {
        let clock = TestClock(currentTime: 100)
        var armCount = 0
        let service = makeService(tapMode: .double, clock: clock) {
            armCount += 1
        }

        XCTAssertTrue(service.handleKeyDown())

        clock.currentTime = 100.2
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 1)
    }

    func testSingleTapInDoubleTapModeDoesNotArmWithinWindow() {
        let clock = TestClock(currentTime: 100)
        let didArm = expectation(description: "arm callback")
        didArm.isInverted = true
        let service = makeService(tapMode: .double, clock: clock) {
            didArm.fulfill()
        }

        XCTAssertTrue(service.handleKeyDown())

        wait(for: [didArm], timeout: 0.6)
    }

    func testSingleTapModeArmsImmediately() {
        let clock = TestClock(currentTime: 100)
        var armCount = 0
        let service = makeService(tapMode: .single, clock: clock) {
            armCount += 1
        }

        XCTAssertTrue(service.handleKeyDown())

        XCTAssertEqual(armCount, 1)
    }

    func testLateSecondTapStartsNewWindowWithoutArming() {
        let clock = TestClock(currentTime: 100)
        var armCount = 0
        let service = makeService(tapMode: .double, clock: clock) {
            armCount += 1
        }

        XCTAssertTrue(service.handleKeyDown())

        clock.currentTime = 100.6
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 0)
    }

    func testDefaultActivationShortcutIsCommandShiftZ() {
        let shortcut = KeyboardShortcuts.getShortcut(for: .activate)

        XCTAssertEqual(shortcut?.key, .v)
        XCTAssertEqual(shortcut?.modifiers, [.control])
    }

    private func makeService(
        tapMode: TapMode,
        clock: TestClock,
        onArm: @escaping () -> Void
    ) -> HotkeyService {
        return HotkeyService(
            onArm: onArm,
            now: { clock.currentTime },
            tapModeOverride: tapMode
        )
    }
}

@MainActor
private final class TestClock {
    var currentTime: CFAbsoluteTime

    init(currentTime: CFAbsoluteTime) {
        self.currentTime = currentTime
    }
}
