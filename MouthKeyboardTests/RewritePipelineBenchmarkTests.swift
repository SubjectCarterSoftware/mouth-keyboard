import XCTest
@testable import MouthKeyboard

/// Opt-in benchmark suite for the rewrite pipeline under realistic deterministic
/// external-context loads.
///
/// Gate: set RUN_REWRITE_BENCHMARK_TESTS=1 to run. Never runs in CI or normal development.
final class RewritePipelineBenchmarkTests: XCTestCase {

    private let service = LocalRewriteService.shared
    private static let wordLimit = RewriteModelLimits.compute(
        tier: .standard2B,
        ramProfile: .current
    ).promptWordLimit

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_REWRITE_BENCHMARK_TESTS"] == "1",
            "Rewrite pipeline benchmarks skipped. Set RUN_REWRITE_BENCHMARK_TESTS=1 to run."
        )
    }

    func testBenchmark_RewritePipeline() async throws {
        printSectionHeader("Scenario 1: Clipboard-Only")

        await runAndPrint(
            label: "Small (~70-word clipboard)",
            targetMode: .clipboard,
            dictated: "rewrite this to sound more formal and polished for an executive update",
            selectedText: nil,
            clipboardText: Fixtures.clipboardSmall
        )
        await runAndPrint(
            label: "Medium (~400-word clipboard)",
            targetMode: .clipboard,
            dictated: "clean up the writing in this section, fix any grammar issues, and make it ready to send to the product team",
            selectedText: nil,
            clipboardText: Fixtures.clipboardMedium
        )
        await runAndPrint(
            label: "Large (~1000-word clipboard)",
            targetMode: .clipboard,
            dictated: "tighten this document section significantly, cut out any redundancy, and aim for roughly two thirds of the original length",
            selectedText: nil,
            clipboardText: Fixtures.clipboardLarge
        )

        printSectionHeader("Scenario 2: Selected-Text-Only")

        await runAndPrint(
            label: "Small (~80-word selection)",
            targetMode: .selectedText,
            dictated: "fix the grammar, remove the hedging language, and make this more confident and direct",
            selectedText: Fixtures.selectedSmall,
            clipboardText: nil
        )
        await runAndPrint(
            label: "Medium (~350-word selection)",
            targetMode: .selectedText,
            dictated: "rewrite this draft to be more compelling, cut it by about a quarter, and tighten the argument",
            selectedText: Fixtures.selectedMedium,
            clipboardText: nil
        )
        await runAndPrint(
            label: "Large (~900-word selection)",
            targetMode: .selectedText,
            dictated: "clean this up, remove the repetitive sections, and make it more direct without losing the key points",
            selectedText: Fixtures.selectedLarge,
            clipboardText: nil
        )
    }
}

extension RewritePipelineBenchmarkTests {

    private struct BenchmarkResult {
        let label: String
        let targetMode: AssistantContextTargetMode
        let promptWordCount: Int
        let wordLimitExceeded: Bool
        let latencySeconds: Double?
        let outputWordCount: Int
        let output: String
        let error: String?
    }

    private func runAndPrint(
        label: String,
        targetMode: AssistantContextTargetMode,
        dictated: String,
        selectedText: String?,
        clipboardText: String?
    ) async {
        let result = await runBenchmark(
            label: label,
            targetMode: targetMode,
            dictated: dictated,
            selectedText: selectedText,
            clipboardText: clipboardText
        )
        printResult(result)
    }

    private func runBenchmark(
        label: String,
        targetMode: AssistantContextTargetMode,
        dictated: String,
        selectedText: String?,
        clipboardText: String?
    ) async -> BenchmarkResult {
        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: dictated,
            selectedText: selectedText,
            clipboardText: clipboardText,
            routingDecision: AssistantContextRoutingDecision(
                targetMode: targetMode,
                decisionSource: .modelClassifier
            )
        )
        let promptWordCount = wordCount(body)

        guard promptWordCount <= Self.wordLimit else {
            return BenchmarkResult(
                label: label,
                targetMode: targetMode,
                promptWordCount: promptWordCount,
                wordLimitExceeded: true,
                latencySeconds: nil,
                outputWordCount: 0,
                output: "",
                error: nil
            )
        }

        let systemPrompt = LocalRewriteService.resolveAssistantSystemPrompt(assistantName: "Assistant")
        let start = Date()

        do {
            let output = try await service.generate(prompt: body, systemPrompt: systemPrompt)
            return BenchmarkResult(
                label: label,
                targetMode: targetMode,
                promptWordCount: promptWordCount,
                wordLimitExceeded: false,
                latencySeconds: Date().timeIntervalSince(start),
                outputWordCount: wordCount(output),
                output: output,
                error: nil
            )
        } catch {
            return BenchmarkResult(
                label: label,
                targetMode: targetMode,
                promptWordCount: promptWordCount,
                wordLimitExceeded: false,
                latencySeconds: Date().timeIntervalSince(start),
                outputWordCount: 0,
                output: "",
                error: error.localizedDescription
            )
        }
    }

    private func printSectionHeader(_ title: String) {
        print("\n=== \(title) ===")
    }

    private func printResult(_ result: BenchmarkResult) {
        print(
            """
            [\(result.label)]
            target: \(result.targetMode.rawValue)
            prompt_words: \(result.promptWordCount)
            word_limit_exceeded: \(result.wordLimitExceeded)
            latency_seconds: \(result.latencySeconds.map { String(format: "%.3f", $0) } ?? "N/A")
            output_words: \(result.outputWordCount)
            error: \(result.error ?? "NONE")
            output:
            \(result.output)
            """
        )
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

private enum Fixtures {
    static let clipboardSmall = """
    Quick notes from the team sync: ship the onboarding update next Tuesday, confirm the analytics event naming before release, and send the final checklist to support.
    """

    static let clipboardMedium = """
    The migration timeline needs to be reset around a more realistic critical path. We underestimated the QA and data backfill work, especially on the entitlement checks and reporting validation. Engineering thinks the backfill can be parallelized if we split the long-running jobs by region, but the analytics team wants a single verification pass before anything rolls out broadly. The revised recommendation is to stage the release across two milestones, first landing the internal tooling changes and then enabling the customer-facing migration path after monitoring is in place. Product also wants a short summary for leadership that makes it clear this is a timing reset rather than a scope failure.
    """

    static let clipboardLarge = """
    The original proposal assumed we could keep the current service boundaries intact while still reducing p95 latency by a meaningful amount. After looking at the traces in more detail, that assumption does not really hold up. Most of the delay is coming from a handful of synchronous lookups that sit directly in the request path. They are individually small, but they stack badly under load and become much worse when the cache misses line up. Several of those lookups also fan out into systems that were never designed for bursty read traffic. The current retry strategy compounds the issue because it encourages redundant work exactly when those dependencies are already degraded.

    The team reviewed three possible directions. The first is a narrow optimization pass, where we clean up the worst calls, tighten timeouts, and try to cache more aggressively. That would be the cheapest path in the short term, but it probably only buys a modest improvement and leaves the architectural bottleneck intact. The second is an async queue approach that moves the heaviest work off the hot path and returns a partial response earlier. That would require more operational work, but it gives us a clearer way to scale. The third is a broader consolidation effort that merges two overlapping services and removes a full network hop, which would likely produce the best long-term performance but comes with the largest migration risk.

    The recommendation from infrastructure is to combine the first and second paths. Start with the low-risk query cleanup and timeout fixes immediately, but treat that as a bridge to the async queue design rather than the final answer. That way we can show measurable improvement in the quarter while still reducing the deeper structural risk. Leadership will probably want a short summary that emphasizes this as a staged reliability investment instead of a complete rewrite.
    """

    static let selectedSmall = """
    hey thanks for hopping on earlier. i think we should probably push the launch back a little bit because some of the tracking still seems off and i do not want to confuse people.
    """

    static let selectedMedium = """
    The case for investing in async infrastructure this quarter is actually stronger than it looked a few weeks ago. Our API response times have a wide variance, and the bad tail behavior is what users notice most. The average request still looks acceptable in dashboards, but the slowest requests are happening often enough that they are shaping overall sentiment. A large reason for that is that we are doing too much work synchronously in the request path, especially around entitlement checks and audit logging. Those operations are individually reasonable, but in combination they produce a path that is harder to optimize incrementally than we expected.

    If we want a meaningful improvement instead of a cosmetic one, we probably need to split the request path into a fast path and a deferred path. That would let us return the primary response earlier and move the slower bookkeeping into a queue. There are tradeoffs, including operational complexity and the need for better failure visibility, but the upside is large enough that it is worth a serious proposal.
    """

    static let selectedLarge = """
    The consolidation proposal has been discussed informally for more than a year, but this is the first time the cost data has made the tradeoff hard to ignore. We are currently paying for three parallel systems that all solve adjacent identity problems. Each has its own deployment cadence, its own on-call rotation, and its own client integration patterns. That fragmentation does not just increase operational overhead; it also makes policy changes and reliability work substantially slower because every improvement has to be translated across multiple stacks.

    The first service remains the largest by volume and still has the best operational tooling. The second service covers most of the external integrations and handles a set of enterprise features that are difficult to move quickly because of customer-specific dependencies. The third service is comparatively small but still important because it supports a handful of high-value federation flows. Taken separately, each system looks manageable. Taken together, they introduce duplicated maintenance effort, inconsistent user experiences, and a surprising amount of hidden incident response cost.

    A realistic plan would not attempt to replace everything at once. Phase one should retire the smallest and least differentiated flows first, especially the paths that already have clear ownership elsewhere. Phase two should focus on the external integrations that can be migrated behind compatibility adapters. Phase three can then address the remaining enterprise-specific logic once the surrounding foundation is better understood. The key is to frame the effort as a staged simplification program with measurable wins in reliability, cost, and delivery speed rather than as a dramatic rewrite. That positioning matters because the broader organization has seen too many “platform investments” that dragged on without producing visible results.
    """
}
