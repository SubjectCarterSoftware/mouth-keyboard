@testable import MouthKeyboard
import XCTest

final class TextReplacementEngineTests: XCTestCase {
    func testBasicReplacement() {
        let replacements = [
            WordReplacement(originals: ["gonna"], replacement: "going to"),
        ]
        let result = TextReplacementEngine.applyReplacements(to: "I'm gonna go", replacements: replacements)
        XCTAssertEqual(result, "I'm going to go")
    }

    func testCaseInsensitiveMatching() {
        let replacements = [
            WordReplacement(originals: ["gonna"], replacement: "going to"),
        ]
        XCTAssertEqual(
            TextReplacementEngine.applyReplacements(to: "GONNA do it", replacements: replacements),
            "going to do it"
        )
    }

    func testWordBoundaries() {
        let replacements = [
            WordReplacement(originals: ["go"], replacement: "leave"),
        ]
        let result = TextReplacementEngine.applyReplacements(to: "let's go to google", replacements: replacements)
        XCTAssertEqual(result, "let's leave to google")
    }

    func testLongestFirstPriority() {
        let replacements = [
            WordReplacement(originals: ["go"], replacement: "leave"),
            WordReplacement(originals: ["going to"], replacement: "planning to"),
        ]
        let result = TextReplacementEngine.applyReplacements(to: "I'm going to go", replacements: replacements)
        XCTAssertEqual(result, "I'm planning to leave")
    }

    func testMultipleOriginals() {
        let replacements = [
            WordReplacement(originals: ["gonna", "gona", "gunna"], replacement: "going to"),
        ]
        XCTAssertEqual(
            TextReplacementEngine.applyReplacements(to: "I'm gonna gona gunna", replacements: replacements),
            "I'm going to going to going to"
        )
    }

    func testDisabledReplacementIsSkipped() {
        let replacements = [
            WordReplacement(originals: ["gonna"], replacement: "going to", isEnabled: false),
        ]
        let result = TextReplacementEngine.applyReplacements(to: "I'm gonna go", replacements: replacements)
        XCTAssertEqual(result, "I'm gonna go")
    }

    func testEmptyTextReturnsEmpty() {
        let replacements = [
            WordReplacement(originals: ["gonna"], replacement: "going to"),
        ]
        XCTAssertEqual(TextReplacementEngine.applyReplacements(to: "", replacements: replacements), "")
    }

    func testNoReplacementsReturnsOriginal() {
        let result = TextReplacementEngine.applyReplacements(to: "hello world", replacements: [])
        XCTAssertEqual(result, "hello world")
    }

    func testSpecialRegexCharsInOriginals() {
        let replacements = [
            WordReplacement(originals: ["c++"], replacement: "C Plus Plus"),
        ]
        let result = TextReplacementEngine.applyReplacements(to: "I write c++ code", replacements: replacements)
        XCTAssertEqual(result, "I write C Plus Plus code")
    }

    func testMultipleReplacementsInSameText() {
        let replacements = [
            WordReplacement(originals: ["john"], replacement: "John"),
            WordReplacement(originals: ["gonna"], replacement: "going to"),
        ]
        let result = TextReplacementEngine.applyReplacements(to: "tell john I'm gonna be late", replacements: replacements)
        XCTAssertEqual(result, "tell John I'm going to be late")
    }

    func testShortcutExpansion() {
        let replacements = [
            WordReplacement(originals: ["sig1"], replacement: "Best regards,\nEli Carter\nSoftware Engineer"),
        ]
        let result = TextReplacementEngine.applyReplacements(to: "end with sig1", replacements: replacements)
        XCTAssertEqual(result, "end with Best regards,\nEli Carter\nSoftware Engineer")
    }

    func testEmptyOriginalsArrayIsIgnored() {
        let entry = WordReplacement(originals: ["", "  "], replacement: "something")
        XCTAssertTrue(entry.originals.isEmpty)
        let result = TextReplacementEngine.applyReplacements(to: "hello", replacements: [entry])
        XCTAssertEqual(result, "hello")
    }
}
