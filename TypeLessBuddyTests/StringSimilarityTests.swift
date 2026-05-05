import XCTest
@testable import TypeLessBuddy

/// Reference pair tests for the Jaro-Winkler implementation.
/// All tests are RED until Plan 02 provides the real jaroWinkler implementation.
/// The stub returns 0.0 for all inputs, causing assertion failures below.
final class StringSimilarityTests: XCTestCase {

    // MARK: - Identity Cases

    func testIdenticalStringsReturnOne() {
        // Identical strings must score 1.0
        XCTAssertEqual(StringSimilarity.jaroWinkler("action items", "action items"), 1.0, accuracy: 0.001)
    }

    func testBothEmptyStringsReturnZero() {
        // Both empty → 0.0 (no similarity to compute)
        XCTAssertEqual(StringSimilarity.jaroWinkler("", ""), 0.0, accuracy: 0.001)
    }

    // MARK: - High-Similarity Pairs (short word insertion)

    func testMakeThisAnEmailVsMakeThisEmail() {
        // One word difference ("an") — should score >= 0.90
        let score = StringSimilarity.jaroWinkler("make this an email", "make this email")
        XCTAssertGreaterThanOrEqual(score, 0.90,
            "Expected jaroWinkler('make this an email', 'make this email') >= 0.90, got \(score)")
    }

    // MARK: - Medium-Similarity Pairs (keyword present, phrase shorter)

    func testEmailModeVsEmail() {
        // "email mode" vs "email" — keyword present but terse; should score >= 0.70
        let score = StringSimilarity.jaroWinkler("email mode", "email")
        XCTAssertGreaterThanOrEqual(score, 0.70,
            "Expected jaroWinkler('email mode', 'email') >= 0.70, got \(score)")
    }

    func testActionItemsVsActionItems() {
        // Identical multi-word string — must score 1.0
        let score = StringSimilarity.jaroWinkler("action items", "action items")
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    // MARK: - Low-Similarity Pairs (very different strings)

    func testConvertToSlackVsSlack() {
        // Long phrase vs single word — dissimilar; should score < 0.70
        let score = StringSimilarity.jaroWinkler("convert to slack", "slack")
        XCTAssertLessThan(score, 0.70,
            "Expected jaroWinkler('convert to slack', 'slack') < 0.70, got \(score)")
    }

    func testCompletelyUnrelatedStrings() {
        // "hello" vs "xylophone" — low similarity; standard Jaro-Winkler gives ~0.54 (two chars in common: l, o)
        let score = StringSimilarity.jaroWinkler("hello", "xylophone")
        XCTAssertLessThan(score, 0.6,
            "Expected jaroWinkler('hello', 'xylophone') < 0.6, got \(score)")
    }
}
