import AppKit
import Combine
import Foundation
import MLXLMCommon
import XCTest
@testable import TypeLessBuddy

/// Opt-in diagnostic suite for external-text assistant prompts.
///
/// Run with:
/// RUN_EXTERNAL_TEXT_SCENARIO_EVAL_TESTS=1 xcodebuild test -scheme TypeLessBuddy \
///   -only-testing:TypeLessBuddyTests/ExternalTextScenarioMatrixEvaluationTests
///
/// Optional:
/// - EXTERNAL_TEXT_EVAL_OUTPUT_DIR=/absolute/path
/// - EXTERNAL_TEXT_EVAL_MODEL_TIER=qwen3.5-2b|qwen3.5-4b|qwen3.5-9b
/// - EXTERNAL_TEXT_EVAL_SCENARIO_IDS=01-selected-professional-only,04-clipboard-slack-only
/// - EXTERNAL_TEXT_EVAL_LIMIT=5
final class ExternalTextScenarioMatrixEvaluationTests: XCTestCase {
    private let assistantName = "Buddy"

    override func setUp() async throws {
        try await super.setUp()

        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("run_external_text_scenario_eval_tests")
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_EXTERNAL_TEXT_SCENARIO_EVAL_TESTS"] == "1" ||
                FileManager.default.fileExists(atPath: markerURL.path),
            "External text scenario eval skipped. Set RUN_EXTERNAL_TEXT_SCENARIO_EVAL_TESTS=1 or create \(markerURL.path) to run."
        )
    }

    func testExternalTextScenarioMatrixGeneratesPerScenarioReports() async throws {
        let scenarios = filteredScenarios(Self.scenarios)
        XCTAssertFalse(scenarios.isEmpty, "No external text eval scenarios selected.")

        let runDirectory = try makeRunDirectory()
        let tier = selectedModelTier()
        let service = LocalRewriteService(tier: tier)
        let recorder = ExternalTextPipelineRecordingRewriter(base: service)
        defer {
            Task {
                await service.unload()
            }
        }

        try await service.prewarm()

        var results: [ExternalTextScenarioEvalResult] = []
        for (offset, scenario) in scenarios.enumerated() {
            let sequenceNumber = offset + 1
            let evaluation = evaluatePrompt(for: scenario)

            let startedAt = Date()
            let pipeline: ExternalTextPipelineEvaluation
            let generationError: String?
            do {
                pipeline = try await runActivationPipeline(
                    for: scenario,
                    tier: tier,
                    rewriter: recorder
                )
                generationError = nil
            } catch {
                pipeline = ExternalTextPipelineEvaluation.failure(String(describing: error))
                generationError = String(describing: error)
            }
            let duration = Date().timeIntervalSince(startedAt)

            let result = ExternalTextScenarioEvalResult(
                scenario: scenario,
                sequenceNumber: sequenceNumber,
                modelTier: tier.rawValue,
                promptEvaluation: evaluation,
                pipelineEvaluation: pipeline,
                generationError: generationError,
                duration: duration
            )
            results.append(result)

            let reportURL = runDirectory.appendingPathComponent(
                "\(String(format: "%02d", sequenceNumber))-\(slug(scenario.id)).md"
            )
            try result.renderedMarkdown.write(
                to: reportURL,
                atomically: true,
                encoding: .utf8
            )
            print("Saved external text scenario report: \(reportURL.path)")

            if let generationError {
                XCTFail("Generation failed for \(scenario.id): \(generationError)")
            } else {
                XCTAssertFalse(
                    pipeline.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Pipeline returned empty output for scenario: \(scenario.id)"
                )
            }
        }

        let indexBody = renderIndex(results: results, runDirectory: runDirectory)
        let indexURL = runDirectory.appendingPathComponent("index.md")
        try indexBody.write(to: indexURL, atomically: true, encoding: .utf8)

        let jsonURL = runDirectory.appendingPathComponent("results.json")
        let jsonData = try JSONEncoder.externalTextEvalEncoder.encode(
            results.map(\.jsonSummary)
        )
        try jsonData.write(to: jsonURL, options: .atomic)

        let attachment = XCTAttachment(string: indexBody)
        attachment.name = "ExternalTextScenarioMatrixIndex"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("Saved external text scenario eval index: \(indexURL.path)")
        print("Saved external text scenario eval JSON: \(jsonURL.path)")
    }

    private func evaluatePrompt(
        for scenario: ExternalTextScenario
    ) -> ExternalTextPromptEvaluation {
        let actualContext = ExternalTextSourceContext(
            selectedText: scenario.selectedText,
            clipboardText: scenario.clipboardText,
            lastTranscription: scenario.lastTranscription
        )
        let phraseOnlyContext = ExternalTextSourceContext(
            selectedTextAvailable: true,
            clipboardTextAvailable: true,
            lastTranscriptionAvailable: true
        )
        let productionDecision = ExternalTextSourceClassifier.classify(
            message: scenario.dictatedContent,
            availableSources: actualContext
        )
        let phraseOnlyDecision = ExternalTextSourceClassifier.classify(
            message: scenario.dictatedContent,
            availableSources: phraseOnlyContext
        )

        let promptBody: String
        if productionDecision.injectsExternalText {
            promptBody = ExternalTextPromptBuilder.buildBody(
                dictatedContent: scenario.dictatedContent,
                selectedText: scenario.selectedText,
                clipboardText: scenario.clipboardText,
                lastTranscription: scenario.lastTranscription,
                routingDecision: productionDecision
            )
        } else {
            promptBody = ExternalTextPromptBuilder.buildDirectBody(
                dictatedContent: scenario.dictatedContent
            )
        }

        return ExternalTextPromptEvaluation(
            productionDecision: productionDecision,
            phraseOnlyDecision: phraseOnlyDecision,
            promptBody: promptBody,
            promptWordCount: wordCount(promptBody)
        )
    }

    @MainActor
    private func runActivationPipeline(
        for scenario: ExternalTextScenario,
        tier: RewriteModelTier,
        rewriter: ExternalTextPipelineRecordingRewriter
    ) async throws -> ExternalTextPipelineEvaluation {
        await rewriter.reset()

        let clipboard = ExternalTextEvalClipboard()
        let pasteService = ExternalTextEvalPasteService(
            clipboard: clipboard,
            selectedText: scenario.selectedText,
            totalSessions: scenario.lastTranscription == nil ? 1 : 2
        )
        let transcriber = ExternalTextEvalTranscriber(
            transcripts: scenario.lastTranscription == nil
                ? [scenario.dictatedContent]
                : [scenario.lastTranscription ?? "", scenario.dictatedContent]
        )
        let preferences = makePreferences(tier: tier)
        let store = ActivationStore(
            preferences: preferences,
            readinessProvider: ExternalTextEvalReadinessProvider(
                permissionsAuthorized: true,
                postEventAuthorized: true
            ),
            whisperModelLoadState: ExternalTextEvalWhisperModelLoadState(
                phase: .ready(model: preferences.whisperModel)
            ),
            whisperService: transcriber,
            localRewriteService: rewriter,
            noteCaptureService: ExternalTextEvalNoteCaptureService(),
            historyCaptureService: ExternalTextEvalHistoryCaptureService(),
            clipboardService: clipboard,
            pasteService: pasteService,
            bufferAccumulator: ExternalTextEvalBufferAccumulator()
        )
        store.soundPlayer = ActivationSoundPlayer.silent

        if let lastTranscription = scenario.lastTranscription {
            clipboard.stubbedPlainText = scenario.clipboardText
            store.arm()
            store.finish()
            guard try await waitForTerminalState(of: store) else {
                throw ExternalTextPipelineEvalError.timeout("timed out while seeding last transcription")
            }
            guard case .success = store.state else {
                throw ExternalTextPipelineEvalError.unexpectedState("failed to seed last transcription: \(store.state)")
            }
            XCTAssertEqual(lastTranscription, store.lastTranscription)
        }

        clipboard.resetWrites()
        clipboard.stubbedPlainText = scenario.clipboardText
        store.arm()
        store.finish()

        guard try await waitForTerminalState(of: store, timeoutNanoseconds: 180_000_000_000) else {
            throw ExternalTextPipelineEvalError.timeout("timed out waiting for final pipeline state")
        }

        let trace = await rewriter.trace()
        return ExternalTextPipelineEvaluation(
            finalStateDescription: "\(store.state)",
            finalText: store.currentSuccessTextForEvaluation ?? "",
            clipboardWrittenText: clipboard.lastWrittenText,
            temporaryPasteText: clipboard.temporaryWriteTexts.last,
            lastTranscriptionAfterRun: store.lastTranscription,
            selectionCopyCount: pasteService.selectionCopyCount,
            pasteCount: pasteService.pasteCount,
            trace: trace
        )
    }

    @MainActor
    private func makePreferences(tier: RewriteModelTier) -> ShellPreferences {
        let suiteName = "ExternalTextScenarioEval.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalTextScenarioEval.TriggerProfiles")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("TriggerProfileStore.json")
        let triggerStore = TriggerProfileStore(storeURL: storeURL)
        let preferences = ShellPreferences(
            userDefaults: defaults,
            triggerProfileStore: triggerStore,
            initialTriggerProfile: .defaultProfile
        )
        preferences.setCustomTrigger(primary: assistantName)
        preferences.rewriteModelTier = tier
        preferences.alwaysAutoPaste = false
        preferences.restorePreviousClipboardAfterAutoPaste = true
        preferences.historyEnabled = false
        return preferences
    }

    private nonisolated func waitForTerminalState(
        of store: ActivationStore,
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        pollingNanoseconds: UInt64 = 20_000_000
    ) async throws -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await MainActor.run(body: { store.state.isTerminal }) {
                return true
            }
            try await Task.sleep(nanoseconds: pollingNanoseconds)
        }
        return await MainActor.run { store.state.isTerminal }
    }

    private func makeRunDirectory() throws -> URL {
        let root: URL
        if let configured = configurationValue(
            environmentKey: "EXTERNAL_TEXT_EVAL_OUTPUT_DIR",
            fileName: "external_text_eval_output_dir"
        ),
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            root = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            root = repoRoot()
                .appendingPathComponent("build", isDirectory: true)
                .appendingPathComponent("external-text-scenario-eval", isDirectory: true)
        }

        let runID = Self.runIDFormatter.string(from: Date())
        let runDirectory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: runDirectory,
            withIntermediateDirectories: true
        )
        return runDirectory
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func selectedModelTier() -> RewriteModelTier {
        let rawValue = configurationValue(
            environmentKey: "EXTERNAL_TEXT_EVAL_MODEL_TIER",
            fileName: "external_text_eval_model_tier"
        )
            ?? RewriteModelTier.standard2B.rawValue
        return RewriteModelTier(rawValue: rawValue) ?? .standard2B
    }

    private func filteredScenarios(_ scenarios: [ExternalTextScenario]) -> [ExternalTextScenario] {
        let selectedIDs = configurationValue(
            environmentKey: "EXTERNAL_TEXT_EVAL_SCENARIO_IDS",
            fileName: "external_text_eval_scenario_ids"
        )
            .map { ids in
                Set(
                    ids.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            } ?? []

        var filtered = selectedIDs.isEmpty
            ? scenarios
            : scenarios.filter { selectedIDs.contains($0.id) }

        if let limitRaw = configurationValue(
            environmentKey: "EXTERNAL_TEXT_EVAL_LIMIT",
            fileName: "external_text_eval_limit"
        ),
           let limit = Int(limitRaw),
           limit > 0 {
            filtered = Array(filtered.prefix(limit))
        }

        return filtered
    }

    private func configurationValue(environmentKey: String, fileName: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[environmentKey],
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func renderIndex(
        results: [ExternalTextScenarioEvalResult],
        runDirectory: URL
    ) -> String {
        let rows = results.map { result in
            let fileName = "\(String(format: "%02d", result.sequenceNumber))-\(slug(result.scenario.id)).md"
            let warningText = result.warnings.isEmpty
                ? "none"
                : result.warnings.joined(separator: "; ")
            return "| \(result.sequenceNumber) | \(result.scenario.id) | \(result.scenario.category) | \(result.productionModesDescription) | \(result.phraseOnlyModesDescription) | \(result.promptMode) | \(warningText) | [report](\(fileName)) |"
        }.joined(separator: "\n")

        return """
        # External Text Scenario Matrix

        Output directory:
        \(runDirectory.path)

        | # | Scenario | Category | Production routing | Phrase-only routing | Prompt mode | Warnings | Report |
        |---|---|---|---|---|---|---|---|
        \(rows)
        """
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private func slug(_ input: String) -> String {
        var scalars = String.UnicodeScalarView()
        var previousWasDash = false

        for scalar in input.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                scalars.append("-")
                previousWasDash = true
            }
        }

        let slug = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "scenario" : slug
    }

    private static let runIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct ExternalTextScenario: Sendable {
    let id: String
    let name: String
    let category: String
    let dictatedContent: String
    let selectedText: String?
    let clipboardText: String?
    let lastTranscription: String?
    let expectedBehavior: String
    let reviewFocus: [String]
    let expectedProductionModes: [AssistantContextTargetMode]
    let expectedPhraseOnlyModes: [AssistantContextTargetMode]
    let expectedOutputSubstrings: [String]
    let disallowedOutputSubstrings: [String]
    let qualityChecks: [ExternalTextQualityCheck]

    init(
        id: String,
        name: String,
        category: String,
        dictatedContent: String,
        selectedText: String? = nil,
        clipboardText: String? = nil,
        lastTranscription: String? = nil,
        expectedBehavior: String,
        reviewFocus: [String],
        expectedProductionModes: [AssistantContextTargetMode],
        expectedPhraseOnlyModes: [AssistantContextTargetMode],
        expectedOutputSubstrings: [String] = [],
        disallowedOutputSubstrings: [String] = [],
        qualityChecks: [ExternalTextQualityCheck] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.dictatedContent = dictatedContent
        self.selectedText = selectedText
        self.clipboardText = clipboardText
        self.lastTranscription = lastTranscription
        self.expectedBehavior = expectedBehavior
        self.reviewFocus = reviewFocus
        self.expectedProductionModes = expectedProductionModes
        self.expectedPhraseOnlyModes = expectedPhraseOnlyModes
        self.expectedOutputSubstrings = expectedOutputSubstrings
        self.disallowedOutputSubstrings = disallowedOutputSubstrings
        self.qualityChecks = qualityChecks
    }
}

private struct ExternalTextQualityCheck: Sendable {
    let description: String
    let isSatisfied: @Sendable (String) -> Bool

    func evaluate(output: String) -> ExternalTextQualityEvaluation {
        ExternalTextQualityEvaluation(
            description: description,
            passed: isSatisfied(output)
        )
    }

    static func contains(_ fragment: String, description: String? = nil) -> ExternalTextQualityCheck {
        ExternalTextQualityCheck(
            description: description ?? "Contains '\(fragment)'"
        ) { output in
            output.localizedCaseInsensitiveContains(fragment)
        }
    }

    static func omits(_ fragment: String, description: String? = nil) -> ExternalTextQualityCheck {
        ExternalTextQualityCheck(
            description: description ?? "Omits '\(fragment)'"
        ) { output in
            !output.localizedCaseInsensitiveContains(fragment)
        }
    }

    static func containsAny(
        _ fragments: [String],
        description: String
    ) -> ExternalTextQualityCheck {
        ExternalTextQualityCheck(description: description) { output in
            fragments.contains { output.localizedCaseInsensitiveContains($0) }
        }
    }

    static func wordCountAtMost(_ maximum: Int) -> ExternalTextQualityCheck {
        ExternalTextQualityCheck(description: "Uses \(maximum) words or fewer") { output in
            output.split(whereSeparator: { $0.isWhitespace }).count <= maximum
        }
    }

    static func exactlyOneSentence() -> ExternalTextQualityCheck {
        ExternalTextQualityCheck(description: "Returns exactly one sentence") { output in
            sentenceCount(in: output) == 1
        }
    }

    static func bulletCount(_ expected: Int) -> ExternalTextQualityCheck {
        ExternalTextQualityCheck(description: "Returns exactly \(expected) bullets") { output in
            output
                .split(whereSeparator: \.isNewline)
                .filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(
                        of: #"^\d+\.\s+"#,
                        options: .regularExpression
                    ) != nil
                }
                .count == expected
        }
    }

    static func bulletCountAtLeast(_ minimum: Int) -> ExternalTextQualityCheck {
        ExternalTextQualityCheck(description: "Returns at least \(minimum) bullets") { output in
            output
                .split(whereSeparator: \.isNewline)
                .filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.range(
                        of: #"^\d+\.\s+"#,
                        options: .regularExpression
                    ) != nil
                }
                .count >= minimum
        }
    }

    static func doesNotAskForMoreInput() -> ExternalTextQualityCheck {
        ExternalTextQualityCheck(description: "Does not ask the user to provide missing source text") { output in
            let lowered = output.lowercased()
            return !lowered.contains("please provide the source") &&
                !lowered.contains("please provide the text") &&
                !lowered.contains("please provide the selected") &&
                !lowered.contains("please provide the clipboard") &&
                !lowered.contains("please provide the transcript") &&
                !lowered.contains("provide the source text") &&
                !lowered.contains("provide the selected text") &&
                !lowered.contains("provide the clipboard") &&
                !lowered.contains("paste the source") &&
                !lowered.contains("paste the text") &&
                !lowered.contains("i need the source") &&
                !lowered.contains("i need the text") &&
                !lowered.contains("i don't have access")
        }
    }

    private static func sentenceCount(in output: String) -> Int {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let matches = trimmed.matches(of: /[.!?]+(?:\s|$)/)
        return max(matches.count, 1)
    }
}

private struct ExternalTextQualityEvaluation {
    let description: String
    let passed: Bool
}

private struct ExternalTextPromptEvaluation {
    let productionDecision: AssistantContextRoutingDecision
    let phraseOnlyDecision: AssistantContextRoutingDecision
    let promptBody: String
    let promptWordCount: Int
}

private struct ExternalTextPipelineEvaluation {
    let finalStateDescription: String
    let finalText: String
    let clipboardWrittenText: String?
    let temporaryPasteText: String?
    let lastTranscriptionAfterRun: String?
    let selectionCopyCount: Int
    let pasteCount: Int
    let trace: [ExternalTextPipelineTraceEntry]

    static func failure(_ error: String) -> ExternalTextPipelineEvaluation {
        ExternalTextPipelineEvaluation(
            finalStateDescription: "failure before terminal state: \(error)",
            finalText: "",
            clipboardWrittenText: nil,
            temporaryPasteText: nil,
            lastTranscriptionAfterRun: nil,
            selectionCopyCount: 0,
            pasteCount: 0,
            trace: []
        )
    }

    var finalGenerationTrace: ExternalTextPipelineTraceEntry? {
        trace.last
    }

    var renderedTrace: String {
        guard !trace.isEmpty else {
            return textBlock("<no rewrite calls captured>")
        }

        return trace.enumerated().map { index, entry in
            """
            ### Rewrite Call \(index + 1)

            System prompt:
            \(textBlock(entry.systemPrompt))

            Prompt:
            \(textBlock(entry.prompt))

            Output:
            \(textBlock(entry.output))
            """
        }.joined(separator: "\n\n")
    }
}

private struct ExternalTextPipelineTraceEntry: Sendable {
    let prompt: String
    let systemPrompt: String
    let output: String
}

private struct ExternalTextScenarioEvalResult {
    let scenario: ExternalTextScenario
    let sequenceNumber: Int
    let modelTier: String
    let promptEvaluation: ExternalTextPromptEvaluation
    let pipelineEvaluation: ExternalTextPipelineEvaluation
    let generationError: String?
    let duration: TimeInterval

    var promptMode: String {
        promptEvaluation.productionDecision.injectsExternalText
            ? "context-injected"
            : "direct"
    }

    var productionModesDescription: String {
        describeModes(promptEvaluation.productionDecision.targetModes)
    }

    var phraseOnlyModesDescription: String {
        describeModes(promptEvaluation.phraseOnlyDecision.targetModes)
    }

    var warnings: [String] {
        var warnings: [String] = []

        if promptEvaluation.productionDecision.targetModes != scenario.expectedProductionModes {
            warnings.append(
                "production routing expected \(describeModes(scenario.expectedProductionModes))"
            )
        }

        if promptEvaluation.phraseOnlyDecision.targetModes != scenario.expectedPhraseOnlyModes {
            warnings.append(
                "phrase-only routing expected \(describeModes(scenario.expectedPhraseOnlyModes))"
            )
        }

        if let actualPrompt = pipelineEvaluation.finalGenerationTrace?.prompt,
           actualPrompt != promptEvaluation.promptBody {
            warnings.append("captured pipeline prompt differs from independently built prompt")
        }

        let loweredOutput = pipelineEvaluation.finalText.lowercased()
        for expected in scenario.expectedOutputSubstrings {
            if !loweredOutput.contains(expected.lowercased()) {
                warnings.append("output missing expected fragment '\(expected)'")
            }
        }

        for disallowed in scenario.disallowedOutputSubstrings {
            if loweredOutput.contains(disallowed.lowercased()) {
                warnings.append("output contains disallowed fragment '\(disallowed)'")
            }
        }

        if generationError != nil {
            warnings.append("generation error")
        }

        for evaluation in qualityEvaluations where !evaluation.passed {
            warnings.append("quality failed: \(evaluation.description)")
        }

        return warnings
    }

    var qualityEvaluations: [ExternalTextQualityEvaluation] {
        scenario.qualityChecks.map {
            $0.evaluate(output: pipelineEvaluation.finalText)
        }
    }

    var renderedMarkdown: String {
        """
        # \(scenario.id): \(scenario.name)

        Category:
        \(scenario.category)

        Expected behavior:
        \(scenario.expectedBehavior)

        Review focus:
        \(scenario.reviewFocus.map { "- \($0)" }.joined(separator: "\n"))

        Model tier:
        \(modelTier)

        Duration:
        \(String(format: "%.2f", duration)) seconds

        ## Inputs

        Dictated request:
        \(textBlock(scenario.dictatedContent))

        Selected text:
        \(textBlock(scenario.selectedText ?? "<nil>"))

        Clipboard text:
        \(textBlock(scenario.clipboardText ?? "<nil>"))

        Last transcription:
        \(textBlock(scenario.lastTranscription ?? "<nil>"))

        ## Routing

        Production routing with actual availability:
        - decisionSource: \(String(describing: promptEvaluation.productionDecision.decisionSource))
        - matchedSources: \(productionModesDescription)
        - expectedMatchedSources: \(describeModes(scenario.expectedProductionModes))

        Phrase-only routing with every source marked available:
        - decisionSource: \(String(describing: promptEvaluation.phraseOnlyDecision.decisionSource))
        - matchedSources: \(phraseOnlyModesDescription)
        - expectedMatchedSources: \(describeModes(scenario.expectedPhraseOnlyModes))

        Prompt mode:
        \(promptMode)

        Prompt word count:
        \(promptEvaluation.promptWordCount)

        Selection copy count:
        \(pipelineEvaluation.selectionCopyCount)

        Paste count:
        \(pipelineEvaluation.pasteCount)

        Quality evaluation:
        \(qualityEvaluations.isEmpty ? "- none" : qualityEvaluations.map { "- [\($0.passed ? "pass" : "fail")] \($0.description)" }.joined(separator: "\n"))

        Warnings:
        \(warnings.isEmpty ? "- none" : warnings.map { "- \($0)" }.joined(separator: "\n"))

        ## Independently Built Prompt Body

        \(textBlock(promptEvaluation.promptBody))

        ## Activation Pipeline

        Final state:
        \(textBlock(pipelineEvaluation.finalStateDescription))

        Final delivered text:
        \(textBlock(pipelineEvaluation.finalText.isEmpty ? "<empty>" : pipelineEvaluation.finalText))

        Clipboard written text:
        \(textBlock(pipelineEvaluation.clipboardWrittenText ?? "<nil>"))

        Temporary paste text:
        \(textBlock(pipelineEvaluation.temporaryPasteText ?? "<nil>"))

        Last transcription after run:
        \(textBlock(pipelineEvaluation.lastTranscriptionAfterRun ?? "<nil>"))

        ## Captured Rewrite Calls

        \(pipelineEvaluation.renderedTrace)

        ## Generation Error

        \(textBlock(generationError ?? "<none>"))
        """
    }

    var jsonSummary: ExternalTextScenarioJSONSummary {
        ExternalTextScenarioJSONSummary(
            id: scenario.id,
            name: scenario.name,
            category: scenario.category,
            modelTier: modelTier,
            promptMode: promptMode,
            productionModes: promptEvaluation.productionDecision.targetModes.map(\.rawValue),
            phraseOnlyModes: promptEvaluation.phraseOnlyDecision.targetModes.map(\.rawValue),
            expectedProductionModes: scenario.expectedProductionModes.map(\.rawValue),
            expectedPhraseOnlyModes: scenario.expectedPhraseOnlyModes.map(\.rawValue),
            promptWordCount: promptEvaluation.promptWordCount,
            outputCharacterCount: pipelineEvaluation.finalText.count,
            duration: duration,
            finalState: pipelineEvaluation.finalStateDescription,
            finalText: pipelineEvaluation.finalText,
            clipboardWrittenText: pipelineEvaluation.clipboardWrittenText,
            temporaryPasteText: pipelineEvaluation.temporaryPasteText,
            lastTranscriptionAfterRun: pipelineEvaluation.lastTranscriptionAfterRun,
            selectionCopyCount: pipelineEvaluation.selectionCopyCount,
            pasteCount: pipelineEvaluation.pasteCount,
            quality: qualityEvaluations.map {
                ExternalTextQualityJSONSummary(
                    description: $0.description,
                    passed: $0.passed
                )
            },
            warnings: warnings,
            generationError: generationError
        )
    }
}

private struct ExternalTextScenarioJSONSummary: Encodable {
    let id: String
    let name: String
    let category: String
    let modelTier: String
    let promptMode: String
    let productionModes: [String]
    let phraseOnlyModes: [String]
    let expectedProductionModes: [String]
    let expectedPhraseOnlyModes: [String]
    let promptWordCount: Int
    let outputCharacterCount: Int
    let duration: TimeInterval
    let finalState: String
    let finalText: String
    let clipboardWrittenText: String?
    let temporaryPasteText: String?
    let lastTranscriptionAfterRun: String?
    let selectionCopyCount: Int
    let pasteCount: Int
    let quality: [ExternalTextQualityJSONSummary]
    let warnings: [String]
    let generationError: String?
}

private struct ExternalTextQualityJSONSummary: Encodable {
    let description: String
    let passed: Bool
}

private extension JSONEncoder {
    static var externalTextEvalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private func describeModes(_ modes: [AssistantContextTargetMode]) -> String {
    modes.isEmpty
        ? "<none>"
        : modes.map(\.rawValue).joined(separator: ", ")
}

private func textBlock(_ text: String) -> String {
    """
    ```text
    \(text)
    ```
    """
}

private enum ExternalTextPipelineEvalError: Error, CustomStringConvertible {
    case timeout(String)
    case unexpectedState(String)

    var description: String {
        switch self {
        case .timeout(let message), .unexpectedState(let message):
            return message
        }
    }
}

@MainActor
private extension ActivationStore {
    var currentSuccessTextForEvaluation: String? {
        guard case .success(let text, _, _, _, _) = state else {
            return nil
        }
        return text
    }
}

private actor ExternalTextPipelineRecordingRewriter: Rewriting {
    private let base: any Rewriting
    private var entries: [ExternalTextPipelineTraceEntry] = []

    init(base: any Rewriting) {
        self.base = base
    }

    func reset() {
        entries.removeAll()
    }

    func trace() -> [ExternalTextPipelineTraceEntry] {
        entries
    }

    func setTier(_ newTier: RewriteModelTier) async {
        await base.setTier(newTier)
    }

    func prewarm() async throws {
        try await base.prewarm()
    }

    func rewrite(body: String, instructions: String, promptPrefix: String) async throws -> String {
        try await base.rewrite(
            body: body,
            instructions: instructions,
            promptPrefix: promptPrefix
        )
    }

    func rewrite(body: String, instructions: String) async throws -> String {
        try await base.rewrite(body: body, instructions: instructions)
    }

    func generate(prompt: String, systemPrompt: String) async throws -> String {
        try await generate(prompt: prompt, systemPrompt: systemPrompt, images: [])
    }

    func generate(
        prompt: String,
        systemPrompt: String,
        images: [UserInput.Image]
    ) async throws -> String {
        let output = try await base.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            images: images
        )
        entries.append(
            ExternalTextPipelineTraceEntry(
                prompt: prompt,
                systemPrompt: systemPrompt,
                output: output
            )
        )
        return output
    }

    func loadedTier() async -> RewriteModelTier? {
        await base.loadedTier()
    }

    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async {
        await base.scheduleIdleUnload(afterNanoseconds: duration)
    }

    func cancelScheduledUnload() async {
        await base.cancelScheduledUnload()
    }

    func unload() async {
        await base.unload()
    }

    func deleteDownloadedModel(for tier: RewriteModelTier) async throws {
        try await base.deleteDownloadedModel(for: tier)
    }
}

@MainActor
private struct ExternalTextEvalReadinessProvider: ReadinessProviding {
    let permissionsAuthorized: Bool
    let postEventAuthorized: Bool

    var snapshot: ReadinessSnapshot {
        let microphoneStatus: PermissionGrantState = permissionsAuthorized ? .authorized : .denied
        let postEventStatus: PermissionGrantState = postEventAuthorized ? .authorized : .notDetermined
        return ReadinessSnapshot(
            state: permissionsAuthorized ? .ready : .blocked,
            title: "",
            message: "",
            permissions: [
                PermissionChecklistItem(
                    kind: .microphone,
                    status: microphoneStatus,
                    message: "",
                    isRequired: true
                ),
                PermissionChecklistItem(
                    kind: .postEvent,
                    status: postEventStatus,
                    message: "",
                    isRequired: false
                ),
            ]
        )
    }
}

@MainActor
private final class ExternalTextEvalWhisperModelLoadState: WhisperModelLoadStateProviding {
    @Published var phase: WhisperModelLoadState.Phase

    init(phase: WhisperModelLoadState.Phase) {
        self.phase = phase
    }

    var phasePublisher: AnyPublisher<WhisperModelLoadState.Phase, Never> {
        $phase.eraseToAnyPublisher()
    }
}

private final class ExternalTextEvalTranscriber: WhisperTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var transcripts: [String]

    init(transcripts: [String]) {
        self.transcripts = transcripts
    }

    func prepare(model _: WhisperModelChoice) async throws {}

    func transcribe(samples _: [Float]) async throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !transcripts.isEmpty else {
            return ""
        }
        return transcripts.removeFirst()
    }

    func loadedModelChoice() async -> WhisperModelChoice? {
        .baseEN
    }
}

private final class ExternalTextEvalClipboard: ClipboardService {
    private(set) var lastWrittenText: String?
    private(set) var temporaryWriteTexts: [String] = []
    private(set) var restoreCount = 0
    var stubbedPlainText: String?
    private var changeCount = 1

    init() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("ExternalTextEvalClipboard.\(UUID().uuidString)")
        )
        super.init(pasteboard: pasteboard)
    }

    override func snapshotCurrentClipboard() -> ClipboardSnapshot {
        ClipboardSnapshot.empty(
            changeCount: changeCount,
            plainText: stubbedPlainText,
            imageContent: nil
        )
    }

    @discardableResult
    override func writeToClipboard(_ text: String) -> Bool {
        lastWrittenText = text
        stubbedPlainText = text
        changeCount += 1
        return true
    }

    override func writeTemporaryText(_ text: String) -> ClipboardWriteReceipt? {
        temporaryWriteTexts.append(text)
        stubbedPlainText = text
        changeCount += 1
        return ClipboardWriteReceipt(changeCount: changeCount)
    }

    override func restoreClipboard(
        from snapshot: ClipboardSnapshot,
        ifUnchangedSince _: ClipboardWriteReceipt? = nil
    ) -> Bool {
        restoreCount += 1
        stubbedPlainText = snapshot.plainText
        changeCount += 1
        return true
    }

    override func readFromClipboard() -> String? {
        stubbedPlainText
    }

    func simulateSelectionCopy(_ text: String?) {
        stubbedPlainText = text
        changeCount += 1
    }

    func resetWrites() {
        lastWrittenText = nil
        temporaryWriteTexts.removeAll()
        restoreCount = 0
    }
}

private final class ExternalTextEvalPasteService: PasteServicing {
    private let clipboard: ExternalTextEvalClipboard
    private let selectedText: String?
    private let maxSelectionCopyAttempts: Int
    private(set) var selectionCopyCount = 0
    private(set) var pasteCount = 0

    init(
        clipboard: ExternalTextEvalClipboard,
        selectedText: String?,
        totalSessions: Int
    ) {
        self.clipboard = clipboard
        self.selectedText = selectedText
        self.maxSelectionCopyAttempts = max(0, totalSessions * 2)
    }

    func pasteCurrentClipboard() -> PasteOutcome {
        pasteCount += 1
        return .copiedOnly
    }

    func copySelectedTextToClipboard() -> PostEventOutcome {
        selectionCopyCount += 1
        guard selectionCopyCount <= maxSelectionCopyAttempts,
              let selectedText else {
            return .unavailable
        }
        clipboard.simulateSelectionCopy(selectedText)
        return .dispatched
    }
}

private final class ExternalTextEvalBufferAccumulator: AudioBufferAccumulator {
    override func convertToWhisperFormat() throws -> [Float] {
        [0.0, 0.0, 0.0]
    }
}

private final class ExternalTextEvalNoteCaptureService: NoteCapturing, @unchecked Sendable {
    func saveNote(
        content _: NoteCaptureContent,
        configuration _: AssistantNoteConfiguration
    ) throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("external-text-eval-note.md")
    }
}

private final class ExternalTextEvalHistoryCaptureService: HistoryCapturing, @unchecked Sendable {
    func saveEntry(
        content _: HistoryCaptureContent,
        configuration _: HistoryConfiguration
    ) throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("external-text-eval-history.txt")
    }

    func listEntries(configuration _: HistoryConfiguration) throws -> [HistoryEntry] {
        []
    }

    func loadEntryText(at _: URL) throws -> String {
        ""
    }

    func loadEntryDetail(at _: URL) throws -> HistoryEntryDetail {
        HistoryEntryDetail(createdAt: nil, mode: .raw, rawTranscription: "", assistantOutput: nil)
    }

    func deleteEntry(at _: URL) throws {}

    func deleteAllEntries(configuration _: HistoryConfiguration) throws {}

    func storageUsage(configuration _: HistoryConfiguration) throws -> HistoryUsage {
        HistoryUsage(totalBytes: 0, entryCount: 0)
    }
}

private extension ExternalTextScenarioMatrixEvaluationTests {
    static let scenarios: [ExternalTextScenario] = [
        ExternalTextScenario(
            id: "01-selected-professional-only",
            name: "Selected text professional rewrite",
            category: "single-source selected",
            dictatedContent: "Buddy, make what's selected sound more professional",
            selectedText: "hey thanks for the quick reply. i think we should probably wait until next week before we announce anything",
            expectedBehavior: "Use selected text as the only source and produce a polished rewrite.",
            reviewFocus: [
                "The output should rewrite the selected text, not answer the request conversationally.",
                "It should preserve the delay to next week.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            expectedOutputSubstrings: ["next week"]
        ),
        ExternalTextScenario(
            id: "02-selected-grammar-only",
            name: "Selected text grammar cleanup",
            category: "single-source selected",
            dictatedContent: "Buddy, check the grammar in what's selected",
            selectedText: "i went too the store and buyed some groceries before the client meeting",
            expectedBehavior: "Use selected text as the grammar source and return only corrected text.",
            reviewFocus: [
                "The output should fix grammar without inventing new details.",
                "It should not mention clipboard or transcript access.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            expectedOutputSubstrings: ["client meeting"]
        ),
        ExternalTextScenario(
            id: "03-selected-tone-softening",
            name: "Selected text tone softening",
            category: "single-source selected",
            dictatedContent: "Buddy, make the selected text less harsh",
            selectedText: "This launch plan is sloppy and the analytics review was a waste of everyone's time.",
            expectedBehavior: "Rewrite the selected text to be less harsh while preserving the criticism.",
            reviewFocus: [
                "The criticism should remain present.",
                "The hostile wording should be softened.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            expectedOutputSubstrings: ["analytics"]
        ),
        ExternalTextScenario(
            id: "04-clipboard-slack-only",
            name: "Clipboard to Slack update",
            category: "single-source clipboard",
            dictatedContent: "Buddy, turn what I copied into a short Slack update",
            clipboardText: "Launch moved to Friday. Waiting on final analytics check. Need support heads-up by Thursday afternoon.",
            expectedBehavior: "Use clipboard text as the only source and produce a concise Slack-ready update.",
            reviewFocus: [
                "The output should preserve Friday and Thursday afternoon.",
                "It should not ask for the clipboard content.",
            ],
            expectedProductionModes: [.clipboard],
            expectedPhraseOnlyModes: [.clipboard],
            expectedOutputSubstrings: ["Friday", "Thursday"]
        ),
        ExternalTextScenario(
            id: "05-clipboard-action-items",
            name: "Clipboard to action items",
            category: "single-source clipboard",
            dictatedContent: "Buddy, turn what I copied into a clean action-item list",
            clipboardText: "Need design sign-off by noon Friday. Follow up with support after analytics review. Confirm rollout timing with product.",
            expectedBehavior: "Use clipboard text and convert it into action items.",
            reviewFocus: [
                "Each item should be actionable.",
                "The output should preserve noon Friday and analytics review.",
            ],
            expectedProductionModes: [.clipboard],
            expectedPhraseOnlyModes: [.clipboard],
            expectedOutputSubstrings: ["Friday", "support", "analytics"]
        ),
        ExternalTextScenario(
            id: "06-last-transcription-polite",
            name: "Last transcription polite rewrite",
            category: "single-source last transcription",
            dictatedContent: "Buddy, fix my last transcription and make it polite",
            lastTranscription: "hey sarah this deck is kind of a mess and i need you to clean it up today",
            expectedBehavior: "Use the last transcription and rewrite it politely.",
            reviewFocus: [
                "The output should keep that the deck needs cleanup today.",
                "It should not become generic praise.",
            ],
            expectedProductionModes: [.lastTranscription],
            expectedPhraseOnlyModes: [.lastTranscription],
            expectedOutputSubstrings: ["today"]
        ),
        ExternalTextScenario(
            id: "07-last-transcription-one-sentence",
            name: "Last transcription one sentence",
            category: "single-source last transcription",
            dictatedContent: "Buddy, tighten my last transcription into one direct sentence",
            lastTranscription: "hey can you maybe take another look at the homepage copy because i think it is still too wordy and i want us to shorten it before launch",
            expectedBehavior: "Use last transcription and return exactly one concise sentence.",
            reviewFocus: [
                "The output should be one sentence.",
                "The homepage copy and launch timing should remain clear.",
            ],
            expectedProductionModes: [.lastTranscription],
            expectedPhraseOnlyModes: [.lastTranscription],
            expectedOutputSubstrings: ["homepage", "launch"]
        ),
        ExternalTextScenario(
            id: "08-selected-target-clipboard-irrelevant",
            name: "Selected target with irrelevant clipboard",
            category: "target source plus irrelevant available context",
            dictatedContent: "Buddy, rewrite the selected text as three bullets",
            selectedText: "The onboarding checklist still needs analytics validation, legal review, and support messaging before the rollout.",
            clipboardText: "Project Sequoia budget notes: do not include this in customer rollout messaging.",
            expectedBehavior: "Use only selected text; the unrelated clipboard should not leak into the output.",
            reviewFocus: [
                "The output should mention onboarding or rollout work.",
                "It should not mention Project Sequoia.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            expectedOutputSubstrings: ["analytics"],
            disallowedOutputSubstrings: ["Sequoia"]
        ),
        ExternalTextScenario(
            id: "09-selected-target-last-irrelevant",
            name: "Selected target with irrelevant last transcription",
            category: "target source plus irrelevant available context",
            dictatedContent: "Buddy, clean up what's selected",
            selectedText: "please send the migration recap to Priya before noon tomorrow",
            lastTranscription: "Remember to buy coffee filters and replace the hallway light.",
            expectedBehavior: "Use selected text only and ignore the irrelevant prior transcript.",
            reviewFocus: [
                "The output should preserve Priya and noon tomorrow.",
                "It should not mention household errands.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            expectedOutputSubstrings: ["Priya", "noon"],
            disallowedOutputSubstrings: ["coffee"]
        ),
        ExternalTextScenario(
            id: "10-clipboard-target-selected-irrelevant",
            name: "Clipboard target with irrelevant selected text",
            category: "target source plus irrelevant available context",
            dictatedContent: "Buddy, summarize my clipboard in one sentence",
            selectedText: "Ignore this selected draft about office lunch preferences.",
            clipboardText: "The beta cohort expanded to 42 accounts, but onboarding support is the current bottleneck. We need two more support owners before Monday.",
            expectedBehavior: "Use clipboard only and summarize it in one sentence.",
            reviewFocus: [
                "The output should preserve 42 accounts and support owners.",
                "It should not mention lunch preferences.",
            ],
            expectedProductionModes: [.clipboard],
            expectedPhraseOnlyModes: [.clipboard],
            expectedOutputSubstrings: ["42", "support"],
            disallowedOutputSubstrings: ["lunch"]
        ),
        ExternalTextScenario(
            id: "11-clipboard-target-last-irrelevant",
            name: "Clipboard target with irrelevant last transcription",
            category: "target source plus irrelevant available context",
            dictatedContent: "Buddy, make what I copied more polished",
            clipboardText: "can we please get the data export done today because finance is blocked",
            lastTranscription: "The selected vendor list needs a separate approval path.",
            expectedBehavior: "Use clipboard text only and make it more polished.",
            reviewFocus: [
                "The output should preserve finance being blocked today.",
                "It should not mention vendor approval.",
            ],
            expectedProductionModes: [.clipboard],
            expectedPhraseOnlyModes: [.clipboard],
            expectedOutputSubstrings: ["finance", "today"],
            disallowedOutputSubstrings: ["vendor"]
        ),
        ExternalTextScenario(
            id: "12-last-target-selected-irrelevant",
            name: "Last transcription target with irrelevant selected text",
            category: "target source plus irrelevant available context",
            dictatedContent: "Buddy, turn my last transcription into action items",
            selectedText: "Unrelated selected paragraph about the design library rename.",
            lastTranscription: "Ask Maria to confirm final QA coverage. Send support the rollout notes. Move launch review to Thursday.",
            expectedBehavior: "Use last transcription and return action items.",
            reviewFocus: [
                "The output should mention Maria, support, and Thursday.",
                "It should not mention design library rename.",
            ],
            expectedProductionModes: [.lastTranscription],
            expectedPhraseOnlyModes: [.lastTranscription],
            expectedOutputSubstrings: ["Maria", "Thursday"],
            disallowedOutputSubstrings: ["design library"]
        ),
        ExternalTextScenario(
            id: "13-last-target-clipboard-irrelevant",
            name: "Last transcription target with irrelevant clipboard",
            category: "target source plus irrelevant available context",
            dictatedContent: "Buddy, make my last transcription nicer and shorter",
            clipboardText: "Clipboard contains travel itinerary details for next month.",
            lastTranscription: "The current draft is confusing and we need to fix the launch section before it goes to leadership.",
            expectedBehavior: "Use last transcription only and soften the tone.",
            reviewFocus: [
                "The output should preserve the launch section and leadership.",
                "It should not mention travel itinerary details.",
            ],
            expectedProductionModes: [.lastTranscription],
            expectedPhraseOnlyModes: [.lastTranscription],
            expectedOutputSubstrings: ["launch", "leadership"],
            disallowedOutputSubstrings: ["travel"]
        ),
        ExternalTextScenario(
            id: "14-direct-draft-context-irrelevant",
            name: "Direct drafting request with all context available",
            category: "direct request with irrelevant available context",
            dictatedContent: "Buddy, draft a thank-you note for the team dinner",
            selectedText: "Selected source that should not be used: migration risk register.",
            clipboardText: "Clipboard source that should not be used: outage incident timeline.",
            lastTranscription: "Last transcription that should not be used: pricing escalation.",
            expectedBehavior: "Stay direct and draft the requested thank-you note without injecting any external context.",
            reviewFocus: [
                "The prompt should be direct, not context-injected.",
                "The output should not mention migration, outage, or pricing.",
            ],
            expectedProductionModes: [],
            expectedPhraseOnlyModes: [],
            disallowedOutputSubstrings: ["migration", "outage", "pricing"]
        ),
        ExternalTextScenario(
            id: "15-direct-explain-context-irrelevant",
            name: "Direct explanation request with all context available",
            category: "direct request with irrelevant available context",
            dictatedContent: "Buddy, explain the difference between latency and throughput",
            selectedText: "Selected text about next quarter hiring.",
            clipboardText: "Clipboard text about a customer renewal.",
            lastTranscription: "Prior dictation about a product launch.",
            expectedBehavior: "Stay direct and answer the conceptual question.",
            reviewFocus: [
                "The prompt should not inject available external context.",
                "The output should explain latency and throughput.",
            ],
            expectedProductionModes: [],
            expectedPhraseOnlyModes: [],
            expectedOutputSubstrings: ["latency", "throughput"],
            disallowedOutputSubstrings: ["hiring", "renewal"]
        ),
        ExternalTextScenario(
            id: "16-retry-no-context-reuse",
            name: "Retry phrasing should not reuse context",
            category: "direct request with irrelevant available context",
            dictatedContent: "Buddy, try that again",
            selectedText: "Selected text should not be reused.",
            clipboardText: "Clipboard text should not be reused.",
            lastTranscription: "Prior dictation should not be reused.",
            expectedBehavior: "Stay direct; this currently has no deterministic source reference.",
            reviewFocus: [
                "The prompt should be direct.",
                "The report should help decide whether retry behavior needs a separate feature.",
            ],
            expectedProductionModes: [],
            expectedPhraseOnlyModes: []
        ),
        ExternalTextScenario(
            id: "17-selected-clipboard-compare",
            name: "Compare selected text and clipboard",
            category: "multi-source",
            dictatedContent: "Buddy, compare the selected text with what I copied",
            selectedText: "Selected text says analytics validation is still incomplete.",
            clipboardText: "Copied text says support is ready for the Friday rollout.",
            expectedBehavior: "Use selected text and clipboard as source material.",
            reviewFocus: [
                "The output should compare both facts.",
                "It should not ignore either source.",
            ],
            expectedProductionModes: [.clipboard, .selectedText],
            expectedPhraseOnlyModes: [.clipboard, .selectedText],
            expectedOutputSubstrings: ["analytics", "support"]
        ),
        ExternalTextScenario(
            id: "18-selected-clipboard-merge",
            name: "Merge selected text and clipboard",
            category: "multi-source",
            dictatedContent: "Buddy, merge what's selected with what I copied into one clean update",
            selectedText: "Analytics validation is still incomplete.",
            clipboardText: "Support is ready for Friday rollout communications.",
            expectedBehavior: "Merge selected text and clipboard into a single update.",
            reviewFocus: [
                "The output should include both analytics validation and support readiness.",
                "It should be one coherent update rather than two unrelated blocks.",
            ],
            expectedProductionModes: [.clipboard, .selectedText],
            expectedPhraseOnlyModes: [.clipboard, .selectedText],
            expectedOutputSubstrings: ["analytics", "support"]
        ),
        ExternalTextScenario(
            id: "19-last-clipboard-combine",
            name: "Combine last transcription and clipboard",
            category: "multi-source",
            dictatedContent: "Buddy, combine my last transcription and my clipboard into bullets",
            clipboardText: "Clipboard: customer comms need approval by Wednesday.",
            lastTranscription: "Last transcription: analytics review is still blocking the launch.",
            expectedBehavior: "Use last transcription and clipboard, then return bullets.",
            reviewFocus: [
                "The output should include approval by Wednesday and analytics blocking launch.",
                "It should format as bullets.",
            ],
            expectedProductionModes: [.lastTranscription, .clipboard],
            expectedPhraseOnlyModes: [.lastTranscription, .clipboard],
            expectedOutputSubstrings: ["Wednesday", "analytics"]
        ),
        ExternalTextScenario(
            id: "20-three-source-status-update",
            name: "Three-source status update",
            category: "multi-source",
            dictatedContent: "Buddy, merge my last transcription with what I copied and what's selected into one clean status update",
            selectedText: "Selected: analytics still needs validation.",
            clipboardText: "Clipboard: support should be notified by Thursday afternoon.",
            lastTranscription: "Last transcription: rollout should move to Friday.",
            expectedBehavior: "Use all three sources and produce one clean status update.",
            reviewFocus: [
                "The output should include analytics, support, Thursday afternoon, and Friday.",
                "It should not privilege only one source.",
            ],
            expectedProductionModes: [.lastTranscription, .clipboard, .selectedText],
            expectedPhraseOnlyModes: [.lastTranscription, .clipboard, .selectedText],
            expectedOutputSubstrings: ["analytics", "support", "Thursday", "Friday"]
        ),
        ExternalTextScenario(
            id: "21-three-source-contradiction-check",
            name: "Three-source contradiction check",
            category: "multi-source",
            dictatedContent: "Buddy, compare my last transcription, my clipboard, and the selected text for contradictions",
            selectedText: "Selected text says launch remains Friday.",
            clipboardText: "Clipboard says launch moved to Monday.",
            lastTranscription: "Last transcription says support has not reviewed launch notes yet.",
            expectedBehavior: "Use all three sources and identify the Friday versus Monday contradiction.",
            reviewFocus: [
                "The output should identify the date conflict.",
                "It should preserve the support review status.",
            ],
            expectedProductionModes: [.lastTranscription, .clipboard, .selectedText],
            expectedPhraseOnlyModes: [.lastTranscription, .clipboard, .selectedText],
            expectedOutputSubstrings: ["Friday", "Monday"]
        ),
        ExternalTextScenario(
            id: "22-selected-last-compare",
            name: "Compare selected text and last transcription",
            category: "multi-source",
            dictatedContent: "Buddy, compare the selected text with my last transcription",
            selectedText: "Selected text says the design handoff is complete.",
            lastTranscription: "Last transcription says engineering is still waiting for final design assets.",
            expectedBehavior: "Use selected text and last transcription and compare them.",
            reviewFocus: [
                "The output should notice the handoff/completion mismatch.",
                "It should not ask for either source.",
            ],
            expectedProductionModes: [.lastTranscription, .selectedText],
            expectedPhraseOnlyModes: [.lastTranscription, .selectedText],
            expectedOutputSubstrings: ["design"]
        ),
        ExternalTextScenario(
            id: "23-highlighted-text-phrase",
            name: "Highlighted text phrase",
            category: "phrase variants",
            dictatedContent: "Buddy, make the highlighted text more concise",
            selectedText: "The rollout timeline is probably going to need to move because analytics validation has not finished yet.",
            expectedBehavior: "Map highlighted text to selected text and rewrite it concisely.",
            reviewFocus: [
                "The classifier should route to selected text.",
                "The output should preserve analytics validation.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            expectedOutputSubstrings: ["analytics"]
        ),
        ExternalTextScenario(
            id: "24-thing-i-copied-phrase",
            name: "Thing I copied phrase",
            category: "phrase variants",
            dictatedContent: "Buddy, turn the thing I copied into a polished sentence",
            clipboardText: "the customer renewal is blocked until legal approves the updated terms",
            expectedBehavior: "Map the thing I copied to clipboard text.",
            reviewFocus: [
                "The classifier should route to clipboard.",
                "The output should preserve legal approval and updated terms.",
            ],
            expectedProductionModes: [.clipboard],
            expectedPhraseOnlyModes: [.clipboard],
            expectedOutputSubstrings: ["legal", "terms"]
        ),
        ExternalTextScenario(
            id: "25-what-i-just-said-phrase",
            name: "What I just said phrase",
            category: "phrase variants",
            dictatedContent: "Buddy, make what I just said more professional",
            lastTranscription: "the onboarding flow is confusing and we need to fix it before more customers hit it",
            expectedBehavior: "Map what I just said to last transcription.",
            reviewFocus: [
                "The classifier should route to last transcription.",
                "The output should preserve onboarding flow and customers.",
            ],
            expectedProductionModes: [.lastTranscription],
            expectedPhraseOnlyModes: [.lastTranscription],
            expectedOutputSubstrings: ["onboarding"]
        ),
        ExternalTextScenario(
            id: "26-this-text-selected-phrase",
            name: "This text selected phrase",
            category: "phrase variants",
            dictatedContent: "Buddy, make this text friendlier",
            selectedText: "You missed the deadline again and this is causing problems for everyone.",
            expectedBehavior: "Map this text to selected text and soften it.",
            reviewFocus: [
                "The classifier should route to selected text.",
                "The output should preserve the missed deadline problem without attacking the person.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            expectedOutputSubstrings: ["deadline"]
        ),
        ExternalTextScenario(
            id: "27-that-paragraph-selected-phrase",
            name: "That paragraph selected phrase",
            category: "phrase variants",
            dictatedContent: "Buddy, rewrite that paragraph as bullets",
            selectedText: "We need legal approval, final analytics validation, and support messaging before the customer announcement.",
            expectedBehavior: "Map that paragraph to selected text and return bullets.",
            reviewFocus: [
                "The classifier should route to selected text.",
                "The output should preserve all three requirements.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            expectedOutputSubstrings: ["legal", "analytics", "support"]
        ),
        ExternalTextScenario(
            id: "28-what-i-have-copied-phrase",
            name: "What I have copied phrase",
            category: "phrase variants",
            dictatedContent: "Buddy, summarize what I have copied",
            clipboardText: "The billing migration is ready for internal testing, but the customer-facing launch should wait until support has updated macros.",
            expectedBehavior: "Map what I have copied to clipboard text and summarize it.",
            reviewFocus: [
                "The classifier should route to clipboard.",
                "The output should preserve internal testing and support macros.",
            ],
            expectedProductionModes: [.clipboard],
            expectedPhraseOnlyModes: [.clipboard],
            expectedOutputSubstrings: ["billing", "support"]
        ),
        ExternalTextScenario(
            id: "29-selected-request-unavailable-clipboard-exists",
            name: "Selected text requested but unavailable",
            category: "capture gap",
            dictatedContent: "Buddy, rewrite what's selected",
            selectedText: nil,
            clipboardText: "Clipboard fallback: analytics review is complete, but support still needs launch notes.",
            lastTranscription: "Last transcription fallback: launch may move to Friday.",
            expectedBehavior: "Current production routing will stay direct because selected text is unavailable; phrase-only routing should reveal the selected-text reference.",
            reviewFocus: [
                "This exposes the availability-gated classifier behavior.",
                "If the model says it needs selected text, that is expected under the current architecture.",
            ],
            expectedProductionModes: [],
            expectedPhraseOnlyModes: [.selectedText]
        ),
        ExternalTextScenario(
            id: "30-clipboard-request-unavailable-selected-exists",
            name: "Clipboard requested but unavailable",
            category: "capture gap",
            dictatedContent: "Buddy, summarize my clipboard",
            selectedText: "Selected fallback: migration risks are low after the final QA pass.",
            clipboardText: nil,
            lastTranscription: "Last transcription fallback: support is ready.",
            expectedBehavior: "Current production routing will stay direct because clipboard text is unavailable; phrase-only routing should reveal the clipboard reference.",
            reviewFocus: [
                "This shows whether a future repair path should attach selected or transcript context.",
                "The current prompt should not pretend clipboard content exists.",
            ],
            expectedProductionModes: [],
            expectedPhraseOnlyModes: [.clipboard]
        ),
        ExternalTextScenario(
            id: "31-last-request-unavailable-context-exists",
            name: "Last transcription requested but unavailable",
            category: "capture gap",
            dictatedContent: "Buddy, fix my last transcription",
            selectedText: "Selected fallback: customer comms need approval by Wednesday.",
            clipboardText: "Clipboard fallback: analytics validation is complete.",
            lastTranscription: nil,
            expectedBehavior: "Current production routing will stay direct because last transcription is unavailable; phrase-only routing should reveal the transcript reference.",
            reviewFocus: [
                "This isolates last-transcription availability failures.",
                "The current model prompt should be direct and likely ask for missing text or infer nothing.",
            ],
            expectedProductionModes: [],
            expectedPhraseOnlyModes: [.lastTranscription]
        ),
        ExternalTextScenario(
            id: "32-multi-source-one-unavailable",
            name: "Selected and clipboard requested but clipboard unavailable",
            category: "capture gap",
            dictatedContent: "Buddy, compare what's selected with what I copied",
            selectedText: "Selected text says launch remains Friday.",
            clipboardText: nil,
            lastTranscription: "Last transcription fallback says launch moved to Monday.",
            expectedBehavior: "Current production routing will include selected text only; phrase-only routing should reveal selected and clipboard.",
            reviewFocus: [
                "This shows partial multi-source degradation.",
                "The output may only compare selected text to nothing under the current architecture.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.clipboard, .selectedText],
            expectedOutputSubstrings: ["Friday"]
        ),
        ExternalTextScenario(
            id: "33-multi-source-selected-unavailable",
            name: "Selected and clipboard requested but selected unavailable",
            category: "capture gap",
            dictatedContent: "Buddy, compare the selected text with my clipboard",
            selectedText: nil,
            clipboardText: "Clipboard text says launch moved to Monday.",
            lastTranscription: "Last transcription fallback says support is not ready.",
            expectedBehavior: "Current production routing will include clipboard only; phrase-only routing should reveal selected and clipboard.",
            reviewFocus: [
                "This shows the mirror partial failure of scenario 32.",
                "The output should not claim it compared selected text if only clipboard was injected.",
            ],
            expectedProductionModes: [.clipboard],
            expectedPhraseOnlyModes: [.clipboard, .selectedText],
            expectedOutputSubstrings: ["Monday"]
        ),
        ExternalTextScenario(
            id: "34-plural-transcriptions-direct",
            name: "Plural transcriptions should stay direct",
            category: "false-positive guard",
            dictatedContent: "Buddy, write a policy for reviewing old transcriptions later",
            selectedText: "Selected text should not be injected.",
            clipboardText: "Clipboard text should not be injected.",
            lastTranscription: "Last transcription should not be injected.",
            expectedBehavior: "Stay direct; plural transcriptions must not trigger last-transcription routing.",
            reviewFocus: [
                "The classifier should not match last transcription.",
                "The output should be a policy, not a rewrite of available context.",
            ],
            expectedProductionModes: [],
            expectedPhraseOnlyModes: [],
            expectedOutputSubstrings: ["policy"]
        ),
        ExternalTextScenario(
            id: "35-selection-page-direct",
            name: "Selection page should stay direct",
            category: "false-positive guard",
            dictatedContent: "Buddy, draft copy for the selection page in onboarding",
            selectedText: "Selected text should not be injected.",
            clipboardText: "Clipboard text should not be injected.",
            expectedBehavior: "Stay direct; selection page should not match selected text.",
            reviewFocus: [
                "The classifier should not route to selected text.",
                "The output should draft onboarding page copy.",
            ],
            expectedProductionModes: [],
            expectedPhraseOnlyModes: [],
            expectedOutputSubstrings: ["onboarding"]
        ),
        ExternalTextScenario(
            id: "36-slacking-not-slack-format",
            name: "Slacking should not imply Slack format",
            category: "false-positive guard",
            dictatedContent: "Buddy, summarize my clipboard about people slacking off",
            clipboardText: "Team feedback says follow-through has been inconsistent and several owners missed their updates.",
            expectedBehavior: "Use clipboard as source, but do not force Slack-message formatting from the word slacking.",
            reviewFocus: [
                "The classifier should route to clipboard.",
                "The output should summarize the feedback rather than produce an explicitly Slack-ready message.",
            ],
            expectedProductionModes: [.clipboard],
            expectedPhraseOnlyModes: [.clipboard],
            expectedOutputSubstrings: ["follow"]
        ),
        ExternalTextScenario(
            id: "37-quality-selected-urgent-professional",
            name: "Selected text urgent professional rewrite",
            category: "quality evaluation",
            dictatedContent: "Buddy, make what's selected much more professional but keep the urgency",
            selectedText: "Jordan, this migration plan is still all over the place. The analytics backfill is late, support has no macros, and finance is blocked on the export. I need the revised plan by 3 PM today, not another vague update.",
            clipboardText: "Unrelated clipboard: lunch headcount is due tomorrow.",
            expectedBehavior: "Rewrite the selected text professionally while preserving the deadline, urgency, and concrete blockers.",
            reviewFocus: [
                "The output should soften the criticism without removing urgency.",
                "It should preserve Jordan, analytics, support, finance, and 3 PM today.",
                "It should ignore the unrelated clipboard text.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            qualityChecks: [
                .contains("Jordan"),
                .contains("analytics"),
                .contains("support"),
                .contains("finance"),
                .contains("3 PM"),
                .contains("today"),
                .omits("all over the place"),
                .omits("lunch"),
                .wordCountAtMost(90),
                .doesNotAskForMoreInput(),
            ]
        ),
        ExternalTextScenario(
            id: "38-quality-clipboard-exec-bullets",
            name: "Clipboard to executive bullets",
            category: "quality evaluation",
            dictatedContent: "Buddy, turn what I copied into three bullets for an exec update",
            clipboardText: "Raw notes: The beta migration is still tracking for Friday, but the analytics backfill finished six hours later than planned. Support has drafted macros but needs legal approval before sending them to customers. Finance confirmed the export blocker is resolved. Product wants leadership to understand this is a schedule risk, not a scope change.",
            lastTranscription: "Unrelated prior dictation: remember to update the office seating chart.",
            expectedBehavior: "Produce exactly three executive-ready bullets from clipboard content only.",
            reviewFocus: [
                "The output should be exactly three bullets.",
                "It should preserve Friday, six-hour delay, support/legal approval, and finance blocker resolution.",
                "It should not include unrelated prior dictation.",
            ],
            expectedProductionModes: [.clipboard],
            expectedPhraseOnlyModes: [.clipboard],
            qualityChecks: [
                .bulletCount(3),
                .contains("Friday"),
                .containsAny(["six hours", "6 hours", "six-hour"], description: "Preserves six-hour analytics delay"),
                .contains("support"),
                .contains("legal"),
                .contains("finance"),
                .omits("seating"),
                .doesNotAskForMoreInput(),
            ]
        ),
        ExternalTextScenario(
            id: "39-quality-last-transcription-action-items",
            name: "Last transcription to action items",
            category: "quality evaluation",
            dictatedContent: "Buddy, turn my last transcription into a clean action-item list",
            selectedText: "Unrelated selected text: office snacks need restocking.",
            lastTranscription: "Maria needs to confirm QA coverage for the billing retry path before Wednesday morning. Lee should send the support macros to legal today. I need to update the launch note with the Monday backup plan. Finance already cleared the export blocker, so do not list that as open.",
            expectedBehavior: "Use the prior transcript and return actionable open items without turning completed finance work into a task.",
            reviewFocus: [
                "The output should include Maria, Lee, and the launch-note update.",
                "It should not list the cleared finance blocker as open work.",
                "It should ignore unrelated selected text.",
            ],
            expectedProductionModes: [.lastTranscription],
            expectedPhraseOnlyModes: [.lastTranscription],
            qualityChecks: [
                .bulletCountAtLeast(3),
                .contains("Maria"),
                .contains("QA"),
                .contains("Wednesday"),
                .contains("Lee"),
                .contains("legal"),
                .contains("Monday"),
                .omits("snacks"),
                .omits("Finance", description: "Does not include the completed finance blocker as an action item"),
                .omits("export blocker", description: "Does not include the cleared export blocker as open work"),
                .doesNotAskForMoreInput(),
            ]
        ),
        ExternalTextScenario(
            id: "40-quality-selected-one-sentence-summary",
            name: "Selected text one-sentence changelog summary",
            category: "quality evaluation",
            dictatedContent: "Buddy, summarize this text in one sentence for the changelog",
            selectedText: "We fixed a billing export retry bug that caused duplicate CSV rows when a customer re-ran a failed export within ten minutes. The fix adds idempotency keys to retry jobs, backfills the missing audit IDs, and improves logging for support escalations.",
            clipboardText: "Unrelated clipboard: Project Poppy launch copy should stay confidential.",
            expectedBehavior: "Summarize selected text in exactly one changelog-ready sentence and ignore the clipboard.",
            reviewFocus: [
                "The output should be exactly one sentence.",
                "It should mention billing/export retry and duplicate rows or idempotency.",
                "It should not mention Project Poppy.",
            ],
            expectedProductionModes: [.selectedText],
            expectedPhraseOnlyModes: [.selectedText],
            qualityChecks: [
                .exactlyOneSentence(),
                .contains("billing"),
                .contains("export"),
                .containsAny(["duplicate", "idempotency", "retry"], description: "Mentions duplicate rows, idempotency, or retry behavior"),
                .omits("Poppy"),
                .wordCountAtMost(45),
            ]
        ),
        ExternalTextScenario(
            id: "41-quality-selected-clipboard-contradiction",
            name: "Selected and clipboard contradiction check",
            category: "quality evaluation",
            dictatedContent: "Buddy, compare the selected text with what I copied and tell me if they conflict",
            selectedText: "Selected source: customer launch remains scheduled for Friday, and support macros are approved.",
            clipboardText: "Copied source: customer launch moved to Monday because support macros still need legal approval.",
            expectedBehavior: "Use both sources and clearly identify the date and support/legal conflicts.",
            reviewFocus: [
                "The output should mention Friday and Monday.",
                "It should identify a conflict rather than merge the facts as compatible.",
                "It should mention the support/legal approval mismatch.",
            ],
            expectedProductionModes: [.clipboard, .selectedText],
            expectedPhraseOnlyModes: [.clipboard, .selectedText],
            qualityChecks: [
                .contains("Friday"),
                .contains("Monday"),
                .containsAny(["conflict", "contradict", "mismatch", "inconsistent"], description: "Identifies a conflict"),
                .contains("support"),
                .contains("legal"),
                .doesNotAskForMoreInput(),
            ]
        ),
        ExternalTextScenario(
            id: "42-quality-direct-draft-ignores-context",
            name: "Direct apology draft ignores available context",
            category: "quality evaluation",
            dictatedContent: "Buddy, write a short apology note for missing a customer meeting",
            selectedText: "Selected text that should not be used: launch is delayed because analytics is incomplete.",
            clipboardText: "Clipboard text that should not be used: finance export blocker was resolved today.",
            lastTranscription: "Prior dictation that should not be used: legal approval is still pending.",
            expectedBehavior: "Stay direct and draft an apology note without leaking available context.",
            reviewFocus: [
                "The output should be an apology for missing a customer meeting.",
                "It should not mention launch, analytics, finance, export, or legal.",
                "It should stay short.",
            ],
            expectedProductionModes: [],
            expectedPhraseOnlyModes: [],
            qualityChecks: [
                .containsAny(["sorry", "apolog"], description: "Includes an apology"),
                .contains("meeting"),
                .contains("customer"),
                .omits("launch"),
                .omits("analytics"),
                .omits("finance"),
                .omits("export"),
                .omits("legal"),
                .omits("Buddy", description: "Does not sign or speak as Buddy"),
                .wordCountAtMost(80),
            ]
        ),
    ]
}
