@testable import TypeLessBuddy
import XCTest

final class ReplacementPackCatalogTests: XCTestCase {
    func testPackIDsAreUnique() {
        let ids = ReplacementPackCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Pack IDs must be unique")
    }

    func testRolesReturnsOnlyRolePacks() {
        XCTAssertFalse(ReplacementPackCatalog.roles.isEmpty)
        XCTAssertTrue(ReplacementPackCatalog.roles.allSatisfy { $0.kind == .role })
    }

    func testPackLookupByID() {
        for pack in ReplacementPackCatalog.all {
            XCTAssertEqual(ReplacementPackCatalog.pack(id: pack.id)?.id, pack.id)
        }
        XCTAssertNil(ReplacementPackCatalog.pack(id: "does.not.exist"))
    }

    func testEveryRuleHasContent() {
        for pack in ReplacementPackCatalog.all {
            XCTAssertFalse(pack.title.isEmpty, "\(pack.id) missing title")
            XCTAssertFalse(pack.symbolName.isEmpty, "\(pack.id) missing symbol")
            for rule in pack.replacements {
                XCTAssertFalse(rule.originals.isEmpty, "\(pack.id) has a rule with no originals")
                XCTAssertFalse(rule.replacement.isEmpty, "\(pack.id) has a rule with empty replacement")
                XCTAssertFalse(
                    rule.originals.contains(where: { $0.isEmpty }),
                    "\(pack.id) has an empty original token"
                )
            }
        }
    }

    /// The replacement engine matches case-insensitively on whole words, so a
    /// single-token original that is a common English word would clobber ordinary
    /// speech. Guard against any such token leaking into the catalog.
    func testNoAmbiguousStandaloneEnglishWords() {
        let forbidden: Set<String> = ["react", "go", "rust", "swift", "pandas", "jupiter", "jason", "vue"]
        for pack in ReplacementPackCatalog.all {
            for rule in pack.replacements {
                for original in rule.originals {
                    let token = original.lowercased()
                    // Multi-word originals are unambiguous; only single tokens are risky.
                    guard !token.contains(" ") else { continue }
                    XCTAssertFalse(
                        forbidden.contains(token),
                        "\(pack.id) contains ambiguous standalone word '\(original)'"
                    )
                }
            }
        }
    }
}
