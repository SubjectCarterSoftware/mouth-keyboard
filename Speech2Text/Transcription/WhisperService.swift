import Foundation
import WhisperKit

// MARK: - Error Types

enum TranscriptionError: LocalizedError, Equatable {
    case modelLoadFailed
    case noModel
    case inferenceFailed
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load Whisper model."
        case .noModel:
            return "Whisper model is not ready. It may still be downloading."
        case .inferenceFailed:
            return "Whisper inference failed during transcription."
        case .noSpeechDetected:
            return "No speech was detected in the audio samples."
        }
    }
}

// MARK: - Protocol

protocol WhisperTranscribing: Sendable {
    func prepare(model: WhisperModelChoice) async throws
    func transcribe(samples: [Float]) async throws -> String
    func loadedModelChoice() async -> WhisperModelChoice?
    func loadingModelChoice() async -> WhisperModelChoice?
    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async
    func cancelScheduledUnload() async
    func unload() async
    func deleteDownloadedModel(for model: WhisperModelChoice) async throws
}

extension WhisperTranscribing {
    func prepare(model: WhisperModelChoice) async throws {}
    func loadedModelChoice() async -> WhisperModelChoice? { nil }
    func loadingModelChoice() async -> WhisperModelChoice? { nil }
    func scheduleIdleUnload(afterNanoseconds duration: UInt64) async {}
    func cancelScheduledUnload() async {}
    func unload() async {}
    func deleteDownloadedModel(for model: WhisperModelChoice) async throws {}
}

// MARK: - Actor

actor WhisperService: WhisperTranscribing {
    static let idleUnloadDelayNanoseconds: UInt64 = 30 * 1_000_000_000
    static let shared = WhisperService()

    struct PreparedModel: Sendable {
        final class PipelineBox: @unchecked Sendable {
            let whisperKit: WhisperKit

            init(_ whisperKit: WhisperKit) {
                self.whisperKit = whisperKit
            }
        }

        let token: UUID
        let pipeline: PipelineBox?

        init(whisperKit: WhisperKit) {
            token = UUID()
            pipeline = PipelineBox(whisperKit)
        }

        init(testToken: UUID = UUID()) {
            token = testToken
            pipeline = nil
        }
    }

    typealias Loader = @Sendable (_ model: WhisperModelChoice, _ directory: URL) async throws -> PreparedModel
    typealias FileDownloader =
        @Sendable (
            _ model: WhisperModelChoice,
            _ progressHandler: @Sendable @escaping (Progress) -> Void
        ) async throws -> URL
    typealias Transcriber = @Sendable (_ model: PreparedModel, _ samples: [Float]) async throws -> String
    typealias Unloader = @Sendable (_ model: PreparedModel) async -> Void

    private let loader: Loader
    private let fileDownloader: FileDownloader
    private let transcriber: Transcriber
    private let unloader: Unloader
    private let hasCustomLoader: Bool
    private let hasCustomFileDownloader: Bool

    private var cachedModel: PreparedModel?
    private var currentModelChoiceStorage: WhisperModelChoice?
    private var loadingModelChoiceStorage: WhisperModelChoice?
    private var loadTask: Task<PreparedModel, Error>?
    private var fileDownloadTasks: [WhisperModelChoice: Task<URL, Error>] = [:]
    private var fileDownloadProgressObservers: [WhisperModelChoice: [UUID: @Sendable (Progress) -> Void]] = [:]
    private var idleUnloadTask: Task<Void, Never>?

    init(
        loader: Loader? = nil,
        fileDownloader: FileDownloader? = nil,
        transcriber: @escaping Transcriber = WhisperService.defaultTranscriber,
        unloader: @escaping Unloader = WhisperService.defaultUnloader
    ) {
        self.hasCustomLoader = loader != nil
        self.hasCustomFileDownloader = fileDownloader != nil
        self.loader = loader ?? WhisperService.makeDefaultLoader()
        self.fileDownloader = fileDownloader ?? { model, progressHandler in
            try await WhisperService.downloadModelVariant(model, progressHandler: progressHandler)
        }
        self.transcriber = transcriber
        self.unloader = unloader
    }

    func prepare(model: WhisperModelChoice) async throws {
        _ = try await resolveModel(for: model)
    }

    func prepare(model: String = WhisperModelChoice.baseEN.rawValue) async throws {
        guard let choice = WhisperModelChoice.resolvedStoredValue(model) else {
            throw TranscriptionError.modelLoadFailed
        }
        _ = try await resolveModel(for: choice)
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let cachedModel else {
            throw TranscriptionError.noModel
        }

        return try await transcriber(cachedModel, samples)
    }

    func loadedModelChoice() async -> WhisperModelChoice? {
        cachedModel == nil ? nil : currentModelChoiceStorage
    }

    func loadingModelChoice() async -> WhisperModelChoice? {
        loadingModelChoiceStorage
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
        loadingModelChoiceStorage = nil
        await unloadCurrentModel()
    }

    func deleteDownloadedModel(for model: WhisperModelChoice) async throws {
        if currentModelChoiceStorage == model || loadingModelChoiceStorage == model {
            await unload()
        }

        fileDownloadTasks[model]?.cancel()
        fileDownloadTasks[model] = nil
        fileDownloadProgressObservers[model] = nil
        try Self.deleteDownloadedModelFiles(for: model)
    }

    func downloadFiles(
        for model: WhisperModelChoice,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws -> URL {
        let observerID = UUID()
        fileDownloadProgressObservers[model, default: [:]][observerID] = progressHandler
        defer {
            fileDownloadProgressObservers[model]?.removeValue(forKey: observerID)
            if fileDownloadProgressObservers[model]?.isEmpty == true {
                fileDownloadProgressObservers.removeValue(forKey: model)
            }
        }

        if let existingTask = fileDownloadTasks[model] {
            let directory = try await existingTask.value
            progressHandler(completedProgress())
            return directory
        }

        try Self.deleteIncompleteDownloadedModelFilesIfNeeded(for: model)

        let fileDownloader = self.fileDownloader
        let task = Task { [self, fileDownloader, model] in
            try await fileDownloader(model) { progress in
                Task {
                    await self.broadcastFileDownloadProgress(progress, for: model)
                }
            }
        }
        fileDownloadTasks[model] = task

        do {
            let directory = try await task.value
            fileDownloadTasks[model] = nil
            progressHandler(completedProgress())
            return directory
        } catch {
            fileDownloadTasks[model] = nil
            throw error
        }
    }

    private func resolveModel(for model: WhisperModelChoice) async throws -> PreparedModel {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil

        if let cachedModel, currentModelChoiceStorage == model {
            return cachedModel
        }

        if let loadTask, loadingModelChoiceStorage == model {
            return try await loadTask.value
        }

        if loadingModelChoiceStorage != model {
            loadTask?.cancel()
            loadTask = nil
            loadingModelChoiceStorage = nil
        }

        if currentModelChoiceStorage != model {
            await unloadCurrentModel()
        }

        let loader = self.loader
        let task = Task { [hasCustomLoader, hasCustomFileDownloader, loader, model, self] in
            if hasCustomLoader && !hasCustomFileDownloader {
                return try await loader(model, Self.downloadedModelDirectory(for: model))
            }

            // Prefer already-downloaded local artifacts to avoid stalling on
            // remote snapshot checks when the model is already present.
            if !hasCustomLoader && !hasCustomFileDownloader && Self.isModelDownloaded(model) {
                let localDirectory = Self.downloadedModelDirectory(for: model)
                do {
                    return try await loader(model, localDirectory)
                } catch {
                    try? Self.deleteDownloadedModelFiles(for: model)
                }
            }

            let directory = try await self.downloadFiles(for: model)
            return try await loader(model, directory)
        }
        loadTask = task
        loadingModelChoiceStorage = model

        do {
            let loadedModel = try await task.value
            cachedModel = loadedModel
            currentModelChoiceStorage = model
            loadTask = nil
            loadingModelChoiceStorage = nil
            return loadedModel
        } catch {
            loadTask = nil
            loadingModelChoiceStorage = nil
            throw TranscriptionError.modelLoadFailed
        }
    }

    private func unloadCurrentModel() async {
        if let cachedModel {
            await unloader(cachedModel)
        }
        cachedModel = nil
        currentModelChoiceStorage = nil
    }

    private func broadcastFileDownloadProgress(_ progress: Progress, for model: WhisperModelChoice) {
        guard let observers = fileDownloadProgressObservers[model]?.values else { return }
        for observer in observers {
            observer(progress)
        }
    }

    private static func makeDefaultLoader() -> Loader {
        { model, directory in
            let config = WhisperKitConfig(
                model: model.rawValue,
                downloadBase: persistentDownloadBaseURL(),
                modelFolder: directory.path,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
            let whisperKit = try await WhisperKit(config)
            return PreparedModel(whisperKit: whisperKit)
        }
    }

    private static func defaultTranscriber(model: PreparedModel, samples: [Float]) async throws -> String {
        guard let whisperKit = model.pipeline?.whisperKit else {
            throw TranscriptionError.noModel
        }

        let options = DecodingOptions(language: "en")
        do {
            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw TranscriptionError.noSpeechDetected
            }

            return text
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.inferenceFailed
        }
    }

    private static func defaultUnloader(model: PreparedModel) async {
        guard let whisperKit = model.pipeline?.whisperKit else {
            return
        }
        await whisperKit.unloadModels()
    }

    private static func downloadModelVariant(
        _ model: WhisperModelChoice,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: model.rawValue,
            downloadBase: persistentDownloadBaseURL(),
            progressCallback: progressHandler
        )
    }

    static func downloadModelFiles(
        for model: WhisperModelChoice,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws -> URL {
        try await shared.downloadFiles(for: model, progressHandler: progressHandler)
    }

    static func isModelDownloaded(
        _ model: WhisperModelChoice,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        let directory = downloadedModelDirectory(for: model, baseURL: baseURL)
        guard fileManager.fileExists(atPath: directory.path) else {
            return false
        }

        return requiredModelArtifacts.allSatisfy { artifact in
            compiledModelDirectoryLooksComplete(
                at: directory.appendingPathComponent(artifact, isDirectory: true),
                fileManager: fileManager
            )
        }
    }

    static func downloadedModelDirectory(
        for model: WhisperModelChoice,
        baseURL: URL? = nil
    ) -> URL {
        downloadedModelDirectory(forModelIdentifier: model.rawValue, baseURL: baseURL)
    }

    static func downloadedModelDirectory(
        forModelIdentifier modelIdentifier: String,
        baseURL: URL? = nil
    ) -> URL {
        let resolvedBaseURL = baseURL ?? persistentDownloadBaseURL()
        return resolvedBaseURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(modelIdentifier)", isDirectory: true)
    }

    static func deleteDownloadedModelFiles(
        for model: WhisperModelChoice,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        try deleteDownloadedModelFiles(
            forModelIdentifier: model.rawValue,
            baseURL: baseURL,
            fileManager: fileManager
        )
    }

    static func deleteLegacyUnsupportedModelFiles(
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        try deleteDownloadedModelFiles(
            forModelIdentifier: WhisperModelChoice.legacyLargeTurboRawValue,
            baseURL: baseURL,
            fileManager: fileManager
        )
    }

    private static func deleteDownloadedModelFiles(
        forModelIdentifier modelIdentifier: String,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let directory = downloadedModelDirectory(forModelIdentifier: modelIdentifier, baseURL: baseURL)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }

        let downloadCacheDirectory = downloadedModelCacheDirectory(
            forModelIdentifier: modelIdentifier,
            baseURL: baseURL
        )
        if fileManager.fileExists(atPath: downloadCacheDirectory.path) {
            try fileManager.removeItem(at: downloadCacheDirectory)
        }
    }

    static func deleteIncompleteDownloadedModelFilesIfNeeded(
        for model: WhisperModelChoice,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let directory = downloadedModelDirectory(for: model, baseURL: baseURL)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        guard !isModelDownloaded(model, baseURL: baseURL, fileManager: fileManager) else { return }
        try deleteDownloadedModelFiles(for: model, baseURL: baseURL, fileManager: fileManager)
    }

    static func downloadedModelCacheDirectory(
        for model: WhisperModelChoice,
        baseURL: URL? = nil
    ) -> URL {
        downloadedModelCacheDirectory(forModelIdentifier: model.rawValue, baseURL: baseURL)
    }

    static func downloadedModelCacheDirectory(
        forModelIdentifier modelIdentifier: String,
        baseURL: URL? = nil
    ) -> URL {
        let resolvedBaseURL = baseURL ?? persistentDownloadBaseURL()
        return resolvedBaseURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("download", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(modelIdentifier)", isDirectory: true)
    }

    private static func persistentDownloadBaseURL(fileManager: FileManager = .default) -> URL {
        // Keep Whisper downloads in Application Support so the app no longer probes Documents at runtime.
        applicationSupportDownloadBaseURL(fileManager: fileManager)
    }

    private static func applicationSupportDownloadBaseURL(fileManager: FileManager) -> URL {
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return appSupport
                .appendingPathComponent("Speech2Text", isDirectory: true)
                .appendingPathComponent("WhisperModel", isDirectory: true)
        }

        return fileManager.temporaryDirectory
            .appendingPathComponent("Speech2Text", isDirectory: true)
            .appendingPathComponent("WhisperModel", isDirectory: true)
    }

    private func completedProgress() -> Progress {
        let done = Progress(totalUnitCount: 1)
        done.completedUnitCount = 1
        return done
    }

    private static let requiredModelArtifacts = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc"
    ]

    private static let requiredCompiledModelArtifacts = [
        "coremldata.bin",
        "metadata.json",
        "model.mil",
        "weights/weight.bin"
    ]

    private static func compiledModelDirectoryLooksComplete(
        at directory: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else {
            return false
        }

        return requiredCompiledModelArtifacts.allSatisfy { artifact in
            fileManager.fileExists(
                atPath: directory.appendingPathComponent(artifact, isDirectory: false).path
            )
        }
    }
}

@MainActor
final class WhisperModelLoadState: ObservableObject {
    struct ModelStatus: Equatable {
        let isDownloaded: Bool
        let isWarm: Bool
        let isLoading: Bool
        let isDownloading: Bool
        let isDeleting: Bool
    }

    enum Phase: Equatable {
        case idle
        case downloading(model: WhisperModelChoice, progress: Double)
        case ready(model: WhisperModelChoice)
        case failed(model: WhisperModelChoice, message: String)

        var activeModel: WhisperModelChoice? {
            switch self {
            case .idle: return nil
            case .downloading(let model, _), .ready(let model), .failed(let model, _): return model
            }
        }

        var downloadProgress: Double? {
            if case .downloading(_, let progress) = self {
                return progress
            }
            return nil
        }
    }

    static let shared = WhisperModelLoadState()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var downloadedModels: Set<WhisperModelChoice> = []
    @Published private(set) var warmModel: WhisperModelChoice?
    @Published private(set) var loadingModel: WhisperModelChoice?
    @Published private(set) var deletingModel: WhisperModelChoice?

    private var downloadTask: Task<Void, Never>?
    private var statusRefreshTask: Task<Void, Never>?

    func startDownload(for model: WhisperModelChoice) {
        downloadTask?.cancel()
        phase = .downloading(model: model, progress: 0)
        refreshStatus()

        downloadTask = Task { [weak self] in
            guard let self else { return }

            do {
                _ = try await WhisperService.downloadModelFiles(for: model) { [weak self] progress in
                    let fraction = min(max(progress.fractionCompleted, 0), 1)
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.phase else { return }
                        self.phase = .downloading(model: model, progress: fraction)
                    }
                }
                guard !Task.isCancelled else { return }
                phase = .ready(model: model)
                refreshStatus()
            } catch is CancellationError {
                // A newer download request replaced this one.
            } catch {
                phase = .failed(model: model, message: error.localizedDescription)
                refreshStatus()
            }

            downloadTask = nil
        }
    }

    func status(for model: WhisperModelChoice) -> ModelStatus {
        ModelStatus(
            isDownloaded: downloadedModels.contains(model),
            isWarm: warmModel == model,
            isLoading: loadingModel == model,
            isDownloading: phase.activeModel == model && phase.downloadProgress != nil,
            isDeleting: deletingModel == model
        )
    }

    func refreshStatus() {
        downloadedModels = Set(WhisperModelChoice.allCases.filter { model in
            WhisperService.isModelDownloaded(model)
        })
        statusRefreshTask?.cancel()
        statusRefreshTask = Task { [weak self] in
            guard let self else { return }
            let warmModel = await WhisperService.shared.loadedModelChoice()
            let loadingModel = await WhisperService.shared.loadingModelChoice()
            guard !Task.isCancelled else { return }
            self.warmModel = warmModel
            self.loadingModel = loadingModel
            self.statusRefreshTask = nil
        }
    }

    func deleteModel(for model: WhisperModelChoice) {
        downloadTask?.cancel()
        downloadTask = nil
        phase = .idle
        deletingModel = model

        Task { [weak self] in
            guard let self else { return }

            do {
                try await WhisperService.shared.deleteDownloadedModel(for: model)
                if self.phase.activeModel == model {
                    self.phase = .idle
                }
                self.deletingModel = nil
                self.refreshStatus()
            } catch {
                self.deletingModel = nil
                self.phase = .failed(model: model, message: error.localizedDescription)
                self.refreshStatus()
            }
        }
    }
}
