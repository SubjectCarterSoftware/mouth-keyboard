import XCTest
import KeyboardShortcuts
@testable import Speech2Test

final class HotkeyServiceTests: XCTestCase {
    func testDoubleTapWithinWindowArmsOnce() {
        var currentTime: CFAbsoluteTime = 100
        var armCount = 0
        let service = makeService(tapMode: .double, currentTime: &currentTime) {
            armCount += 1
        }

        XCTAssertTrue(service.handleKeyDown())

        currentTime = 100.2
        XCTAssertTrue(service.handleKeyDown())
        XCTAssertEqual(armCount, 1)
    }

    func testSingleTapInDoubleTapModeDoesNotArmWithinWindow() {
        var currentTime: CFAbsoluteTime = 100
        let didArm = expectation(description: "arm callback")
        didArm.isInverted = true
        let service = makeService(tapMode: .double, currentTime: &currentTime) {
            didArm.fulfill()
        }

        XCTAssertTrue(service.handleKeyDown())

        wait(for: [didArm], timeout: 0.4)
    }

    func testSingleTapModeArmsImmediately() {
        var currentTime: CFAbsoluteTime = 100
        var armCount = 0
        let service = makeService(tapMode: .single, currentTime: &currentTime) {
            armCount += 1
        }

        XCTAssertTrue(service.handleKeyDown())

        XCTAssertEqual(armCount, 1)
    }

    func testLateSecondTapStartsNewWindowWithoutArming() {
        var currentTime: CFAbsoluteTime = 100
        var armCount = 0
        let service = makeService(tapMode: .double, currentTime: &currentTime) {
            armCount += 1
        }

        XCTAssertTrue(service.handleKeyDown())

        currentTime = 100.4
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
        currentTime: inout CFAbsoluteTime,
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
            now: { currentTime }
        )
    }
}
