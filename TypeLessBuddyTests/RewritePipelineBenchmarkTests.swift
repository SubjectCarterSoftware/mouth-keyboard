import XCTest
@testable import TypeLessBuddy

/// Opt-in benchmark suite for the rewrite pipeline under realistic external-text context loads.
///
/// Gate: set RUN_REWRITE_BENCHMARK_TESTS=1 to run. Never runs in CI or normal development.
///
/// Three scenarios × three input sizes each:
///   1. Clipboard-only:   small (~70 words) / medium (~400 words) / large (~1000 words)
///   2. Selected-only:    small (~80 words) / medium (~350 words) / large (~900 words)
///   3. Both sources:     small (~200 combined) / medium (~700 combined) /
///                        large (~1600 combined — expects BOTH→SELECTED fallback)
///
/// Output is printed to stdout for manual inspection. Records: route used (including any
/// fallback), prompt word count, latency, output word count, word-limit/truncation events,
/// and the complete generated output for quality review.
final class RewritePipelineBenchmarkTests: XCTestCase {

    private let service = LLMRewriteService.shared
    private static let wordLimit = RewriteModelTier.standard2B.rewritePromptWordLimit

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_REWRITE_BENCHMARK_TESTS"] == "1",
            "Rewrite pipeline benchmarks skipped. Set RUN_REWRITE_BENCHMARK_TESTS=1 to run."
        )
    }

    // MARK: - Single entry point
    //
    // All nine cases run sequentially in one test method so the runner can never
    // parallelise across scenarios and only one model call is in flight at a time.

    func testBenchmark_RewritePipeline() async throws {
        // Scenario 1: Clipboard-Only
        printSectionHeader("Scenario 1: Clipboard-Only")

        await runAndPrint(
            label: "Small (~70-word clipboard)",
            route: .clipboard,
            dictated: "rewrite this to sound more formal and polished for an executive update",
            selectedText: nil,
            clipboardText: Fixtures.clipboardSmall
        )
        await runAndPrint(
            label: "Medium (~400-word clipboard)",
            route: .clipboard,
            dictated: "clean up the writing in this section, fix any grammar issues, and make it ready to send to the product team",
            selectedText: nil,
            clipboardText: Fixtures.clipboardMedium
        )
        await runAndPrint(
            label: "Large (~1000-word clipboard)",
            route: .clipboard,
            dictated: "tighten this document section significantly, cut out any redundancy, and aim for roughly two thirds of the original length",
            selectedText: nil,
            clipboardText: Fixtures.clipboardLarge
        )

        // Scenario 2: Selected-Text-Only
        printSectionHeader("Scenario 2: Selected-Text-Only")

        await runAndPrint(
            label: "Small (~80-word selection)",
            route: .selectedText,
            dictated: "fix the grammar, remove the hedging language, and make this more confident and direct",
            selectedText: Fixtures.selectedSmall,
            clipboardText: nil
        )
        await runAndPrint(
            label: "Medium (~350-word selection)",
            route: .selectedText,
            dictated: "rewrite this draft to be more compelling, cut it by about a quarter, and tighten the argument",
            selectedText: Fixtures.selectedMedium,
            clipboardText: nil
        )
        await runAndPrint(
            label: "Large (~900-word selection)",
            route: .selectedText,
            dictated: "clean this up, remove the repetitive sections, and make it more direct without losing the key points",
            selectedText: Fixtures.selectedLarge,
            clipboardText: nil
        )

        // Scenario 3: Both Sources
        printSectionHeader("Scenario 3: Both Sources")

        await runAndPrint(
            label: "Small (~200-word combined, well under limit)",
            route: .both,
            dictated: "merge the key points from my clipboard notes into this intro paragraph",
            selectedText: Fixtures.bothSelected_Small,
            clipboardText: Fixtures.bothClipboard_Small
        )
        await runAndPrint(
            label: "Medium (~700-word combined, comfortably under limit)",
            route: .both,
            dictated: "incorporate the relevant supporting facts from my clipboard into this draft while keeping the same structure",
            selectedText: Fixtures.bothSelected_Medium,
            clipboardText: Fixtures.bothClipboard_Medium
        )
        await runAndPrint(
            label: "Large (~1600-word combined, expects BOTH→SELECTED fallback)",
            route: .both,
            dictated: "use my clipboard notes to enrich this draft by adding any missing context or facts that fit naturally",
            selectedText: Fixtures.bothSelected_Large,
            clipboardText: Fixtures.bothClipboard_Large
        )
    }
}

// MARK: - Benchmark Engine

extension RewritePipelineBenchmarkTests {

    private struct BenchmarkResult {
        let label: String
        let routeRequested: ExternalTextSource
        let routeUsed: ExternalTextSource
        let bothFalledBack: Bool
        let promptWordCount: Int
        let wordLimitExceeded: Bool
        let latencySeconds: Double?
        let outputWordCount: Int
        let output: String
        let error: String?
    }

    private func runAndPrint(
        label: String,
        route: ExternalTextSource,
        dictated: String,
        selectedText: String?,
        clipboardText: String?
    ) async {
        let result = await runBenchmark(
            label: label,
            route: route,
            dictated: dictated,
            selectedText: selectedText,
            clipboardText: clipboardText
        )
        printResult(result)
    }

    private func runBenchmark(
        label: String,
        route: ExternalTextSource,
        dictated: String,
        selectedText: String?,
        clipboardText: String?
    ) async -> BenchmarkResult {
        var effectiveRoute = route
        var body = buildPromptBody(
            route: route,
            dictated: dictated,
            selected: selectedText,
            clipboard: clipboardText
        )
        var didFallBack = false

        // Mirrors ActivationStore's BOTH→SELECTED fallback when the combined prompt
        // body exceeds the global word limit.
        if route == .both, wordCount(body) > Self.wordLimit {
            body = buildPromptBody(
                route: .selectedText,
                dictated: dictated,
                selected: selectedText,
                clipboard: nil
            )
            effectiveRoute = .selectedText
            didFallBack = true
        }

        let wc = wordCount(body)

        guard wc <= Self.wordLimit else {
            return BenchmarkResult(
                label: label,
                routeRequested: route,
                routeUsed: effectiveRoute,
                bothFalledBack: didFallBack,
                promptWordCount: wc,
                wordLimitExceeded: true,
                latencySeconds: nil,
                outputWordCount: 0,
                output: "",
                error: nil
            )
        }

        let systemPrompt = LLMRewriteService.resolveAssistantSystemPrompt(assistantName: "Assistant")
        let start = Date()

        do {
            let output = try await service.generate(prompt: body, systemPrompt: systemPrompt)
            let latency = Date().timeIntervalSince(start)
            return BenchmarkResult(
                label: label,
                routeRequested: route,
                routeUsed: effectiveRoute,
                bothFalledBack: didFallBack,
                promptWordCount: wc,
                wordLimitExceeded: false,
                latencySeconds: latency,
                outputWordCount: wordCount(output),
                output: output,
                error: nil
            )
        } catch {
            let latency = Date().timeIntervalSince(start)
            return BenchmarkResult(
                label: label,
                routeRequested: route,
                routeUsed: effectiveRoute,
                bothFalledBack: didFallBack,
                promptWordCount: wc,
                wordLimitExceeded: false,
                latencySeconds: latency,
                outputWordCount: 0,
                output: "",
                error: error.localizedDescription
            )
        }
    }

    private func buildPromptBody(
        route: ExternalTextSource,
        dictated: String,
        selected: String?,
        clipboard: String?
    ) -> String {
        switch route {
        case .clipboard:
            return ExternalTextPromptBuilder.buildBody(
                dictatedContent: dictated,
                selectedText: nil,
                clipboardText: clipboard
            )
        case .selectedText:
            return ExternalTextPromptBuilder.buildBody(
                dictatedContent: dictated,
                selectedText: selected,
                clipboardText: nil
            )
        case .both:
            return ExternalTextPromptBuilder.buildBody(
                dictatedContent: dictated,
                selectedText: selected,
                clipboardText: clipboard
            )
        case .none:
            return dictated
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func printSectionHeader(_ title: String) {
        let bar = String(repeating: "═", count: 72)
        print("\n\(bar)")
        print("  BENCHMARK — \(title)")
        print(bar)
    }

    private func printResult(_ r: BenchmarkResult) {
        print("\n┌─ [\(r.label)]")

        if r.bothFalledBack {
            print("│  Route        : \(routeLabel(r.routeRequested)) → \(routeLabel(r.routeUsed))  (BOTH→SELECTED: combined prompt exceeded \(Self.wordLimit)-word limit)")
        } else {
            print("│  Route        : \(routeLabel(r.routeUsed))")
        }

        let limitNote = r.wordLimitExceeded ? " ← EXCEEDED" : ""
        print("│  Prompt words : \(r.promptWordCount) / \(Self.wordLimit)\(limitNote)")

        if r.wordLimitExceeded {
            print("│  Status       : ✗ WORD LIMIT EXCEEDED — generation skipped")
        } else if let err = r.error {
            let t = r.latencySeconds.map { String(format: "%.2fs", $0) } ?? "n/a"
            print("│  Status       : ✗ FAILED after \(t)")
            print("│  Error        : \(err)")
        } else {
            let t = r.latencySeconds.map { String(format: "%.2fs", $0) } ?? "n/a"
            print("│  Status       : ✓ SUCCESS")
            print("│  Latency      : \(t)")
            print("│  Output words : \(r.outputWordCount)")
            print("│  Output       :")
            r.output
                .components(separatedBy: "\n")
                .forEach { print("│    \($0)") }
        }

        print("└" + String(repeating: "─", count: 70))
    }

    private func routeLabel(_ route: ExternalTextSource) -> String {
        switch route {
        case .clipboard:    return ".clipboard"
        case .selectedText: return ".selectedText"
        case .both:         return ".both"
        case .none:         return ".none"
        }
    }
}

// MARK: - Fixtures

private enum Fixtures {

    // MARK: Clipboard-only
    // Simulates a user who copies content they want transformed, then dictates an instruction.

    static let clipboardSmall = """
    Our new onboarding flow reduced time-to-first-value by 40% in the first month. Users who \
    complete the three-step setup wizard retain at 2x the rate of those who skip it. The main \
    friction point was the API key step, which we moved to the end of the flow. We are now \
    investigating whether we can automate it entirely using OAuth.
    """

    static let clipboardMedium = """
    Q3 Product Update — Search and Discovery

    Search latency dropped from an average of 340ms to 95ms after we migrated the ranking layer \
    to the new inference cluster. This was the largest single improvement to perceived performance \
    shipped in two years. Users are now seeing results within one second in 97% of cases, up \
    from 71%.

    The new query understanding model went into production on September 8th. Early signals are \
    strong: zero-result rates are down 18% and click-through on the top result increased by 9 \
    points. The model handles multi-word queries with implicit context much better than the \
    rule-based fallback it replaced. A few edge cases around negation queries are still being \
    addressed.

    On the discovery side, the personalized feed experiment moved from 10% to 50% rollout after \
    hitting its primary engagement metric. Session depth in the treatment group increased by 1.4 \
    pages on average and the bounce rate for new users dropped from 34% to 27%. We are preparing \
    a full rollout for Q4 pending final review of the diversity metrics, which currently show a \
    slight overfit to recent activity.

    Infrastructure costs for the search cluster are up 12% quarter-over-quarter due to the \
    inference migration, but the team expects this to normalize after the final capacity \
    optimization pass planned for late October. No incidents were attributable to the migration.
    """

    static let clipboardLarge = """
    Technical Specification: Rewrite Service Architecture — v2.1

    Overview

    This document describes the architecture of the on-device text rewrite service introduced in \
    version 2.0 and extended in version 2.1. The service is responsible for taking raw \
    transcription output and transforming it into polished prose based on user-supplied \
    instructions. The design prioritizes low latency on consumer hardware, deterministic output \
    for a given input, and a clean separation between model loading, generation, and instruction \
    routing.

    Model Selection and Tier System

    The service supports three model tiers: 2B, 4B, and 9B parameter counts. The default tier \
    is 2B. Users with modern Apple Silicon devices can opt into 4B or 9B for higher output \
    quality. Tier selection is persisted in app preferences and applied at service initialization.

    Each tier maps to a specific model repository on the Hugging Face Hub. The service downloads \
    models lazily on first use and caches them locally in the Application Support directory. \
    Downloads are gated behind an availability check that inspects available disk space before \
    initiating a transfer. If disk space is insufficient, the service falls back to the next \
    smaller tier and displays a user-visible warning.

    Model Loading and Caching

    Model loading is handled by a single shared actor. The actor serializes concurrent load \
    requests, returning the cached model container to all callers once the first load completes. \
    A load progress observer system allows the UI to display download and initialization progress \
    during the first-use flow.

    Once loaded, the model container is retained in memory until an idle unload timer fires. The \
    idle timer is reset on each new generation request and expires after 30 seconds of inactivity. \
    This prevents repeated cold-start latency for users who make multiple requests in quick \
    succession while avoiding persistent memory pressure for users who switch away.

    The load path distinguishes between first-time downloads and subsequent loads from the local \
    cache. First-time downloads go through the Hub API with a custom progress reporting layer. \
    Subsequent loads read directly from the local cache directory, bypassing the network \
    entirely. Cache validity is checked via a manifest hash comparison to detect incomplete or \
    corrupted downloads.

    Generation Pipeline

    The generation pipeline is built on top of the MLX inference framework. Each generation \
    request creates a fresh ChatSession to ensure there is no state bleed between requests. The \
    session is initialized with the system prompt, generation parameters, and a flag disabling \
    the model's built-in chain-of-thought feature.

    Generation is streamed token by token and emitted through an AsyncThrowingStream. A \
    ThinkStripper component processes the raw stream and filters out any reasoning tags that \
    the model may emit despite the disable flag. The stripped tokens are accumulated into the \
    final output string.

    Stop conditions are enforced via the GenerateParameters struct, which specifies the maximum \
    token budget and sampling configuration. The service uses temperature 0 and topP 1.0 for \
    deterministic output. The maximum token budget is set per tier to avoid runaway generation \
    on large inputs.

    Error Handling and Recovery

    The service differentiates between transient and permanent errors. Model load failures due \
    to network issues are classified as transient and trigger a retry with exponential backoff. \
    Load failures due to device memory pressure are classified as permanent for the session and \
    surface a user-visible error explaining the situation.

    Generation errors from the MLX layer are mapped to a typed error enum that the calling layer \
    can inspect. The calling layer distinguishes between cancellation, truncation, and hard \
    failures when deciding how to surface the result to the user. Cancelled generations do not \
    trigger a failure sound or error overlay.

    Instruction Routing

    The routing layer decides whether a given user request intends to operate on selected text, \
    clipboard content, both, or neither. This decision is made by a small classifier model that \
    takes the transcribed utterance and the availability flags for each source as input.

    The routing request is subject to an 8-second timeout. If the classifier does not respond \
    within this window, the service defaults to the none route and proceeds with dictation-only \
    context. This timeout is intentionally conservative to avoid blocking the user experience \
    on slow routing responses.

    Word Limit Enforcement

    All rewrite prompts are subject to a global word count limit before being sent to the \
    generation model. For requests that include both selected text and clipboard content, the \
    combined prompt is checked first. If it exceeds the limit, the clipboard content is dropped \
    and the request proceeds with selected text only. If the prompt still exceeds the limit after \
    that reduction, the session fails with a word-limit-exceeded error. This ensures generation \
    requests stay within the model's effective context window for quality output.
    """

    // MARK: Selected-only
    // Simulates a user who has highlighted a draft they are editing in the focused app.

    static let selectedSmall = """
    I think we should probably maybe consider looking at whether or not it makes sense to \
    potentially revamp the dashboard at some point. There has been some feedback from users that \
    it is not super intuitive and some of the metrics are kind of confusing, so we could maybe \
    try to run a quick usability test to get a better sense of where the actual pain points are \
    before we commit to anything too major.
    """

    static let selectedMedium = """
    The case for investing in async infrastructure this quarter is actually pretty strong when \
    you look at the numbers. Right now our API response times have a really wide variance — the \
    p50 is 120ms which is honestly fine, but the p95 is sitting at 890ms and the p99 is over two \
    seconds, which is just not acceptable for the kind of real-time collaborative features we are \
    trying to build out over the next year.

    The main thing causing this is that we are doing a lot of synchronous database calls in the \
    critical path, especially for the permission and entitlement checks. These are queries that \
    could totally be cached or moved off the hot path, but because everything is synchronous \
    right now it is really hard to make incremental improvements without a larger refactor.

    What we are proposing is basically to introduce a proper async task queue for the \
    non-latency-sensitive work and to add a lightweight caching layer in front of the permission \
    queries. Based on the profiling we did last sprint, those two changes together should bring \
    the p95 down to somewhere around 200ms, which would unblock the real-time features team \
    from shipping their Q4 work.

    The implementation risk is medium. We have done similar async migrations in other parts of \
    the system and have a decent set of integration tests we can lean on. The main thing to watch \
    out for is making sure the retry and error handling semantics are correct — we have gotten \
    bitten by that before when moving from sync to async patterns.

    The rough estimate is three to four weeks of engineering time across two engineers. We would \
    need to block some time from the platform team for a final review of the queue implementation \
    before we cut over to production traffic.
    """

    static let selectedLarge = """
    Proposal: Consolidation of the Three Authentication Services

    Background

    The current authentication infrastructure consists of three independently deployed services: \
    the legacy session service introduced in 2019, the OAuth bridge built to support third-party \
    integrations added in 2021, and the identity federation layer that handles SSO for enterprise \
    customers rolled out in 2023. Each service has its own database, its own deployment pipeline, \
    its own on-call rotation, and its own client library. Together they account for a \
    disproportionate share of our incident volume — eleven of the thirty-two P1 incidents last \
    year had authentication as a contributing factor.

    The consolidation proposal has been discussed informally for about eighteen months but has \
    not moved forward due to a combination of staffing constraints, competing priorities, and \
    genuine architectural disagreement about the right target state. This document is an attempt \
    to propose a concrete path forward.

    Current State Assessment

    The legacy session service handles approximately 80% of authentication volume. It is built on \
    a stateful session model with sessions stored in a Redis cluster. The service is well \
    understood by the team and has strong operational tooling, but it lacks support for modern \
    token standards, cannot issue JWTs natively, and has a homegrown revocation mechanism that \
    has been a source of bugs. The code is in a maintenance-only state with no new features in \
    over a year.

    The OAuth bridge was built quickly to meet a product deadline and shows it. It is a thin \
    wrapper around a third-party OAuth library that is no longer actively maintained. The bridge \
    handles roughly 15% of authentication volume, mostly through the developer API and \
    third-party integrations. It has known rate limiting bugs and a token refresh path that \
    occasionally fails silently.

    The identity federation layer is the newest and in the best architectural shape. It was built \
    with federation in mind from the start, uses standard protocols correctly, and has good test \
    coverage. It handles the remaining 5% of volume, all from enterprise SSO customers. The main \
    limitation is that it was never designed for consumer-scale session volumes.

    Proposed Target Architecture

    The proposal is to consolidate everything into a single service built on top of the \
    federation layer. The federation layer already has the right foundations — it just needs to \
    be extended to handle the session management and OAuth use cases currently handled by the \
    other two services.

    The consolidation would proceed in three phases. Phase one is to migrate the OAuth bridge \
    use cases into the federation layer. This is the lowest-risk migration because the volume is \
    small and the client base can be notified and given a migration window. Estimated duration: \
    six weeks.

    Phase two is to add stateless session support to the federation layer, allowing it to issue \
    and validate the same session tokens currently managed by the legacy service. The plan is to \
    run both systems in parallel, with new sessions issued by the federation layer and old \
    sessions validated by the legacy service until they expire naturally. Estimated duration: \
    ten weeks.

    Phase three is to decommission the legacy service and the OAuth bridge once migration is \
    complete. This includes data migration, operational cleanup, and on-call rotation \
    consolidation. Estimated duration: four weeks.

    Risks and Mitigations

    The main risk is in phase two. Migrating high-volume session management is inherently risky \
    and the parallel-run period needs to be carefully managed to avoid user-visible \
    inconsistencies. We propose gating the cutover behind a feature flag and running with a 1% \
    new-session split for the first two weeks before increasing gradually.

    A secondary risk is institutional knowledge. The legacy service is well understood; the \
    federation layer less so for most of the team. We need a dedicated knowledge transfer period \
    before phase two starts to ensure the engineers who will own the new system understand its \
    internals well enough to operate it safely under load.

    The third risk is timeline. Ten weeks for phase two is an optimistic estimate. Budget for \
    twelve and communicate that to stakeholders.
    """

    // MARK: Both-sources
    // Simulates a user who has a draft selected in the focused app and related notes on clipboard.

    static let bothSelected_Small = """
    We are planning to launch the new onboarding experience in early Q4. The current flow has \
    too many steps and users are dropping off before they see the product's core value. We want \
    to reduce setup time while still collecting the information we need for personalization.
    """

    static let bothClipboard_Small = """
    Notes from user research — September 12th:
    - 7 of 10 participants abandoned onboarding at the API key step
    - Main complaint: not clear why the key is needed at that stage
    - Two participants only completed setup after seeing the "skip for now" option
    - Suggested fix: move API key step to after first successful action
    - Progress indicator confused participants — 3 steps shown but uncounted substeps present
    - Data consent screen got positive reactions when rationale was shown inline
    """

    static let bothSelected_Medium = """
    The dashboard redesign project is targeting a mid-November release. Our goal is to reduce \
    cognitive load for new users while preserving the depth that power users depend on. The \
    current dashboard shows eighteen metrics on the default view, most of which are irrelevant \
    to users in their first thirty days. Based on previous A/B tests, we know that a more focused \
    default view improves week-two retention, but we have not yet determined the right cutoff for \
    which metrics to surface by default.

    The engineering work is relatively straightforward — the dashboard is already componentized \
    and we have a configuration system that controls which widgets appear in which contexts. The \
    harder question is product: which metrics belong in the default view and how do we handle the \
    transition for existing users who have customized their layout.

    We are proposing a three-tier structure: a simplified default view for new users showing the \
    five highest-signal metrics, a standard view that activates automatically after thirty days, \
    and a fully customizable advanced view that any user can opt into. Existing users will keep \
    their current layout unless they opt into the new structure.
    """

    static let bothClipboard_Medium = """
    Dashboard Metrics Prioritization — Research Summary

    We analyzed usage data from 12,000 accounts across individual, small-team, and enterprise \
    segments to identify which dashboard metrics correlate most strongly with retention.

    Active usage rate is the single strongest retention predictor for new individual users. \
    Accounts that view this metric in their first two weeks retain at 1.8x the rate of those \
    who do not. Enterprise customers largely ignore it in favor of cost-per-action metrics.

    Error rate and latency percentile charts are the most-viewed metrics for power users, \
    accounting for 34% of all dashboard widget interactions. New users almost never interact \
    with these in the first 30 days.

    The billing summary widget has unusually high interaction rates across all segments. Users \
    check it frequently even when nothing has changed. The team's working hypothesis is that \
    users treat it as a proxy for "is the system working."

    Collaboration metrics are important for team accounts but actively confusing for individual \
    users who see them without context.

    Recommendation: the default view should include active usage rate, recent activity timeline, \
    simplified error rate, and billing summary. Everything else should be in the standard or \
    advanced tier. Note: the last time we changed the default dashboard layout, we saw a 12% \
    spike in support tickets in the first week that normalized within three weeks. Recommend a \
    gradual rollout with a clear opt-out path for existing users.
    """

    // These two texts are sized so their combined prompt body (including header labels) exceeds
    // the 1500-word limit, triggering the BOTH→SELECTED fallback in ActivationStore. After
    // fallback, bothSelected_Large alone stays well under the limit.

    static let bothSelected_Large = """
    Engineering Retrospective: Q3 Platform Reliability

    This retrospective covers the four platform-level incidents that occurred during Q3 and the \
    systemic issues they exposed. It is intended for internal distribution within the platform \
    and infrastructure teams and for the quarterly review with engineering leadership. Total \
    customer-visible downtime was 2 hours and 47 minutes across the quarter, up from 1 hour and \
    12 minutes in Q2.

    Incident One: Configuration Drift — July 14th

    The incident began when a cache eviction policy that had been tuned in the staging \
    environment was not propagated to production during a routine deployment. The discrepancy \
    caused production cache hit rates to drop from 87% to 23% for a period of four hours, \
    resulting in elevated database load and degraded response times across the API tier.

    Detection was slow because the monitoring alert threshold for cache hit rate was set too \
    conservatively and did not fire until the situation was already severe. The on-call engineer \
    identified the root cause through manual investigation of the metrics dashboard rather than \
    through an automated alert. Remediation was straightforward once the cause was identified — \
    the configuration was updated within 15 minutes. Total incident duration: 6 hours.

    Root cause: no automated configuration consistency check between staging and production. \
    Secondary cause: alert threshold too conservative.

    Incident Two: Capacity Event — August 3rd

    A marketing campaign drove approximately 4x the normal new user registration rate over a \
    six-hour window. The account provisioning service, which had not been load-tested at this \
    scale, began dropping requests after about 90 minutes. Users attempting to create new \
    accounts received 503 errors for 2 hours and 11 minutes.

    The incident was detected within 12 minutes via automated error rate monitoring. The on-call \
    response was prompt, but scaling the provisioning service required manual intervention and \
    took 47 minutes. The service does not support automatic horizontal scaling. The marketing \
    campaign had been planned for six weeks, but the platform team was not informed about the \
    expected traffic spike until four days before launch, leaving insufficient time to prepare.

    Root cause: insufficient lead time for capacity planning. Secondary cause: provisioning \
    service lacks auto-scaling support.

    Incident Three: Configuration Drift — August 19th

    A second configuration drift incident, similar in nature to the July 14th event but affecting \
    a different subsystem: the rate limiting configuration for the developer API. A rate limit \
    increase that had been approved and applied in staging was not applied to production, causing \
    legitimate high-volume API users to be incorrectly throttled for a period of three hours.

    This incident resulted in zero customer-visible downtime but generated significant support \
    volume and caused one enterprise customer to file a formal complaint. The configuration \
    management gap that caused both July and August incidents was confirmed to be the same \
    underlying problem, establishing it as systemic rather than a one-off.

    Root cause: same configuration management gap as Incident One.

    Incident Four: Data Pipeline Failure — September 22nd

    The analytics data pipeline failed during its nightly run, producing incomplete data for \
    the September 21st daily report. The failure was caused by a change to an internal API \
    endpoint that the pipeline had been calling without an explicit version pin. The API change \
    was backwards-incompatible and was not flagged as such in the internal changelog.

    Pipeline failure was detected within one hour. Data recovery required re-running the \
    pipeline against a backup data snapshot, which took six hours. The daily report was delayed \
    by seven hours total.

    Root cause: undocumented API dependency without version pinning. Secondary cause: no \
    consumer notification process for backwards-incompatible internal API changes.

    Systemic Issues Identified

    Three systemic issues emerged across these four incidents. First, configuration management: \
    there is no automated mechanism for detecting and preventing configuration drift between \
    environments. Both the July and August incidents were caused by the same gap. This is the \
    highest-priority item coming out of the retrospective.

    Second, capacity planning communication: there is no formal process for product and marketing \
    to notify infrastructure of planned events that will affect load. The August incident would \
    have been preventable with two weeks of additional lead time.

    Third, internal API governance: backwards-incompatible changes to internal APIs are not \
    subject to a formal deprecation process. The September incident required an ad hoc fix \
    rather than a managed migration.
    """

    static let bothClipboard_Large = """
    Platform Infrastructure Roadmap — Q4 Planning Notes

    These are the working notes from the infrastructure team's Q4 planning session, intended to \
    inform the quarterly roadmap submission.

    Priority 1: Configuration Management Overhaul

    Following two configuration-drift incidents in Q3, automated configuration consistency \
    checking between environments is the top Q4 priority. The proposed solution is a \
    configuration snapshot comparison tool that runs as part of the deployment pipeline and \
    blocks promotion if undeclared drift is detected.

    The tool covers three configuration categories: application configuration managed via YAML \
    files in the repository, infrastructure configuration managed via Terraform, and runtime \
    configuration managed via the internal feature flag system. The first two categories are \
    relatively straightforward to compare. Feature flag state is more complex because it can \
    legitimately differ between environments during controlled rollouts. Legitimate differences \
    will be specified in an allowlist; anything not covered blocks the deployment and pages \
    on-call.

    Estimated engineering effort: 6 weeks across two engineers. Target: deployed and active by \
    end of October, before the November 15th marketing campaign.

    Priority 2: Provisioning Service Auto-Scaling

    The account provisioning service needs horizontal auto-scaling before the next major \
    marketing campaign. The service currently holds an in-memory task queue for pending \
    provisioning work that would be lost on instance termination, making horizontal scaling \
    unsafe in its current form.

    The proposed approach externalizes the task queue to a managed message queue service and \
    makes the provisioning workers stateless, allowing the service to scale horizontally without \
    risk of task loss. This is a moderate refactor — the provisioning service carries some \
    architectural debt from being one of the older services in the stack. Estimated engineering \
    effort: 8 weeks, including a staged rollout and load test before the next expected campaign.

    Priority 3: Internal API Governance Process

    Following the September data pipeline incident, the team is proposing a lightweight \
    governance process for backwards-incompatible changes to internal APIs. API owners would \
    be required to publish a deprecation notice at least four weeks before removing or changing \
    a public method signature and to notify known consumers directly.

    Consumer notification requires a dependency graph that does not currently exist. Building \
    a complete graph is out of scope for Q4, but a partial graph covering the APIs most likely \
    to change based on Q3 incident data is feasible. Known consumers would be identified from \
    code search and added to a registry. Estimated effort: 3 weeks for documentation and \
    tooling, plus ongoing overhead for API owners.

    Priority 4: Capacity Planning Process

    The team is proposing a formal capacity planning intake process. Any marketing or product \
    initiative expected to drive more than 2x normal load on any service must submit a capacity \
    review at least two weeks before the event. Reviews involve the platform team, the relevant \
    service owners, and a representative from the product or marketing team driving the event. \
    This is primarily a process change, not an engineering project. Estimated effort: one week \
    to document and socialize.

    Open Questions for Leadership Review

    Resourcing: priorities 1 and 2 together require the full Q4 engineering capacity of the two \
    engineers assigned to this work. If priority 2 slips to Q1, priority 3 can move up within \
    the same budget.

    On-call tooling: Q3 incidents surfaced alert threshold calibration issues and slow escalation \
    paths. The team wants to dedicate one sprint to on-call tooling improvements, but this is not \
    in the current Q4 plan due to resourcing constraints and would require reducing scope \
    elsewhere.

    Campaign timeline dependency: the configuration management tool must be deployed before the \
    November 15th marketing campaign. If it is not ready by November 1st, the recommendation is \
    to either delay the campaign or explicitly accept the risk of proceeding without it. This \
    decision should involve both engineering leadership and marketing.
    """
}
