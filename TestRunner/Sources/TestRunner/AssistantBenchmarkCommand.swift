import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon

struct AssistantBenchmarkCommand {
    func run(arguments: [String]) async {
        do {
            let config = try BenchmarkCLIConfig(arguments: arguments)
            let runner = try AssistantBenchmarkRunner(config: config)
            try await runner.run()
        } catch {
            fputs("assistant-benchmark failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct BenchmarkCLIConfig {
    let assistantName: String
    let tiers: [ModelTier]
    let outputDirectory: URL
    let scenarioIDs: Set<String>?
    let customTranscript: String?
    let customTitle: String

    init(arguments: [String]) throws {
        var assistantName = "Ava"
        var tiers: [ModelTier] = [.qwen2B, .qwen4B]
        var outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/assistant-benchmark", isDirectory: true)
        var scenarioIDs: Set<String>?
        var customTranscript: String?
        var customTitle = "Custom Scenario"

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--assistant-name":
                index += 1
                guard index < arguments.count else { throw BenchmarkError.invalidCLI("--assistant-name requires a value") }
                assistantName = arguments[index]
            case "--tiers":
                index += 1
                guard index < arguments.count else { throw BenchmarkError.invalidCLI("--tiers requires a value") }
                tiers = try arguments[index]
                    .split(separator: ",")
                    .map { try ModelTier(rawCLIValue: String($0)) }
            case "--output-dir":
                index += 1
                guard index < arguments.count else { throw BenchmarkError.invalidCLI("--output-dir requires a value") }
                outputDirectory = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--scenario-ids":
                index += 1
                guard index < arguments.count else { throw BenchmarkError.invalidCLI("--scenario-ids requires a value") }
                scenarioIDs = Set(
                    arguments[index]
                        .split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                )
            case "--custom-transcript":
                index += 1
                guard index < arguments.count else { throw BenchmarkError.invalidCLI("--custom-transcript requires a value") }
                customTranscript = arguments[index]
            case "--custom-title":
                index += 1
                guard index < arguments.count else { throw BenchmarkError.invalidCLI("--custom-title requires a value") }
                customTitle = arguments[index]
            default:
                throw BenchmarkError.invalidCLI("Unknown argument: \(arg)")
            }
            index += 1
        }

        self.assistantName = assistantName
        self.tiers = tiers
        self.outputDirectory = outputDirectory
        self.scenarioIDs = scenarioIDs
        self.customTranscript = customTranscript
        self.customTitle = customTitle
    }
}

private enum BenchmarkError: LocalizedError {
    case invalidCLI(String)
    case localModelNotFound(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCLI(let message):
            return message
        case .localModelNotFound(let path):
            return "Local model directory not found: \(path)"
        case .generationFailed(let message):
            return message
        }
    }
}

private enum ModelTier: String, CaseIterable {
    case qwen2B = "2b"
    case qwen4B = "4b"

    init(rawCLIValue: String) throws {
        switch rawCLIValue.lowercased() {
        case "2b", "qwen2b", "qwen3.5-2b":
            self = .qwen2B
        case "4b", "5b", "qwen4b", "qwen3.5-4b":
            self = .qwen4B
        default:
            throw BenchmarkError.invalidCLI("Unsupported tier: \(rawCLIValue)")
        }
    }

    var label: String {
        switch self {
        case .qwen2B: return "Qwen 3.5 2B"
        case .qwen4B: return "Qwen 3.5 4B"
        }
    }

    var directoryName: String {
        switch self {
        case .qwen2B: return "Qwen3.5-2B-OptiQ-4bit"
        case .qwen4B: return "Qwen3.5-4B-OptiQ-4bit"
        }
    }

    var maxTokens: Int {
        switch self {
        case .qwen2B: return 1_024
        case .qwen4B: return 1_536
        }
    }
}

private enum PromptStyle: String, CaseIterable {
    case split
    case combined

    var label: String {
        rawValue
    }
}

private struct BenchmarkScenario {
    let id: String
    let title: String
    let transcriptTemplate: String
    let intent: String
    let checks: [OutputCheck]

    func transcript(assistantName: String) -> String {
        transcriptTemplate.replacingOccurrences(of: "{{ASSISTANT}}", with: assistantName)
    }
}

private enum OutputCheck {
    case contains(String)
    case notContains(String)
    case lineCountAtLeast(Int)
    case oneOf([String])
    case orderedNumbers([String])
    case jsonLike

    func evaluate(_ output: String) -> Bool {
        switch self {
        case .contains(let token):
            return output.localizedCaseInsensitiveContains(token)
        case .notContains(let token):
            return !output.localizedCaseInsensitiveContains(token)
        case .lineCountAtLeast(let minimum):
            return output.split(separator: "\n", omittingEmptySubsequences: true).count >= minimum
        case .oneOf(let values):
            return values.contains { output.localizedCaseInsensitiveContains($0) }
        case .orderedNumbers(let values):
            var cursor = output.startIndex
            for value in values {
                guard let range = output.range(of: value, options: [.caseInsensitive], range: cursor..<output.endIndex) else {
                    return false
                }
                cursor = range.upperBound
            }
            return true
        case .jsonLike:
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.first == "{" || trimmed.first == "["
        }
    }

    var label: String {
        switch self {
        case .contains(let token): return "contains(\(token))"
        case .notContains(let token): return "notContains(\(token))"
        case .lineCountAtLeast(let minimum): return "lineCountAtLeast(\(minimum))"
        case .oneOf(let values): return "oneOf(\(values.joined(separator: "|")))"
        case .orderedNumbers(let values): return "orderedNumbers(\(values.joined(separator: ",")))"
        case .jsonLike: return "jsonLike"
        }
    }
}

private struct ParsedSplit {
    let matchedAlias: String?
    let content: String
    let instructions: String?
}

private struct ScenarioRunResult: Codable {
    let tier: String
    let style: String
    let scenarioID: String
    let scenarioTitle: String
    let transcript: String
    let content: String?
    let instructions: String?
    let durationSeconds: Double
    let output: String
    let passedChecks: [String]
    let failedChecks: [String]
}

private final class AssistantBenchmarkRunner {
    private let config: BenchmarkCLIConfig
    private let scenarios: [BenchmarkScenario]
    private let outputDate = Date()

    init(config: BenchmarkCLIConfig) throws {
        self.config = config
        if let customTranscript = config.customTranscript {
            self.scenarios = [
                BenchmarkScenario(
                    id: "CUSTOM",
                    title: config.customTitle,
                    transcriptTemplate: customTranscript,
                    intent: "Ad hoc mixed utterance supplied at runtime.",
                    checks: []
                )
            ]
        } else {
            let allScenarios = Self.makeScenarios()
            if let scenarioIDs = config.scenarioIDs, !scenarioIDs.isEmpty {
                self.scenarios = allScenarios.filter { scenarioIDs.contains($0.id.uppercased()) }
            } else {
                self.scenarios = allScenarios
            }
        }
    }

    func run() async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: config.outputDirectory, withIntermediateDirectories: true)

        let stamp = Self.timestampFormatter.string(from: outputDate)
        let markdownURL = config.outputDirectory.appendingPathComponent("assistant-benchmark-\(stamp).md")
        let jsonURL = config.outputDirectory.appendingPathComponent("assistant-benchmark-\(stamp).json")

        var results: [ScenarioRunResult] = []

        for tier in config.tiers {
            print("\n=== Loading \(tier.label) ===")
            let engine = try LocalChatEngine(tier: tier)
            try await engine.load()

            for scenario in scenarios {
                print("\n[\(tier.rawValue)] \(scenario.id) \(scenario.title)")
                let transcript = scenario.transcript(assistantName: config.assistantName)

                for style in PromptStyle.allCases {
                    print("  -> \(style.label)")
                    let prompt = makePrompt(
                        style: style,
                        transcript: transcript,
                        assistantName: config.assistantName
                    )

                    let started = CFAbsoluteTimeGetCurrent()
                    let output = try await engine.generate(
                        systemPrompt: prompt.systemPrompt,
                        userPrompt: prompt.userPrompt
                    )
                    let durationSeconds = CFAbsoluteTimeGetCurrent() - started

                    let evaluation = evaluate(output: output, checks: scenario.checks)
                    let result = ScenarioRunResult(
                        tier: tier.rawValue,
                        style: style.rawValue,
                        scenarioID: scenario.id,
                        scenarioTitle: scenario.title,
                        transcript: transcript,
                        content: prompt.contentForReport,
                        instructions: prompt.instructionsForReport,
                        durationSeconds: durationSeconds,
                        output: output,
                        passedChecks: evaluation.passed,
                        failedChecks: evaluation.failed
                    )
                    results.append(result)

                    let status = evaluation.failed.isEmpty ? "pass" : "check-fail"
                    print("     \(status) \(String(format: "%.2fs", durationSeconds))")
                }
            }
        }

        try writeMarkdown(results: results, to: markdownURL)
        try writeJSON(results: results, to: jsonURL)

        print("\nWrote markdown report: \(markdownURL.path)")
        print("Wrote JSON report: \(jsonURL.path)")
    }

    private func evaluate(output: String, checks: [OutputCheck]) -> (passed: [String], failed: [String]) {
        var passed: [String] = []
        var failed: [String] = []

        for check in checks {
            if check.evaluate(output) {
                passed.append(check.label)
            } else {
                failed.append(check.label)
            }
        }

        return (passed, failed)
    }

    private func makePrompt(style: PromptStyle, transcript: String, assistantName: String) -> BenchmarkPrompt {
        switch style {
        case .split:
            let parsed = Self.parseSplit(
                transcript: transcript,
                assistantName: assistantName
            )
            let systemPrompt = """
            You are a local text rewriting assistant.
            Follow the rewrite instructions exactly.
            Return only the final rewritten text.
            Do not explain your changes.
            Do not include labels, quotes, code fences, or <think> tags.

            Rewrite instructions:
            \(parsed.instructions ?? "Return the source text exactly as written.")
            """

            return BenchmarkPrompt(
                systemPrompt: systemPrompt,
                userPrompt: parsed.content,
                contentForReport: parsed.content,
                instructionsForReport: parsed.instructions
            )
        case .combined:
            return BenchmarkPrompt(
                systemPrompt: Self.makeAssistantSystemPrompt(assistantName: assistantName),
                userPrompt: transcript,
                contentForReport: transcript,
                instructionsForReport: nil
            )
        }
    }

    private func writeMarkdown(results: [ScenarioRunResult], to url: URL) throws {
        var lines: [String] = []
        lines.append("# Assistant Trigger Benchmark")
        lines.append("")
        lines.append("- Assistant name: `\(config.assistantName)`")
        lines.append("- Models: `\(config.tiers.map(\.rawValue).joined(separator: ", "))`")
        lines.append("- Scenarios: `\(scenarios.count)`")
        lines.append("- Generated: `\(Self.humanDateFormatter.string(from: outputDate))`")
        lines.append("")

        for tier in config.tiers {
            lines.append("## \(tier.label)")
            lines.append("")
            let tierResults = results.filter { $0.tier == tier.rawValue }
            let splitPasses = tierResults.filter { $0.style == PromptStyle.split.rawValue && $0.failedChecks.isEmpty }.count
            let combinedPasses = tierResults.filter { $0.style == PromptStyle.combined.rawValue && $0.failedChecks.isEmpty }.count
            lines.append("- Split full-check passes: `\(splitPasses)/\(scenarios.count)`")
            lines.append("- Combined full-check passes: `\(combinedPasses)/\(scenarios.count)`")
            lines.append("")

            for scenario in scenarios {
                lines.append("### \(scenario.id) \(scenario.title)")
                lines.append("")
                lines.append("Intent: \(scenario.intent)")
                lines.append("")

                let pair = tierResults.filter { $0.scenarioID == scenario.id }
                for result in pair.sorted(by: { $0.style < $1.style }) {
                    lines.append("#### \(result.style.capitalized)")
                    lines.append("")
                    lines.append("- Duration: `\(String(format: "%.2f", result.durationSeconds))s`")
                    lines.append("- Passed checks: `\(result.passedChecks.count)`")
                    if !result.failedChecks.isEmpty {
                        lines.append("- Failed checks: `\(result.failedChecks.joined(separator: ", "))`")
                    }
                    lines.append("")
                    lines.append("Transcript:")
                    lines.append("```text")
                    lines.append(result.transcript)
                    lines.append("```")
                    if let instructions = result.instructions {
                        lines.append("Instructions:")
                        lines.append("```text")
                        lines.append(instructions)
                        lines.append("```")
                    }
                    if let content = result.content {
                        lines.append("Prompt content:")
                        lines.append("```text")
                        lines.append(content)
                        lines.append("```")
                    }
                    lines.append("Output:")
                    lines.append("```text")
                    lines.append(result.output)
                    lines.append("```")
                    lines.append("")
                }
            }
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeJSON(results: [ScenarioRunResult], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(results)
        try data.write(to: url)
    }

    private static func parseSplit(transcript: String, assistantName: String) -> ParsedSplit {
        let aliases = [
            assistantName.lowercased(),
            "assistant \(assistantName.lowercased())",
            "hey \(assistantName.lowercased())"
        ]
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedSplit(matchedAlias: nil, content: "", instructions: nil)
        }

        var bestRange: NSRange?
        var bestAlias: String?
        let searchRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)

        for alias in aliases {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: alias))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            regex.enumerateMatches(in: trimmed, options: [], range: searchRange) { match, _, _ in
                guard let match else { return }
                if let current = bestRange {
                    if match.range.location > current.location ||
                        (match.range.location == current.location && match.range.length > current.length) {
                        bestRange = match.range
                        bestAlias = alias
                    }
                } else {
                    bestRange = match.range
                    bestAlias = alias
                }
            }
        }

        guard let bestRange, let range = Range(bestRange, in: trimmed) else {
            return ParsedSplit(matchedAlias: nil, content: trimmed, instructions: nil)
        }

        let content = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawInstructions = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = rawInstructions
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.:;")))

        return ParsedSplit(
            matchedAlias: bestAlias,
            content: content,
            instructions: instructions.isEmpty ? nil : instructions
        )
    }

    private static func makeAssistantSystemPrompt(assistantName: String) -> String {
        let template = """
        You are {{assistant_name}}, a local voice assistant embedded in a speech transcription app.
        The user may mix source material and instructions in one continuous utterance.
        If the message mentions {{assistant_name}} anywhere, infer the intended task and return only the requested final artifact.
        Preserve important concrete details from the utterance.
        Do not explain your reasoning.
        Do not include labels, quotes, code fences, or <think> tags unless the user explicitly asks for them.
        """

        return template.replacingOccurrences(of: "{{assistant_name}}", with: assistantName)
    }

    private static func makeScenarios() -> [BenchmarkScenario] {
        [
            BenchmarkScenario(
                id: "S01",
                title: "Basic Cleanup",
                transcriptTemplate: "um I think we should probably move the deadline to next Wednesday because QA still needs a day {{ASSISTANT}} remove filler words and make this one clean sentence",
                intent: "Classic current-style rewrite where the source comes before the assistant trigger.",
                checks: [.contains("next Wednesday"), .contains("QA"), .notContains("um"), .notContains("probably")]
            ),
            BenchmarkScenario(
                id: "S02",
                title: "Sort Numbers",
                transcriptTemplate: "9 1 14 13 12 15 {{ASSISTANT}} put these in ascending order separated by commas",
                intent: "Structured transformation with an objective expected ordering.",
                checks: [.orderedNumbers(["1", "9", "12", "13", "14", "15"])]
            ),
            BenchmarkScenario(
                id: "S03",
                title: "Bulleted Meeting Notes",
                transcriptTemplate: "Roadmap review notes timeline slips two weeks design owes final mocks and Derek will own rollout comms {{ASSISTANT}} format these as three concise bullet points",
                intent: "Formatting-heavy rewrite with a stable output shape.",
                checks: [.lineCountAtLeast(3), .contains("Derek"), .contains("two weeks")]
            ),
            BenchmarkScenario(
                id: "S04",
                title: "JSON Extraction",
                transcriptTemplate: "Customer issue high priority bug on iOS login screen owner Priya due Monday {{ASSISTANT}} return valid JSON with keys issue priority owner due",
                intent: "Schema-constrained output.",
                checks: [.jsonLike, .contains("Priya"), .contains("Monday"), .contains("priority")]
            ),
            BenchmarkScenario(
                id: "S05",
                title: "Slack Message",
                transcriptTemplate: "Tell the team the deploy is done and monitoring looks normal {{ASSISTANT}} make this a short friendly Slack message",
                intent: "Classic split case with source first and instructions second.",
                checks: [.contains("deploy"), .contains("monitoring")]
            ),
            BenchmarkScenario(
                id: "S06",
                title: "Spanish Translation",
                transcriptTemplate: "The vendor pushed the invoice review to Friday afternoon {{ASSISTANT}} translate this into natural Spanish",
                intent: "Language translation on a straightforward split input.",
                checks: [.oneOf(["viernes", "tarde"]), .notContains("vendor")]
            ),
            BenchmarkScenario(
                id: "S07",
                title: "Assistant Name At Start",
                transcriptTemplate: "{{ASSISTANT}} write a polite follow-up email saying thanks for the demo we want pricing for fifty seats and we can meet Tuesday afternoon",
                intent: "Continuous-message case where the current split path loses the body because the assistant name comes first.",
                checks: [.contains("pricing"), .contains("fifty"), .contains("Tuesday")]
            ),
            BenchmarkScenario(
                id: "S08",
                title: "Source Continues After Trigger",
                transcriptTemplate: "Draft a release note {{ASSISTANT}} make it upbeat and mention dark mode support faster sync and a fix for duplicate notifications",
                intent: "Continuous dictation after the assistant trigger; the split path treats key facts as instructions instead of source.",
                checks: [.contains("dark mode"), .contains("sync"), .contains("duplicate notifications")]
            ),
            BenchmarkScenario(
                id: "S09",
                title: "Trigger In The Middle Of Narrative",
                transcriptTemplate: "For the account summary {{ASSISTANT}} turn this into an executive update revenue is up twelve percent churn is flat and the enterprise pilot closes in May",
                intent: "Tests whether the combined path can reason over the whole message when source and instruction are interleaved.",
                checks: [.contains("twelve percent"), .contains("May"), .contains("enterprise")]
            ),
            BenchmarkScenario(
                id: "S10",
                title: "Checklist After Trigger",
                transcriptTemplate: "We need to prep the launch {{ASSISTANT}} turn this into a checklist and include confirm legal signoff schedule the email and freeze the landing page copy",
                intent: "Instruction-first continuation after the trigger with all substantive items coming later.",
                checks: [.lineCountAtLeast(3), .contains("legal"), .contains("email"), .contains("landing page")]
            ),
            BenchmarkScenario(
                id: "S11",
                title: "Quoted Content After Trigger",
                transcriptTemplate: "{{ASSISTANT}} summarize this transcript in two sentences customer said the migration took six hours longer than expected but support was excellent",
                intent: "Start-triggered summarization where the entire transcript follows the name.",
                checks: [.contains("six hours"), .contains("support")]
            ),
            BenchmarkScenario(
                id: "S12",
                title: "Table Request",
                transcriptTemplate: "Compare plan options {{ASSISTANT}} make a compact table for Starter ten dollars Pro thirty dollars and Enterprise custom pricing",
                intent: "Output-shape task with nearly all content after the trigger.",
                checks: [.contains("Starter"), .contains("Pro"), .contains("Enterprise")]
            ),
            BenchmarkScenario(
                id: "S13",
                title: "Task Extraction With Owners",
                transcriptTemplate: "Meeting recap {{ASSISTANT}} extract action items Sam owns QA checklist Maria sends revised contract and Jon updates onboarding docs by Thursday",
                intent: "Entity extraction from a continuous utterance after the trigger.",
                checks: [.contains("Sam"), .contains("Maria"), .contains("Jon"), .contains("Thursday")]
            ),
            BenchmarkScenario(
                id: "S14",
                title: "Late Trigger With More Dictation",
                transcriptTemplate: "Need a customer apology note for the outage {{ASSISTANT}} make it empathetic and mention that service was restored at 9 40 AM and that no data was lost",
                intent: "Late trigger with factual details arriving only after the trigger.",
                checks: [.contains("9 40"), .contains("no data was lost")]
            ),
            BenchmarkScenario(
                id: "S15",
                title: "Natural Voice Command",
                transcriptTemplate: "Could you {{ASSISTANT}} clean this up for the investor update we signed three new logos expanded gross margin by four points and hired a VP of sales",
                intent: "Natural voice phrasing where instruction and source are fully meshed.",
                checks: [.contains("three"), .contains("gross margin"), .contains("VP of sales")]
            )
        ]
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let humanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

private struct BenchmarkPrompt {
    let systemPrompt: String
    let userPrompt: String
    let contentForReport: String?
    let instructionsForReport: String?
}

private final class LocalChatEngine {
    private let tier: ModelTier
    private var container: ModelContainer?

    init(tier: ModelTier) throws {
        self.tier = tier
    }

    func load() async throws {
        guard container == nil else { return }
        let directory = try Self.localModelDirectory(for: tier)
        var configuration = ModelConfiguration(directory: directory)
        configuration.eosTokenIds = [248044]
        configuration.extraEOSTokens = ["<|im_end|>"]
        let hub = try Self.makePersistentHub()
        container = try await LLMModelFactory.shared.loadContainer(hub: hub, configuration: configuration)
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        guard let container else {
            throw BenchmarkError.generationFailed("Model container not loaded")
        }

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: GenerateParameters(maxTokens: tier.maxTokens, temperature: 0, topP: 1),
            additionalContext: ["enable_thinking": false],
            tools: []
        )

        var output = ""
        var stripper = ThinkStripper()
        var completion: GenerateStopReason?

        for try await generation in session.streamDetails(
            to: userPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            images: [],
            videos: []
        ) {
            switch generation {
            case .chunk(let text):
                output += stripper.process(text)
            case .info(let info):
                output += stripper.flush()
                completion = info.stopReason
            case .toolCall:
                break
            }
        }

        output += stripper.flush()

        switch completion {
        case .some(.stop):
            break
        case .some(.length):
            throw BenchmarkError.generationFailed("Output truncated for \(tier.label)")
        case .some(.cancelled):
            throw BenchmarkError.generationFailed("Generation cancelled for \(tier.label)")
        case .none:
            throw BenchmarkError.generationFailed("No completion signal for \(tier.label)")
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BenchmarkError.generationFailed("Empty output for \(tier.label)")
        }
        return trimmed
    }

    private static func localModelDirectory(for tier: ModelTier) throws -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Speech2Text/RewriteModel/models/mlx-community", isDirectory: true)
        let directory = base.appendingPathComponent(tier.directoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw BenchmarkError.localModelNotFound(directory.path)
        }
        return directory
    }

    private static func makePersistentHub() throws -> HubApi {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let downloadBase = appSupport
            .appendingPathComponent("Speech2Text", isDirectory: true)
            .appendingPathComponent("RewriteModel", isDirectory: true)
        try fileManager.createDirectory(at: downloadBase, withIntermediateDirectories: true)
        return HubApi(downloadBase: downloadBase)
    }
}

private struct ThinkStripper {
    private var inThink = false
    private var buffer = ""

    mutating func process(_ text: String) -> String {
        buffer += text
        var output = ""

        while !buffer.isEmpty {
            if inThink {
                if let range = buffer.range(of: "</think>") {
                    buffer = String(buffer[range.upperBound...])
                    inThink = false
                } else {
                    let partial = suffixPartialMatch(buffer, target: "</think>")
                    buffer = String(buffer.suffix(partial))
                    break
                }
            } else {
                if let range = buffer.range(of: "<think>") {
                    output += String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])
                    inThink = true
                } else {
                    let partial = suffixPartialMatch(buffer, target: "<think>")
                    let safeIndex = buffer.index(buffer.endIndex, offsetBy: -partial)
                    output += String(buffer[..<safeIndex])
                    buffer = String(buffer[safeIndex...])
                    break
                }
            }
        }

        return output
    }

    mutating func flush() -> String {
        let remaining = inThink ? "" : buffer
        buffer = ""
        return remaining
    }

    private func suffixPartialMatch(_ text: String, target: String) -> Int {
        let textUTF8 = Array(text.utf8)
        let targetUTF8 = Array(target.utf8)
        let maxLen = min(textUTF8.count, targetUTF8.count - 1)
        guard maxLen > 0 else { return 0 }

        for len in (1...maxLen).reversed() {
            let suffix = textUTF8[(textUTF8.count - len)...]
            let prefix = targetUTF8[0..<len]
            if suffix[...] == prefix[...] {
                return len
            }
        }

        return 0
    }
}
