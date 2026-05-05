import XCTest
@testable import TypeLessBuddy

final class LLMRewriteServiceIntegrationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_MODEL_INTEGRATION_TESTS"] == "1",
            "Skipping real MLX model tests. Set RUN_MODEL_INTEGRATION_TESTS=1 to enable."
        )
    }

    /// Exercises rewrite with user-provided instructions against the real MLX/Qwen path and
    /// asserts that it returns trimmed, non-empty output.
    func testRewriteWithInstructionsProducesNonEmptyOutput() async throws {
        let service = LLMRewriteService()

        let result = try await service.rewrite(
            body: "um so I was thinking we should uh fix the bug before the deadline",
            instructions: "Remove filler words and fix grammar. Return only the cleaned text."
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result, result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Uses the loader seam to count actual model-load invocations.
    /// Two sequential rewrites on the same service instance must trigger exactly one load.
    func testRealRewriteReusesLoadedModelOnSecondCall() async throws {
        let loadCounter = IntegrationLoadCounter()

        let defaultLoader = LLMRewriteService.makeDefaultLoader(tier: .standard2B)
        let service = LLMRewriteService(
            loader: { hub in
                await loadCounter.increment()
                return try await defaultLoader(hub)
            }
        )

        let input = "keep the tests fast and the builds green"
        _ = try await service.rewrite(body: input, instructions: "Clean up grammar.")
        _ = try await service.rewrite(body: input, instructions: "Clean up grammar.")

        let count = await loadCounter.value()
        XCTAssertEqual(count, 1, "Expected model loaded once; was loaded \(count) times")
    }

    func testRewriteWith4BTierProducesNonEmptyOutput() async throws {
        let service = LLMRewriteService(tier: .standard4B)

        let result = try await service.rewrite(
            body: "weekly product update",
            instructions: "Turn this into a short executive summary."
        )

        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result, result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testRewriteWith4BTierUsingDirectHubLoaderProducesNonEmptyOutput() async throws {
        let service = LLMRewriteService(
            tier: .standard4B,
            loader: LLMRewriteService.makeDefaultLoader(tier: .standard4B)
        )

        let result = try await service.rewrite(
            body: "weekly product update",
            instructions: "Turn this into a short executive summary."
        )

        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result, result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

}

private actor IntegrationLoadCounter {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}
