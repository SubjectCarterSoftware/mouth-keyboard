@testable import MouthKeyboard
import XCTest

final class ReplacementPackServiceTests: XCTestCase {
    private func pack(
        id: String,
        rules: [(originals: [String], replacement: String)]
    ) -> ReplacementPack {
        ReplacementPack(
            id: id,
            title: id,
            kind: .role,
            symbolName: "circle",
            subtitle: "",
            replacements: rules.map { WordReplacement(originals: $0.originals, replacement: $0.replacement) }
        )
    }

    func testEnablingInsertsRulesTaggedWithPackID() {
        let pack = pack(id: "p1", rules: [(["type script"], "TypeScript")])
        let result = ReplacementPackService.enabling(pack, in: .empty)

        XCTAssertEqual(result.enabledPackIDs, ["p1"])
        XCTAssertEqual(result.replacements.count, 1)
        XCTAssertEqual(result.replacements[0].replacement, "TypeScript")
        XCTAssertEqual(result.replacements[0].sourcePackIDs, ["p1"])
        XCTAssertTrue(result.replacements[0].isEnabled)
    }

    func testEnablingIsIdempotent() {
        let pack = pack(id: "p1", rules: [(["type script"], "TypeScript")])
        let once = ReplacementPackService.enabling(pack, in: .empty)
        let twice = ReplacementPackService.enabling(pack, in: once)

        XCTAssertEqual(twice.enabledPackIDs, ["p1"])
        XCTAssertEqual(twice.replacements.count, 1)
        XCTAssertEqual(twice.replacements[0].sourcePackIDs, ["p1"])
    }

    func testDisablingRemovesPackOnlyRules() {
        let pack = pack(id: "p1", rules: [(["type script"], "TypeScript")])
        let enabled = ReplacementPackService.enabling(pack, in: .empty)
        let disabled = ReplacementPackService.disabling(pack, in: enabled)

        XCTAssertTrue(disabled.enabledPackIDs.isEmpty)
        XCTAssertTrue(disabled.replacements.isEmpty)
    }

    func testRuleSharedByTwoPacksSurvivesDisablingOne() {
        let figmaRule: [(originals: [String], replacement: String)] = [(["fig ma", "figma"], "Figma")]
        let designer = pack(id: "designer", rules: figmaRule)
        let pm = pack(id: "pm", rules: figmaRule)

        var data = ReplacementPackService.enabling(designer, in: .empty)
        data = ReplacementPackService.enabling(pm, in: data)

        XCTAssertEqual(data.replacements.count, 1)
        XCTAssertEqual(Set(data.replacements[0].sourcePackIDs), ["designer", "pm"])

        let afterDisable = ReplacementPackService.disabling(designer, in: data)
        XCTAssertEqual(afterDisable.replacements.count, 1, "Rule should stay while pm keeps it alive")
        XCTAssertEqual(afterDisable.replacements[0].sourcePackIDs, ["pm"])
        XCTAssertEqual(afterDisable.enabledPackIDs, ["pm"])

        let afterBoth = ReplacementPackService.disabling(pm, in: afterDisable)
        XCTAssertTrue(afterBoth.replacements.isEmpty)
    }

    func testUserAuthoredRuleIsNeverRemovedOrRetagged() {
        let userRule = WordReplacement(originals: ["type script"], replacement: "TypeScript")
        let data = DictionaryData(replacements: [userRule])
        let pack = pack(id: "p1", rules: [(["type script"], "TypeScript")])

        let enabled = ReplacementPackService.enabling(pack, in: data)
        // The pack is "on" but the matching user rule stays untouched (no duplicate, no tag).
        XCTAssertEqual(enabled.enabledPackIDs, ["p1"])
        XCTAssertEqual(enabled.replacements.count, 1)
        XCTAssertTrue(enabled.replacements[0].sourcePackIDs.isEmpty)

        let disabled = ReplacementPackService.disabling(pack, in: enabled)
        XCTAssertEqual(disabled.replacements.count, 1, "User-authored rule must survive disable")
        XCTAssertTrue(disabled.replacements[0].sourcePackIDs.isEmpty)
    }

    func testLegacyDictionaryDataDecodesWithDefaults() throws {
        // A store written before vocabulary packs: no enabledPackIDs, and a
        // replacement with no sourcePackIDs field.
        let legacyJSON = """
        {
            "replacements": [
                {
                    "id": "00000000-0000-0000-0000-000000000001",
                    "originals": ["type script"],
                    "replacement": "TypeScript",
                    "isEnabled": true
                }
            ]
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(DictionaryData.self, from: data)

        XCTAssertEqual(decoded.enabledPackIDs, [])
        XCTAssertEqual(decoded.replacements.count, 1)
        XCTAssertEqual(decoded.replacements[0].sourcePackIDs, [])
        XCTAssertEqual(decoded.replacements[0].replacement, "TypeScript")
    }

    func testMatchingIsCaseInsensitiveAndOrderIndependent() {
        let existing = WordReplacement(
            originals: ["FIGMA", "fig ma"],
            replacement: "Figma",
            sourcePackIDs: ["other"]
        )
        let data = DictionaryData(replacements: [existing], enabledPackIDs: ["other"])
        let pack = pack(id: "designer", rules: [(["fig ma", "figma"], "figma")])

        let enabled = ReplacementPackService.enabling(pack, in: data)
        XCTAssertEqual(enabled.replacements.count, 1, "Should match the existing entry, not duplicate")
        XCTAssertEqual(Set(enabled.replacements[0].sourcePackIDs), ["other", "designer"])
    }
}
