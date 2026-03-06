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

        wait(for: [didArm], timeout: 0.4)
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

        clock.currentTime = 100.4
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 0)
    }

    func testDefaultActivationShortcutIsCommandShiftZ() {
        let shortcut = KeyboardShortcuts.getShortcut(for: .activate)

        XCTAssertEqual(shortcut?.key, .z)
        XCTAssertEqual(shortcut?.modifiers, [.command, .shift])
    }

    private func makeService(
        tapMode: TapMode,
        clock: TestClock,
        onArm: @escaping () -> Void
    ) -> HotkeyService {
        let suiteName = "HotkeyServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = ShellPreferences(userDefaults: defaults)
        preferences.tapMode = tapMode

        return HotkeyService(
            preferences: preferences,
            onArm: onArm,
            now: { clock.currentTime }
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
