import XCTest
@testable import Speech2Text

final class LLMRewriteServiceIntegrationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        guard ProcessInfo.processInfo.environment["ENABLE_LLM_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set ENABLE_LLM_INTEGRATION_TESTS=1 to run real-model rewrite tests.")
        }
    }

    /// Exercises every built-in (non-passthrough) mode against the real MLX/Qwen path and
    /// asserts that each returns trimmed, non-empty output.
    func testRewritesAllBuiltInModes() async throws {
        let service = LLMRewriteService()

        let inputs: [ConvertMode: String] = [
            .cleanEnglish: "um so I was thinking we should uh fix the bug before the deadline",
            .email: "I want to follow up on the meeting we had yesterday about the roadmap",
            .slack: "hey can we sync tomorrow morning on the project status and blockers",
            .teams: "need to discuss the deployment timeline with the team before end of week",
        ]

        for (mode, input) in inputs {
            let result = try await service.rewrite(body: input, mode: mode)
            XCTAssertFalse(
                result.isEmpty,
                "Expected non-empty rewrite for mode \(mode.rawValue)"
            )
            XCTAssertEqual(
                result,
                result.trimmingCharacters(in: .whitespacesAndNewlines),
                "Expected trimmed output for mode \(mode.rawValue)"
            )
        }
    }

    /// Uses the loader seam from Plan 01 to count actual model-load invocations.
    /// Two sequential rewrites on the same service instance must trigger exactly one load.
    func testRealRewriteReusesLoadedModelOnSecondCall() async throws {
        let loadCounter = IntegrationLoadCounter()

        let service = LLMRewriteService(
            loader: { hub in
                await loadCounter.increment()
                return try await LLMRewriteService.defaultLoader(hub: hub)
            }
        )

        let input = "keep the tests fast and the builds green"
        _ = try await service.rewrite(body: input, mode: .cleanEnglish)
        _ = try await service.rewrite(body: input, mode: .cleanEnglish)

        let count = await loadCounter.value()
        XCTAssertEqual(count, 1, "Expected model loaded once; was loaded \(count) times")
    }
}

private actor IntegrationLoadCounter {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}
