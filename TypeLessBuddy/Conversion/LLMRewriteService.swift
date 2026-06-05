import CoreImage
import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

enum LLMRewriteError: LocalizedError, Equatable {
    case modelLoadFailed
    case modelTooLargeForDevice
    case generationFailed
    case cancelled
    case outputTruncated
    case emptyOutput
    case networkError(String)
    case authenticationFailed
    case rateLimited
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load rewrite model."
        case .modelTooLargeForDevice:
            return "This model is too large for your device — reverting to default."
        case .generationFailed:
            return "Rewrite generation failed."
        case .cancelled:
            return "Rewrite was cancelled."
        case .outputTruncated:
            return "Rewrite output hit the token limit."
        case .emptyOutput:
            return "Rewrite model returned empty output."
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .authenticationFailed:
            return "Invalid API key — check your cloud LLM settings."
        case .rateLimited:
            return "Rate limited by the API provider — try again shortly."
        case .providerError(let detail):
            return "Cloud LLM error: \(detail)"
        }
    }
}

protocol LLMRewriting: Sendable {
    func setTier(_ newTier: RewriteModelTier) async
    func prewarm() async throws
    func rewrite(body: String, instructions: String, promptPrefix: String) async throws -> String
    func rewrite(body: String, instructions: String) async throws -> String
    /// Raw generation with a caller-supplied system prompt. No rewrite framing is added.
    func generate(prompt: String, systemPrompt: String) async throws -> String
    func generate(
        prompt: String,
        systemPrompt: String,
        images: [UserInput.Image]
    ) async throws -> String
    func loadedTier() async -> RewriteModelTier?
    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async
    func cancelScheduledUnload() async
    func unload() async
    func deleteDownloadedModel(for tier: RewriteModelTier) async throws
}

extension LLMRewriting {
    func setTier(_ newTier: RewriteModelTier) async {}
    func prewarm() async throws {}
    func rewrite(body: String, instructions: String) async throws -> String {
        try await rewrite(
            body: body,
            instructions: instructions,
            promptPrefix: LLMRewriteService.defaultRewritePromptPrefix
        )
    }
    func generate(prompt: String, systemPrompt: String) async throws -> String {
        try await generate(prompt: prompt, systemPrompt: systemPrompt, images: [])
    }
    func generate(
        prompt: String,
        systemPrompt: String,
        images: [UserInput.Image]
    ) async throws -> String {
        try await rewrite(body: prompt, instructions: systemPrompt)
    }
    func loadedTier() async -> RewriteModelTier? { nil }
    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async {}
    func cancelScheduledUnload() async {}
    func unload() async {}
    func deleteDownloadedModel(for tier: RewriteModelTier) async throws {}
}

private actor RewriteExecutionGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if isLocked {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            return
        }
        isLocked = true
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
            return
        }
        let next = waiters.removeFirst()
        next.resume()
    }
}

actor LLMRewriteService: LLMRewriting {
    static let idleUnloadDelayNanoseconds: UInt64 = 30 * 1_000_000_000
    static let legacyDefaultRewritePromptPrefix = """
    You are a local text rewriting assistant.
    Follow the rewrite instructions exactly.
    Return only the final rewritten text.
    Output only the final answer text.
    Do not explain your changes.
    Do not surround the answer in quotation marks unless the user explicitly asks for quotes.
    Do not include labels, quotes, code fences, or <think> tags.
    """
    static let defaultRewritePromptPrefix = legacyDefaultRewritePromptPrefix
    static let assistantNamePlaceholder = "{{assistant_name}}"
    static let defaultAssistantSystemPromptTemplate = """
    You are \(assistantNamePlaceholder), a voice-activated text production assistant. Your name is the trigger to act.
    Questions like "can you write X" or "could you make X" are commands — produce X directly.
    Treat dictated speech as the user's request. Additional context, when present, is source material the request may reference — use it as needed to fulfil the request.
    When the prompt includes one or more trailing labeled sections followed by quoted content, treat each quoted section as source material the request may reference or transform.
    References such as "context provided below" point to source text already included in the prompt, not to an action you need to perform.
    When source text is included below the request, apply rewrite or formatting requests directly to that source text instead of describing the change.
    If source text is already provided, never ask the user to paste or provide it again.
    When the user asks to make provided text nicer, kinder, less harsh, or more polite, rewrite the provided source text itself to satisfy that request.
    For tone-softening requests, remove insults, profanity, ridicule, and shaming language from the final output while preserving the underlying criticism and urgency.
    Do not merely correct punctuation, capitalization, or formatting when the request asks for a tone change.
    When the user asks for bullets, a list, action items, a Slack update, or one sentence, return the requested format directly.
    When source text is provided, transform that text itself instead of restating the request.
    Output only the final artifact. No greetings, affirmations, reasoning, or explanation.
    Preserve all proper nouns, names, numbers, dates, and specific facts from the utterance.
    Do not use quotation marks, labels, code fences, or <think> tags unless explicitly asked.
    """

    struct RewriteModel: Sendable {
        let token: UUID
        let container: ModelContainer?

        init(container: ModelContainer) {
            self.token = UUID()
            self.container = container
        }

        init(testToken: UUID = UUID()) {
            self.token = testToken
            self.container = nil
        }
    }

    enum RewriteEvent: Sendable {
        case chunk(String)
        case completion(GenerateStopReason)
    }

    typealias Loader = @Sendable (HubApi) async throws -> RewriteModel
    typealias FileDownloader =
        @Sendable (
            _ tier: RewriteModelTier,
            _ progressHandler: @Sendable @escaping (Progress) -> Void
        ) async throws -> URL
    typealias StreamFactory =
        @Sendable (
            _ model: RewriteModel,
            _ body: String,
            _ instructions: String,
            _ parameters: GenerateParameters,
            _ images: [UserInput.Image]
        ) throws -> AsyncThrowingStream<RewriteEvent, Error>

    static let shared = LLMRewriteService()

    private let streamFactory: StreamFactory
    private let hubFactory: @Sendable () throws -> HubApi
    private let fileDownloader: FileDownloader
    private let rewriteExecutionGate = RewriteExecutionGate()

    private var tier: RewriteModelTier = .standard2B
    private var tierLoader: Loader = LLMRewriteService.makeDefaultLoader(tier: .standard2B)
    private let hasCustomLoader: Bool
    private let hasCustomFileDownloader: Bool
    private var cachedModel: RewriteModel?
    private var loadTask: Task<RewriteModel, Error>?
    private var fileDownloadTasks: [RewriteModelTier: Task<URL, Error>] = [:]
    private var fileDownloadProgressObservers: [RewriteModelTier: [UUID: @Sendable (Progress) -> Void]] = [:]
    private var loadProgressObservers: [UUID: @Sendable (Progress) -> Void] = [:]
    private var idleUnloadTask: Task<Void, Never>?

    init(
        tier: RewriteModelTier = .standard2B,
        loader: Loader? = nil,
        fileDownloader: FileDownloader? = nil,
        streamFactory: @escaping StreamFactory = LLMRewriteService.defaultStreamFactory,
        hubFactory: @escaping @Sendable () throws -> HubApi = LLMRewriteService.makePersistentHub
    ) {
        self.tier = tier
        self.hasCustomLoader = loader != nil
        self.hasCustomFileDownloader = fileDownloader != nil
        self.tierLoader = loader ?? LLMRewriteService.makeDefaultLoader(tier: tier)
        self.fileDownloader = fileDownloader ?? { tier, progressHandler in
            let hub = try hubFactory()
            return try await LLMRewriteService.downloadModelFiles(
                hub: hub,
                tier: tier,
                progressHandler: progressHandler
            )
        }
        self.streamFactory = streamFactory
        self.hubFactory = hubFactory
    }

    func setTier(_ newTier: RewriteModelTier) async {
        guard newTier != tier else { return }
        tier = newTier
        if !hasCustomLoader {
            tierLoader = LLMRewriteService.makeDefaultLoader(tier: newTier)
        }
        resetLoadedModelState()
    }

    private func resetLoadedModelState() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        loadTask?.cancel()
        loadTask = nil
        cachedModel = nil
        loadProgressObservers.removeAll()
        Memory.clearCache()
    }

    func prewarm() async throws {
        _ = try await resolveLoadedModel()
    }

    func rewrite(body: String, instructions: String) async throws -> String {
        try await rewrite(
            body: body,
            instructions: instructions,
            promptPrefix: Self.defaultRewritePromptPrefix
        )
    }

    func rewrite(body: String, instructions: String, promptPrefix: String) async throws -> String {
        try await rewriteCore(body: body, instructions: instructions, promptPrefix: promptPrefix)
    }

    func generate(prompt: String, systemPrompt: String) async throws -> String {
        try await generate(prompt: prompt, systemPrompt: systemPrompt, images: [])
    }

    func generate(
        prompt: String,
        systemPrompt: String,
        images: [UserInput.Image]
    ) async throws -> String {
        try await generateCore(prompt: prompt, systemPrompt: systemPrompt, images: images)
    }

    func loadedTier() async -> RewriteModelTier? {
        cachedModel == nil ? nil : tier
    }

    private func rewriteCore(body: String, instructions: String, promptPrefix: String) async throws -> String {
        try await rewriteCore(body: body, instructions: instructions, promptPrefix: promptPrefix, images: [])
    }

    private func rewriteCore(
        body: String,
        instructions: String,
        promptPrefix: String,
        images: [UserInput.Image]
    ) async throws -> String {
        if Task.isCancelled {
            throw LLMRewriteError.cancelled
        }

        let model: RewriteModel
        do {
            model = try await resolveLoadedModel()
        } catch is CancellationError {
            throw LLMRewriteError.cancelled
        } catch let rewriteError as LLMRewriteError {
            throw rewriteError
        } catch {
            throw LLMRewriteError.modelLoadFailed
        }

        await rewriteExecutionGate.acquire()

        do {
            let stream = try streamFactory(
                model,
                body,
                Self.makeRewriteInstructions(promptPrefix: promptPrefix, instructions: instructions),
                generationParameters(for: tier),
                images
            )

            var output = ""
            var completion: GenerateStopReason?

            for try await event in stream {
                switch event {
                case .chunk(let chunk):
                    output += chunk
                case .completion(let reason):
                    completion = reason
                }
            }

            if Task.isCancelled {
                throw LLMRewriteError.cancelled
            }

            guard let completion else {
                throw LLMRewriteError.generationFailed
            }

            switch completion {
            case .cancelled:
                throw LLMRewriteError.cancelled
            case .length:
                throw LLMRewriteError.outputTruncated
            case .stop:
                break
            }

            let trimmed = Self.sanitizeGeneratedOutput(output)
            guard !trimmed.isEmpty else {
                throw LLMRewriteError.emptyOutput
            }
            await rewriteExecutionGate.release()
            return trimmed
        } catch let error as LLMRewriteError {
            await rewriteExecutionGate.release()
            throw error
        } catch is CancellationError {
            await rewriteExecutionGate.release()
            throw LLMRewriteError.cancelled
        } catch {
            await rewriteExecutionGate.release()
            throw LLMRewriteError.generationFailed
        }
    }

    private func generateCore(
        prompt: String,
        systemPrompt: String,
        images: [UserInput.Image]
    ) async throws -> String {
        if Task.isCancelled {
            throw LLMRewriteError.cancelled
        }

        let model: RewriteModel
        do {
            model = try await resolveLoadedModel()
        } catch is CancellationError {
            throw LLMRewriteError.cancelled
        } catch let rewriteError as LLMRewriteError {
            throw rewriteError
        } catch {
            throw LLMRewriteError.modelLoadFailed
        }

        await rewriteExecutionGate.acquire()

        do {
            let stream = try streamFactory(
                model,
                prompt,
                systemPrompt,
                generationParameters(for: tier),
                images
            )

            var output = ""
            var completion: GenerateStopReason?

            for try await event in stream {
                switch event {
                case .chunk(let chunk):
                    output += chunk
                case .completion(let reason):
                    completion = reason
                }
            }

            if Task.isCancelled {
                throw LLMRewriteError.cancelled
            }

            guard let completion else {
                throw LLMRewriteError.generationFailed
            }

            switch completion {
            case .cancelled:
                throw LLMRewriteError.cancelled
            case .length:
                throw LLMRewriteError.outputTruncated
            case .stop:
                break
            }

            let trimmed = Self.sanitizeGeneratedOutput(output)
            guard !trimmed.isEmpty else {
                throw LLMRewriteError.emptyOutput
            }
            await rewriteExecutionGate.release()
            return trimmed
        } catch let error as LLMRewriteError {
            await rewriteExecutionGate.release()
            throw error
        } catch is CancellationError {
            await rewriteExecutionGate.release()
            throw LLMRewriteError.cancelled
        } catch {
            await rewriteExecutionGate.release()
            throw LLMRewriteError.generationFailed
        }
    }

    private func resolveLoadedModel() async throws -> RewriteModel {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil

        if let cachedModel {
            return cachedModel
        }

        if let loadTask {
            return try await loadTask.value
        }

        return try await resolveBuiltInModel(for: tier)
    }

    private func resolveBuiltInModel(
        for tier: RewriteModelTier
    ) async throws -> RewriteModel {
        let loader = currentLoader()
        let loadProgressHandler = currentLoadProgressHandler()
        let task = Task { [loader, hubFactory, hasCustomLoader, hasCustomFileDownloader, tier, loadProgressHandler, self] in
            if hasCustomLoader && !hasCustomFileDownloader {
                let hub = try hubFactory()
                return try await loader(hub)
            }

            if hasCustomLoader {
                let _ = try await self.downloadFiles(
                    for: tier,
                    progressHandler: loadProgressHandler
                )
                let hub = try hubFactory()
                return try await loader(hub)
            }

            // Prefer local artifacts when already complete to avoid remote
            // snapshot checks on every cold load.
            let directory: URL
            if !hasCustomFileDownloader,
               Self.isModelDownloaded(tier, fileManager: .default),
               let localDirectory = try? Self.downloadedModelDirectory(for: tier, fileManager: .default) {
                directory = localDirectory
            } else {
                directory = try await self.downloadFiles(
                    for: tier,
                    progressHandler: loadProgressHandler
                )
            }

            let hub = try hubFactory()
            let container = try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: Self.localModelConfiguration(for: tier, directory: directory)
            )
            return RewriteModel(container: container)
        }
        loadTask = task

        do {
            let model = try await task.value
            cachedModel = model
            try? Self.markModelPrepared(tier, fileManager: .default)
            loadTask = nil
            loadProgressObservers.removeAll()
            return model
        } catch {
            loadTask = nil
            loadProgressObservers.removeAll()
            if isMemoryPressureError(error) {
                throw LLMRewriteError.modelTooLargeForDevice
            }
            throw error
        }
    }

    private func generationParameters(for tier: RewriteModelTier) -> GenerateParameters {
        GenerateParameters(maxTokens: tier.recommendedMaxTokens, temperature: 0, topP: 1.0)
    }

    private func isMemoryPressureError(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("out of memory") || description.contains("memory") && description.contains("alloc")
    }

    func download(progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }) async throws {
        if cachedModel != nil {
            let done = Progress(totalUnitCount: 1)
            done.completedUnitCount = 1
            progressHandler(done)
            return
        }
        let observerID = UUID()
        loadProgressObservers[observerID] = progressHandler
        defer {
            loadProgressObservers.removeValue(forKey: observerID)
        }

        _ = try await resolveLoadedModel()
        let done = Progress(totalUnitCount: 1)
        done.completedUnitCount = 1
        progressHandler(done)
    }

    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: duration)
            } catch {
                return
            }

            guard let self else { return }
            await self.unload()
        }
    }

    func cancelScheduledUnload() async {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    func unload() async {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        loadTask?.cancel()
        loadTask = nil
        cachedModel = nil
        loadProgressObservers.removeAll()
        Memory.clearCache()
    }

    func deleteDownloadedModel(for tier: RewriteModelTier) async throws {
        if self.tier == tier {
            await unload()
        }
        fileDownloadTasks[tier]?.cancel()
        fileDownloadTasks[tier] = nil
        fileDownloadProgressObservers[tier] = nil
        try Self.deleteDownloadedModelFiles(for: tier)
    }

    func downloadFiles(
        for tier: RewriteModelTier,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws -> URL {
        let observerID = UUID()
        fileDownloadProgressObservers[tier, default: [:]][observerID] = progressHandler
        defer {
            fileDownloadProgressObservers[tier]?.removeValue(forKey: observerID)
            if fileDownloadProgressObservers[tier]?.isEmpty == true {
                fileDownloadProgressObservers.removeValue(forKey: tier)
            }
        }

        if let existingTask = fileDownloadTasks[tier] {
            let directory = try await existingTask.value
            progressHandler(completedProgress())
            return directory
        }

        try Self.deleteIncompleteDownloadedModelFilesIfNeeded(for: tier)

        let fileDownloader = self.fileDownloader
        let task = Task { [self, fileDownloader, tier] in
            try await fileDownloader(tier) { progress in
                Task {
                    await self.broadcastFileDownloadProgress(progress, for: tier)
                }
            }
        }
        fileDownloadTasks[tier] = task

        do {
            let directory = try await task.value
            fileDownloadTasks[tier] = nil
            progressHandler(completedProgress())
            return directory
        } catch {
            fileDownloadTasks[tier] = nil
            throw error
        }
    }

    private func currentLoadProgressHandler() -> @Sendable (Progress) -> Void {
        guard !loadProgressObservers.isEmpty else {
            return { _ in }
        }

        return { [self] progress in
            Task {
                await self.broadcastLoadProgress(progress)
            }
        }
    }

    private func currentLoader() -> Loader {
        guard !hasCustomLoader, !loadProgressObservers.isEmpty else {
            return tierLoader
        }

        return LLMRewriteService.makeDefaultLoader(tier: tier) { [self] progress in
            Task {
                await broadcastLoadProgress(progress)
            }
        }
    }

    private func broadcastLoadProgress(_ progress: Progress) {
        for observer in loadProgressObservers.values {
            observer(progress)
        }
    }

    private func broadcastFileDownloadProgress(_ progress: Progress, for tier: RewriteModelTier) {
        guard let observers = fileDownloadProgressObservers[tier]?.values else { return }
        for observer in observers {
            observer(progress)
        }
    }

    static func makeDefaultLoader(
        tier: RewriteModelTier,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) -> Loader {
        { hub in
            let container = try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: tier.modelConfiguration,
                progressHandler: progressHandler
            )
            return RewriteModel(container: container)
        }
    }

    private static func defaultStreamFactory(
        model: RewriteModel,
        body: String,
        instructions: String,
        parameters: GenerateParameters,
        images: [UserInput.Image]
    ) throws -> AsyncThrowingStream<RewriteEvent, Error> {
        guard let container = model.container else {
            throw LLMRewriteError.generationFailed
        }

        let rewriteBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: parameters,
            // The 4B Qwen 3.5 template defaults to thinking mode when the flag is omitted,
            // which causes rewrite generation to terminate early on this path.
            additionalContext: ["enable_thinking": false],
            tools: []
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var stripper = ThinkStripper()
                    for try await generation in session.streamDetails(
                        to: rewriteBody,
                        images: images,
                        videos: []
                    ) {
                        switch generation {
                        case .chunk(let text):
                            let visible = stripper.process(text)
                            if !visible.isEmpty {
                                continuation.yield(.chunk(visible))
                            }
                        case .info(let info):
                            let remaining = stripper.flush()
                            if !remaining.isEmpty {
                                continuation.yield(.chunk(remaining))
                            }
                            continuation.yield(.completion(info.stopReason))
                        case .toolCall:
                            break
                        }
                    }
                    let remaining = stripper.flush()
                    if !remaining.isEmpty {
                        continuation.yield(.chunk(remaining))
                    }
                    continuation.finish()
                } catch {
                    NSLog("TypeLessBuddy: assistant rewrite stream failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func rawStreamFactory(
        model: RewriteModel,
        prompt: String,
        systemPrompt: String,
        parameters: GenerateParameters,
        images: [UserInput.Image] = []
    ) throws -> AsyncThrowingStream<RewriteEvent, Error> {
        guard let container = model.container else {
            throw LLMRewriteError.generationFailed
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: parameters,
            additionalContext: ["enable_thinking": false],
            tools: []
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var stripper = ThinkStripper()
                    for try await generation in session.streamDetails(
                        to: trimmedPrompt,
                        images: images,
                        videos: []
                    ) {
                        switch generation {
                        case .chunk(let text):
                            let visible = stripper.process(text)
                            if !visible.isEmpty {
                                continuation.yield(.chunk(visible))
                            }
                        case .info(let info):
                            let remaining = stripper.flush()
                            if !remaining.isEmpty {
                                continuation.yield(.chunk(remaining))
                            }
                            continuation.yield(.completion(info.stopReason))
                        case .toolCall:
                            break
                        }
                    }
                    let remaining = stripper.flush()
                    if !remaining.isEmpty {
                        continuation.yield(.chunk(remaining))
                    }
                    continuation.finish()
                } catch {
                    NSLog("TypeLessBuddy: raw generation stream failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func normalizeRewritePromptPrefix(_ promptPrefix: String) -> String {
        let trimmedPromptPrefix = promptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPromptPrefix.isEmpty {
            return defaultRewritePromptPrefix
        }
        return trimmedPromptPrefix
    }

    static func normalizeAssistantSystemPromptTemplate(_ promptTemplate: String) -> String {
        let trimmedTemplate = promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTemplate.isEmpty {
            return defaultAssistantSystemPromptTemplate
        }
        return trimmedTemplate
    }

    static func sanitizeGeneratedOutput(_ output: String) -> String {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            return trimmedOutput
        }

        let unwrappedCodeFence = unwrapEntireCodeFenceIfNeeded(trimmedOutput)
        let unlabeled = stripLeadingArtifactLabelIfNeeded(unwrappedCodeFence)
        let extractedArtifact = extractTrailingArtifactIfNeeded(unlabeled) ?? unlabeled

        return extractedArtifact.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolveAssistantSystemPrompt(
        promptTemplate: String = defaultAssistantSystemPromptTemplate,
        assistantName: String
    ) -> String {
        let resolvedAssistantName = assistantName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveAssistantName = resolvedAssistantName.isEmpty ? "Assistant" : resolvedAssistantName
        let effectiveTemplate = normalizeAssistantSystemPromptTemplate(promptTemplate)
        return effectiveTemplate.replacingOccurrences(
            of: assistantNamePlaceholder,
            with: effectiveAssistantName
        )
    }

    static func makeRewriteInstructions(
        promptPrefix: String = defaultRewritePromptPrefix,
        instructions: String
    ) -> String {
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInstructions: String
        if trimmedInstructions.isEmpty {
            effectiveInstructions = "Return the source text exactly as written."
        } else {
            effectiveInstructions = trimmedInstructions
        }
        let effectivePromptPrefix = normalizeRewritePromptPrefix(promptPrefix)

        return """
        \(effectivePromptPrefix)

        Rewrite instructions:
        \(effectiveInstructions)
        """
    }

    static func makeRewritePrompt(
        body: String,
        instructions: String,
        promptPrefix: String = defaultRewritePromptPrefix
    ) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let rewriteInstructions = makeRewriteInstructions(
            promptPrefix: promptPrefix,
            instructions: instructions
        )

        return """
        \(rewriteInstructions)

        Source text:
        \(trimmedBody)
        """
    }

    private static func unwrapEntireCodeFenceIfNeeded(_ output: String) -> String {
        guard output.hasPrefix("```"), output.hasSuffix("```") else {
            return output
        }

        let pattern = #"(?s)^```[^\n`]*\n?(.*?)\n?```$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return output
        }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard
            let match = regex.firstMatch(in: output, options: [], range: range),
            let bodyRange = Range(match.range(at: 1), in: output)
        else {
            return output
        }

        return String(output[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingArtifactLabelIfNeeded(_ output: String) -> String {
        let pattern = #"(?is)^\s*(?:draft(?: message)?|message|reply|email|slack message|text message)\s*:\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return output
        }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard
            let match = regex.firstMatch(in: output, options: [], range: range),
            let bodyRange = Range(match.range(at: 1), in: output)
        else {
            return output
        }

        return String(output[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractTrailingArtifactIfNeeded(_ output: String) -> String? {
        let paragraphs = output
            .components(separatedBy: .newlines)
            .split(whereSeparator: { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
            .map { lines in
                lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        guard paragraphs.count >= 2 else {
            return nil
        }

        let preamble = paragraphs[0]
        guard looksLikeMetaPreamble(preamble) else {
            return nil
        }

        let artifact = paragraphs.dropFirst().joined(separator: "\n\n")
        return unwrapBalancedQuotesIfNeeded(artifact)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeMetaPreamble(_ preamble: String) -> Bool {
        let pattern = #"(?i)^\s*(?:sure|of course|certainly|absolutely|here(?: is|'s)|below is|you can send|draft(?: message)?|message|reply|email|slack message|text message)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range = NSRange(preamble.startIndex..<preamble.endIndex, in: preamble)
        return regex.firstMatch(in: preamble, options: [], range: range) != nil
    }

    private static func unwrapBalancedQuotesIfNeeded(_ output: String) -> String {
        let quotePairs: [(Character, Character)] = [
            ("\"", "\""),
            ("“", "”")
        ]

        for (opening, closing) in quotePairs {
            guard output.first == opening, output.last == closing else { continue }
            let inner = output.dropFirst().dropLast()
            return String(inner)
        }

        return output
    }

    static func downloadModelFiles(
        for tier: RewriteModelTier,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws -> URL {
        try await shared.downloadFiles(for: tier, progressHandler: progressHandler)
    }

    private static func downloadModelFiles(
        hub: HubApi,
        tier: RewriteModelTier,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let repo = Hub.Repo(id: tier.hubSlug)
        return try await hub.snapshot(
            from: repo,
            matching: requiredDownloadPatterns(for: tier),
            progressHandler: progressHandler
        )
    }

    static func isModelDownloaded(
        _ tier: RewriteModelTier,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let directory = try? downloadedModelDirectory(for: tier, baseURL: baseURL, fileManager: fileManager),
              fileManager.fileExists(atPath: directory.path) else {
            return false
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let fileNames = Set(contents.map(\.lastPathComponent))
        let hasRequiredMetadata = requiredTopLevelArtifacts(for: tier).isSubset(of: fileNames)
        let hasWeights = contents.contains { url in
            url.pathExtension == "safetensors" || url.lastPathComponent == "model.safetensors.index.json"
        }

        return hasRequiredMetadata && hasWeights
    }

    static func isModelPrepared(
        _ tier: RewriteModelTier,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        guard isModelDownloaded(tier, baseURL: baseURL, fileManager: fileManager),
              let directory = try? downloadedModelDirectory(for: tier, baseURL: baseURL, fileManager: fileManager)
        else {
            return false
        }

        let markerURL = preparedMarkerURL(for: directory)
        return fileManager.fileExists(atPath: markerURL.path)
    }

    private static func makePersistentHub() throws -> HubApi {
        let fileManager = FileManager.default
        let downloadBase = try persistentDownloadBaseURL(fileManager: fileManager)
        try fileManager.createDirectory(at: downloadBase, withIntermediateDirectories: true)
        return HubApi(downloadBase: downloadBase)
    }

    private static func persistentDownloadBaseURL(fileManager: FileManager) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("TypeLessBuddy", isDirectory: true)
            .appendingPathComponent("RewriteModel", isDirectory: true)
    }

    static func downloadedModelDirectory(
        for tier: RewriteModelTier,
        baseURL: URL? = nil,
        fileManager: FileManager
    ) throws -> URL {
        let resolvedBaseURL = try baseURL ?? persistentDownloadBaseURL(fileManager: fileManager)
        return tier.hubSlug
            .split(separator: "/")
            .reduce(resolvedBaseURL.appendingPathComponent("models", isDirectory: true)) { partial, component in
                partial.appendingPathComponent(String(component), isDirectory: true)
            }
    }

    static func deleteDownloadedModelFiles(
        for tier: RewriteModelTier,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let directory = try downloadedModelDirectory(for: tier, baseURL: baseURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    static func deleteIncompleteDownloadedModelFilesIfNeeded(
        for tier: RewriteModelTier,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let directory = try downloadedModelDirectory(for: tier, baseURL: baseURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        guard !isModelDownloaded(tier, baseURL: baseURL, fileManager: fileManager) else { return }
        try fileManager.removeItem(at: directory)
    }

    private static func localModelConfiguration(for tier: RewriteModelTier, directory: URL) -> ModelConfiguration {
        let source = tier.modelConfiguration
        return ModelConfiguration(
            directory: directory,
            tokenizerId: source.tokenizerId,
            overrideTokenizer: source.overrideTokenizer,
            defaultPrompt: source.defaultPrompt,
            extraEOSTokens: source.extraEOSTokens,
            eosTokenIds: source.eosTokenIds,
            toolCallFormat: source.toolCallFormat
        )
    }

    private static func markModelPrepared(_ tier: RewriteModelTier, fileManager: FileManager) throws {
        let directory = try downloadedModelDirectory(for: tier, fileManager: fileManager)
        guard fileManager.fileExists(atPath: directory.path) else { return }

        try markModelPrepared(at: directory, fileManager: fileManager)
    }

    private static func markModelPrepared(at directory: URL, fileManager: FileManager) throws {
        let markerURL = preparedMarkerURL(for: directory)
        if !fileManager.fileExists(atPath: markerURL.path) {
            fileManager.createFile(atPath: markerURL.path, contents: Data(), attributes: nil)
        }
    }

    private static func preparedMarkerURL(for directory: URL) -> URL {
        directory.appendingPathComponent(".typelessbuddy-prepared", isDirectory: false)
    }

    private func completedProgress() -> Progress {
        let done = Progress(totalUnitCount: 1)
        done.completedUnitCount = 1
        return done
    }

    static func requiredDownloadPatterns(for tier: RewriteModelTier) -> [String] {
        switch tier {
        case .standard2B, .standard4B, .high9B:
            return ["*.safetensors", "*.json", "*.jinja"]
        }
    }

    private static func requiredTopLevelArtifacts(for tier: RewriteModelTier) -> Set<String> {
        switch tier {
        case .standard2B, .standard4B, .high9B:
            return [
                "chat_template.jinja",
                "config.json",
                "processor_config.json",
                "tokenizer.json",
                "tokenizer_config.json"
            ]
        }
    }
}

struct ThinkStripper {
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
