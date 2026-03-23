import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon

enum LLMRewriteError: LocalizedError, Equatable {
    case modelLoadFailed
    case modelTooLargeForDevice
    case generationFailed
    case cancelled
    case outputTruncated
    case emptyOutput

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
        }
    }
}

protocol LLMRewriting: Sendable {
    func setTier(_ newTier: RewriteModelTier) async
    func prewarm() async throws
    func rewrite(body: String, instructions: String) async throws -> String
    func loadedTier() async -> RewriteModelTier?
    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async
    func cancelScheduledUnload() async
    func unload() async
    func deleteDownloadedModel(for tier: RewriteModelTier) async throws
}

extension LLMRewriting {
    func setTier(_ newTier: RewriteModelTier) async {}
    func prewarm() async throws {}
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
            _ parameters: GenerateParameters
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

    private var generationParameters: GenerateParameters {
        GenerateParameters(maxTokens: tier.recommendedMaxTokens, temperature: 0, topP: 1.0)
    }

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
            return try await downloadModel(
                hub: hub,
                configuration: tier.modelConfiguration,
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
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        loadTask?.cancel()
        loadTask = nil
        cachedModel = nil
        loadProgressObservers.removeAll()
        Memory.clearCache()
    }

    func prewarm() async throws {
        _ = try await resolveModel()
    }

    func rewrite(body: String, instructions: String) async throws -> String {
        try await rewriteCore(body: body, instructions: instructions)
    }

    func loadedTier() async -> RewriteModelTier? {
        cachedModel == nil ? nil : tier
    }

    private func rewriteCore(body: String, instructions: String) async throws -> String {
        if Task.isCancelled {
            throw LLMRewriteError.cancelled
        }

        let model: RewriteModel
        do {
            model = try await resolveModel()
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
                instructions,
                generationParameters
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

            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func resolveModel() async throws -> RewriteModel {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil

        // Set conservative MLX GPU cache limit to leave room for WhisperKit
        // 3GB cache limit helps prevent OOM crashes when both are loaded
        MLX.GPU.set(cacheLimit: 3 * 1024 * 1024 * 1024)

        if let cachedModel {
            return cachedModel
        }

        if let loadTask {
            return try await loadTask.value
        }

        let loader = currentLoader()
        let tier = self.tier
        let loadProgressHandler = currentLoadProgressHandler()
        let task = Task { [loader, hubFactory, hasCustomLoader, hasCustomFileDownloader, tier, loadProgressHandler, self] in
            if hasCustomLoader && !hasCustomFileDownloader {
                let hub = try hubFactory()
                return try await loader(hub)
            }

            let directory = try await self.downloadFiles(
                for: tier,
                progressHandler: loadProgressHandler
            )

            if hasCustomLoader {
                let hub = try hubFactory()
                return try await loader(hub)
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

        _ = try await resolveModel()
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
        parameters: GenerateParameters
    ) throws -> AsyncThrowingStream<RewriteEvent, Error> {
        guard let container = model.container else {
            throw LLMRewriteError.generationFailed
        }

        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: parameters,
            additionalContext: ["enable_thinking": false],
            tools: []
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var stripper = ThinkStripper()
                    for try await generation in session.streamDetails(to: body, images: [], videos: []) {
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
                    NSLog("Speech2Text: assistant rewrite stream failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func downloadModelFiles(
        for tier: RewriteModelTier,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws -> URL {
        try await shared.downloadFiles(for: tier, progressHandler: progressHandler)
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
        let hasRequiredMetadata = requiredTopLevelArtifacts.isSubset(of: fileNames)
        let hasWeights = contents.contains { url in
            url.pathExtension == "safetensors" || url.lastPathComponent == "model.safetensors.index.json"
        }

        return hasRequiredMetadata && hasWeights
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
            .appendingPathComponent("Speech2Text", isDirectory: true)
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

    private func completedProgress() -> Progress {
        let done = Progress(totalUnitCount: 1)
        done.completedUnitCount = 1
        return done
    }

    private static let requiredTopLevelArtifacts: Set<String> = [
        "config.json",
        "tokenizer.json"
    ]
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
