import XCTest
@testable import MouthKeyboard

/// End-to-end tests that drive the real local MLX model with inputs sized past
/// the old hardcoded caps (1000–2000 words / 1024–2048 output tokens) to confirm
/// the dynamic RAM-aware limits actually deliver clean output at those sizes.
///
/// Runs every (tier × body size) combination so a regression on any single tier
/// is visible. Models load once per test method instance — total runtime is
/// ~60–90 seconds across all tiers on warm caches.
///
/// Opt-in: set RUN_MODEL_INTEGRATION_TESTS=1.
final class RewriteContextLengthIntegrationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_MODEL_INTEGRATION_TESTS"] == "1",
            "Skipping real MLX context-length tests. Set RUN_MODEL_INTEGRATION_TESTS=1 to enable."
        )
    }

    // MARK: - Quality assertions

    /// Output must end on a sentence-terminating mark — proves the model wasn't
    /// cut off mid-sentence by the output-token cap.
    private func assertNotTruncated(_ output: String, label: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(trimmed.isEmpty, "\(label): output was empty")
        let terminators: Set<Character> = [".", "!", "?", "\"", "'", ")"]
        guard let last = trimmed.last else {
            XCTFail("\(label): output had no characters")
            return
        }
        XCTAssertTrue(
            terminators.contains(last),
            "\(label): output didn't end on sentence terminator (last char: '\(last)'). Likely truncated by output cap. Tail: '\(trimmed.suffix(80))'"
        )
    }

    /// Detects degenerate loops by scanning for any 20-word window that repeats
    /// verbatim somewhere later in the output.
    private func assertNoRepetitionLoop(_ output: String, label: String) {
        let words = output
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
        guard words.count >= 60 else { return }
        let windowSize = 20
        var seen: [String: Int] = [:]
        for start in 0...(words.count - windowSize) {
            let window = words[start..<(start + windowSize)].joined(separator: " ").lowercased()
            if let earlier = seen[window], start - earlier > windowSize {
                XCTFail("\(label): output contains repeating 20-word loop. First at word \(earlier), again at word \(start). Window: \"\(window.prefix(120))\"")
                return
            }
            seen[window] = start
        }
    }

    // MARK: - Inputs

    private func paragraphs(_ count: Int) -> String {
        let para = "The quarterly review captured a mixed picture across the four major business lines. Revenue from the enterprise segment grew faster than forecast, driven by larger contract sizes in financial services and a meaningful uptick in renewals from the prior cohort. The mid-market segment held steady but margins compressed as competitive discounting picked up. Self-serve growth slowed for the second quarter in a row, which the team attributes to a saturated top-of-funnel and a longer activation timeline for the redesigned onboarding. International expansion remains the biggest open question, with strong early traction in two countries offset by regulatory friction in a third."
        return Array(repeating: para, count: count).joined(separator: "\n\n")
    }

    // MARK: - Shared runner

    private func runRewriteQualityCheck(
        tier: RewriteModelTier,
        paragraphCount: Int,
        instructions: String,
        minOutputChars: Int
    ) async throws {
        let service = LocalRewriteService(tier: tier)
        let body = paragraphs(paragraphCount)
        let approxWordCount = paragraphCount * 100
        let label = "\(tier.rawValue)/\(approxWordCount)w"

        let result = try await service.rewrite(body: body, instructions: instructions)

        assertNotTruncated(result, label: label)
        XCTAssertGreaterThan(result.count, minOutputChars, "\(label): output suspiciously short (\(result.count) chars)")
        assertNoRepetitionLoop(result, label: label)
    }

    // MARK: - 2B tier

    func testRewrite_2B_1500WordBody_completesCleanly() async throws {
        try await runRewriteQualityCheck(
            tier: .standard2B,
            paragraphCount: 15,
            instructions: "Rewrite this as a crisp executive summary, preserving the four-segment structure.",
            minOutputChars: 200
        )
    }

    func testRewrite_2B_3000WordBody_completesPastOldLimit() async throws {
        try await runRewriteQualityCheck(
            tier: .standard2B,
            paragraphCount: 30,
            instructions: "Summarize the key trends. Keep it concise but cover every business line mentioned.",
            minOutputChars: 300
        )
    }

    func testRewrite_2B_5000WordBody_holdsQualityAtLargeContext() async throws {
        try await runRewriteQualityCheck(
            tier: .standard2B,
            paragraphCount: 50,
            instructions: "Distill this into a one-paragraph executive overview.",
            minOutputChars: 300
        )
    }

    /// ~20,000 words (~28k input tokens) — pushes near the 32k practical input
    /// cap to validate that the full ceiling actually works on this tier.
    func testRewrite_2B_atNearCapInput_completesCleanly() async throws {
        try await runRewriteQualityCheck(
            tier: .standard2B,
            paragraphCount: 200,
            instructions: "Distill this into a one-paragraph executive overview.",
            minOutputChars: 200
        )
    }

    // MARK: - 4B tier

    func testRewrite_4B_1500WordBody_completesCleanly() async throws {
        try await runRewriteQualityCheck(
            tier: .standard4B,
            paragraphCount: 15,
            instructions: "Rewrite this as a crisp executive summary, preserving the four-segment structure.",
            minOutputChars: 200
        )
    }

    func testRewrite_4B_3000WordBody_completesPastOldLimit() async throws {
        try await runRewriteQualityCheck(
            tier: .standard4B,
            paragraphCount: 30,
            instructions: "Summarize the key trends. Keep it concise but cover every business line mentioned.",
            minOutputChars: 300
        )
    }

    func testRewrite_4B_5000WordBody_holdsQualityAtLargeContext() async throws {
        try await runRewriteQualityCheck(
            tier: .standard4B,
            paragraphCount: 50,
            instructions: "Distill this into a one-paragraph executive overview.",
            minOutputChars: 300
        )
    }

    func testRewrite_4B_atNearCapInput_completesCleanly() async throws {
        try await runRewriteQualityCheck(
            tier: .standard4B,
            paragraphCount: 200,
            instructions: "Distill this into a one-paragraph executive overview.",
            minOutputChars: 200
        )
    }

    // MARK: - 9B tier

    func testRewrite_9B_1500WordBody_completesCleanly() async throws {
        try await runRewriteQualityCheck(
            tier: .high9B,
            paragraphCount: 15,
            instructions: "Rewrite this as a crisp executive summary, preserving the four-segment structure.",
            minOutputChars: 200
        )
    }

    func testRewrite_9B_3000WordBody_completesPastOldLimit() async throws {
        try await runRewriteQualityCheck(
            tier: .high9B,
            paragraphCount: 30,
            instructions: "Summarize the key trends. Keep it concise but cover every business line mentioned.",
            minOutputChars: 300
        )
    }

    func testRewrite_9B_5000WordBody_holdsQualityAtLargeContext() async throws {
        try await runRewriteQualityCheck(
            tier: .high9B,
            paragraphCount: 50,
            instructions: "Distill this into a one-paragraph executive overview.",
            minOutputChars: 300
        )
    }

    func testRewrite_9B_atNearCapInput_completesCleanly() async throws {
        try await runRewriteQualityCheck(
            tier: .high9B,
            paragraphCount: 200,
            instructions: "Distill this into a one-paragraph executive overview.",
            minOutputChars: 200
        )
    }
}
