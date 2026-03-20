import XCTest
@testable import Speech2Text

final class TriggerAliasNormalizerTests: XCTestCase {
    func testNormalizeLowercasesAndTrimsAliases() {
        let normalized = TriggerAliasNormalizer.normalize(["  Zeus  ", " ATLAS "])

        XCTAssertEqual(normalized, ["zeus", "atlas"])
    }

    func testNormalizeCollapsesInternalWhitespaceForMultiWordValues() {
        let normalized = TriggerAliasNormalizer.normalize(["  assistant     zeus  "])

        XCTAssertEqual(normalized, ["assistant zeus"])
    }

    func testNormalizeDeduplicatesByPostNormalizationValue() {
        let normalized = TriggerAliasNormalizer.normalize(["Zeus", " zeus ", "ZEUS"])

        XCTAssertEqual(normalized, ["zeus"])
    }

    func testNormalizeRejectsValuesShorterThanTwoCharactersAfterNormalization() {
        let normalized = TriggerAliasNormalizer.normalize(["a", " z ", "  "])

        XCTAssertEqual(normalized, [])
    }

    func testNormalizeKeepsValidMultiWordAliases() {
        let normalized = TriggerAliasNormalizer.normalize(["ai assistant", "hello atlas"])

        XCTAssertEqual(normalized, ["ai assistant", "hello atlas"])
    }
}
