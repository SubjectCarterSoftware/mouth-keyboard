import XCTest
@testable import Speech2Text

@MainActor
final class HoldKeyDisplayFormatterTests: XCTestCase {
    // Modifier-only keys
    func testRightOptionKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 61, modifiers: 0), "⌥")
    }

    func testLeftOptionKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 58, modifiers: 0), "⌥")
    }

    func testLeftCommandKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 55, modifiers: 0), "⌘")
    }

    func testRightCommandKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 54, modifiers: 0), "⌘")
    }

    func testLeftShiftKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 56, modifiers: 0), "⇧")
    }

    func testRightShiftKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 60, modifiers: 0), "⇧")
    }

    func testLeftControlKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 59, modifiers: 0), "⌃")
    }

    func testRightControlKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 62, modifiers: 0), "⌃")
    }

    func testFnKey() {
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 63, modifiers: 0), "fn")
    }

    // Regular key with modifier
    func testControlV() {
        // keyCode 9 = V, modifiers bit 18 = .control
        let controlBit: UInt = 1 << 18
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 9, modifiers: controlBit), "⌃V")
    }

    func testCommandShiftS() {
        // keyCode 1 = S, modifiers bit 20 = .command, bit 17 = .shift
        let mods: UInt = (1 << 20) | (1 << 17)
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 1, modifiers: mods), "⇧⌘S")
    }

    // Unknown key code should not crash and return non-empty string
    func testUnknownKeyCodeFallsBack() {
        let result = HoldKeyDisplayFormatter.symbol(keyCode: 999, modifiers: 0)
        XCTAssertEqual(result, "?")
    }

    // keyCharacter is used by StatusMenuView for tap shortcut hints
    func testKeyCharacterForV() {
        XCTAssertEqual(HoldKeyDisplayFormatter.keyCharacter(for: 9), "V")
    }

    func testKeyCharacterForSpace() {
        XCTAssertEqual(HoldKeyDisplayFormatter.keyCharacter(for: 49), "Space")
    }

    func testKeyCharacterForUnknown() {
        XCTAssertEqual(HoldKeyDisplayFormatter.keyCharacter(for: 999), "?")
    }

    func testModifierOnlyKeyIgnoresBitmask() {
        // Modifier-only keyCode paths return the bare symbol regardless of the bitmask
        let optionBit: UInt = 1 << 19
        XCTAssertEqual(HoldKeyDisplayFormatter.symbol(keyCode: 61, modifiers: optionBit), "⌥")
    }
}
