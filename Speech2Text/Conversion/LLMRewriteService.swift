import Foundation
import Hub
import MLXLLM
import MLXLMCommon

enum LLMRewriteError: LocalizedError, Equatable {
    case modelLoadFailed
    case generationFailed
    case cancelled
    case outputTruncated
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load rewrite model."
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
    func rewrite(body: String, mode: ConvertMode) async throws -> String
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
    typealias StreamFactory =
        @Sendable (
            _ model: RewriteModel,
            _ body: String,
            _ instructions: String,
            _ parameters: GenerateParameters
        ) throws -> AsyncThrowingStream<RewriteEvent, Error>

    static let shared = LLMRewriteService()

    private static let defaultGenerationParameters = GenerateParameters(
        maxTokens: 1_024,
        temperature: 0,
        topP: 1.0
    )

    private let loader: Loader
    private let streamFactory: StreamFactory
    private let generationParameters: GenerateParameters
    private let hubFactory: @Sendable () throws -> HubApi
    private let rewriteExecutionGate = RewriteExecutionGate()

    private var cachedModel: RewriteModel?
    private var loadTask: Task<RewriteModel, Error>?

    init(
        loader: @escaping Loader = LLMRewriteService.defaultLoader,
        streamFactory: @escaping StreamFactory = LLMRewriteService.defaultStreamFactory,
        generationParameters: GenerateParameters = LLMRewriteService.defaultGenerationParameters,
        hubFactory: @escaping @Sendable () throws -> HubApi = LLMRewriteService.makePersistentHub
    ) {
        self.loader = loader
        self.streamFactory = streamFactory
        self.generationParameters = generationParameters
        self.hubFactory = hubFactory
    }

    func rewrite(body: String, mode: ConvertMode) async throws -> String {
        if Task.isCancelled {
            throw LLMRewriteError.cancelled
        }

        let model: RewriteModel
        do {
            model = try await resolveModel()
        } catch is CancellationError {
            throw LLMRewriteError.cancelled
        } catch {
            throw LLMRewriteError.modelLoadFailed
        }

        await rewriteExecutionGate.acquire()

        do {
            let stream = try streamFactory(
                model,
                body,
                mode.defaultSystemPrompt,
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
        if let cachedModel {
            return cachedModel
        }

        if let loadTask {
            return try await loadTask.value
        }

        let task = Task { [loader, hubFactory] in
            let hub = try hubFactory()
            return try await loader(hub)
        }
        loadTask = task

        do {
            let model = try await task.value
            cachedModel = model
            loadTask = nil
            return model
        } catch {
            loadTask = nil
            throw error
        }
    }

    private static func defaultLoader(hub: HubApi) async throws -> RewriteModel {
        let container = try await LLMModelFactory.shared.loadContainer(
            hub: hub,
            configuration: LLMRegistry.qwen2_5_1_5b
        )
        return RewriteModel(container: container)
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
            tools: []
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await generation in session.streamDetails(to: body, images: [], videos: []) {
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(.chunk(text))
                        case .info(let info):
                            continuation.yield(.completion(info.stopReason))
                        case .toolCall:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
