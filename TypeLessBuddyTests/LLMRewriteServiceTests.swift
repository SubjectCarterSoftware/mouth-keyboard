import CoreImage
import XCTest
import Hub
import MLXLMCommon
@testable import TypeLessBuddy

private struct StubError: Error {}

private actor CallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private final class SyncCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor GenerationProbe {
    private var started = 0
    private var active = 0
    private var maxActive = 0
    private var firstRelease: CheckedContinuation<Void, Never>?

    func start() -> Int {
        started += 1
        active += 1
        maxActive = max(maxActive, active)
        return started
    }

    func finish() {
        active -= 1
    }

    func awaitFirstReleaseIfNeeded(order: Int) async {
        guard order == 1 else { return }
        await withCheckedContinuation { continuation in
            firstRelease = continuation
        }
    }

    func releaseFirst() {
        firstRelease?.resume()
        firstRelease = nil
    }

    func snapshot() -> (started: Int, maxActive: Int) {
        (started, maxActive)
    }
}

final class LocalRewriteServiceTests: XCTestCase {

    func testSuccessfulRewriteReturnsTrimmedNonEmptyText() async throws {
        let service = makeService { _, _, _, _, _ in
            stream(events: [.chunk("  rewritten text  "), .completion(.stop)])
        }

        let rewritten = try await service.rewrite(body: "raw", instructions: "")
        XCTAssertEqual(rewritten, "rewritten text")
    }

    func testGeneratePassesImagesToStreamFactory() async throws {
        let imageCount = SyncCounter()
        let service = makeService { _, _, _, _, images in
            if images.count == 1 {
                imageCount.increment()
            }
            return stream(events: [.chunk("ready"), .completion(.stop)])
        }

        let image = UserInput.Image.ciImage(
            CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
                .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        )

        let output = try await service.generate(
            prompt: "hello",
            systemPrompt: "reply ready",
            images: [image]
        )

        XCTAssertEqual(output, "ready")
        XCTAssertEqual(imageCount.count, 1)
    }

    func testSequentialRewritesReuseLoadedContainer() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _ in
                await loadCounter.increment()
                return .init()
            },
            streamFactory: { _, _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        _ = try await service.rewrite(body: "one", instructions: "")
        _ = try await service.rewrite(body: "two", instructions: "")

        let loadCount = await loadCounter.value()
        XCTAssertEqual(loadCount, 1)
    }

    func testConcurrentFirstRewritesShareInflightLoadTask() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _ in
                await loadCounter.increment()
                try await Task.sleep(nanoseconds: 50_000_000)
                return .init()
            },
            streamFactory: { _, _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        async let first: String = service.rewrite(body: "one", instructions: "")
        async let second: String = service.rewrite(body: "two", instructions: "")
        _ = try await (first, second)

        let loadCount = await loadCounter.value()
        XCTAssertEqual(loadCount, 1)
    }

    func testDownloadAndRewriteShareInflightLoadTask() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _ in
                await loadCounter.increment()
                try await Task.sleep(nanoseconds: 50_000_000)
                return .init()
            },
            streamFactory: { _, _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        async let preload: Void = service.download()
        try await Task.sleep(nanoseconds: 20_000_000)
        async let rewrite: String = service.rewrite(body: "one", instructions: "")
        _ = try await (preload, rewrite)

        let loadCount = await loadCounter.value()
        XCTAssertEqual(loadCount, 1)
    }

    func testConcurrentRewritesDoNotOverlapGeneration() async throws {
        let probe = GenerationProbe()
        let service = makeService { _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                let task = Task {
                    let order = await probe.start()
                    await probe.awaitFirstReleaseIfNeeded(order: order)
                    continuation.yield(.chunk("done \(order)"))
                    continuation.yield(.completion(.stop))
                    continuation.finish()
                    await probe.finish()
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }

        let firstTask = Task { try await service.rewrite(body: "first", instructions: "") }
        try await Task.sleep(nanoseconds: 20_000_000)
        let secondTask = Task { try await service.rewrite(body: "second", instructions: "") }
        try await Task.sleep(nanoseconds: 20_000_000)
        await probe.releaseFirst()

        _ = try await firstTask.value
        _ = try await secondTask.value

        let snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.started, 2)
        XCTAssertEqual(snapshot.maxActive, 1)
    }

    func testEachRewriteCreatesFreshSessionEvenWithCachedModel() async throws {
        let streamCounter = SyncCounter()
        let service = makeService(
            loader: { _ in .init() },
            streamFactory: { _, _, _, _, _ in
                streamCounter.increment()
                return stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        _ = try await service.rewrite(body: "one", instructions: "")
        _ = try await service.rewrite(body: "two", instructions: "")

        XCTAssertEqual(streamCounter.count, 2)
    }

    func testLoaderFailureThrowsModelLoadFailed() async throws {
        let service = makeService(
            loader: { _ in throw StubError() },
            streamFactory: { _, _, _, _, _ in
                XCTFail("Stream should not run when model loading fails")
                return stream(events: [])
            }
        )

        await assertRewriteError(.modelLoadFailed) {
            try await service.rewrite(body: "raw", instructions: "")
        }
    }

    func testThrownStreamErrorThrowsGenerationFailed() async throws {
        let service = makeService { _, _, _, _, _ in
            stream(events: [.chunk("partial")], error: StubError())
        }

        await assertRewriteError(.generationFailed) {
            try await service.rewrite(body: "raw", instructions: "")
        }
    }

    func testCancelledCompletionThrowsCancelled() async throws {
        let service = makeService { _, _, _, _, _ in
            stream(events: [.chunk("partial"), .completion(.cancelled)])
        }

        await assertRewriteError(.cancelled) {
            try await service.rewrite(body: "raw", instructions: "")
        }
    }

    func testTaskCancellationThrowsCancelled() async throws {
        let service = makeService { _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(.chunk("partial"))
                    try await Task.sleep(nanoseconds: 500_000_000)
                    continuation.yield(.completion(.stop))
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }

        let rewriteTask = Task { try await service.rewrite(body: "raw", instructions: "") }
        try await Task.sleep(nanoseconds: 20_000_000)
        rewriteTask.cancel()

        await assertRewriteError(.cancelled) {
            try await rewriteTask.value
        }
    }

    func testLengthCompletionThrowsOutputTruncated() async throws {
        let service = makeService { _, _, _, _, _ in
            stream(events: [.chunk("partial"), .completion(.length)])
        }

        await assertRewriteError(.outputTruncated) {
            try await service.rewrite(body: "raw", instructions: "")
        }
    }

    func testWhitespaceOnlyOutputThrowsEmptyOutput() async throws {
        let service = makeService { _, _, _, _, _ in
            stream(events: [.chunk(" \n\t "), .completion(.stop)])
        }

        await assertRewriteError(.emptyOutput) {
            try await service.rewrite(body: "raw", instructions: "")
        }
    }

    func testChunkedTextIsNotReturnedWhenFailureOccursLater() async throws {
        let service = makeService { _, _, _, _, _ in
            stream(events: [.chunk("keep me out")], error: StubError())
        }

        await assertRewriteError(.generationFailed) {
            try await service.rewrite(body: "raw", instructions: "")
        }
    }

    // MARK: - rewrite(body:instructions:) overload tests (Phase 11-02)

    func testRewriteWithInstructionsOverloadExists() async throws {
        // Verifies the overload compiles, is callable, and passes the built system prompt to the stream factory.
        var capturedInstructions: String?
        let service = makeService { _, _, instructions, _, _ in
            capturedInstructions = instructions
            return stream(events: [.chunk("rewritten"), .completion(.stop)])
        }
        let result = try await service.rewrite(body: "raw", instructions: "Be brief.")
        XCTAssertEqual(result, "rewritten")
        XCTAssertEqual(
            capturedInstructions,
            LocalRewriteService.makeRewriteInstructions(instructions: "Be brief.")
        )
    }

    func testMakeRewritePromptIncludesInstructionsAndBody() {
        let prompt = LocalRewriteService.makeRewritePrompt(
            body: "Draft note for finance.",
            instructions: "Turn this into a short email."
        )

        XCTAssertTrue(prompt.contains("Rewrite instructions:\nTurn this into a short email."))
        XCTAssertTrue(prompt.contains("Source text:\nDraft note for finance."))
        XCTAssertTrue(prompt.contains("Return only the final rewritten text."))
        XCTAssertTrue(prompt.contains("Output only the final answer text."))
        XCTAssertTrue(prompt.contains("Do not surround the answer in quotation marks unless the user explicitly asks for quotes."))
    }

    func testMakeRewriteInstructionsUsesCustomPromptPrefix() {
        let prompt = LocalRewriteService.makeRewriteInstructions(
            promptPrefix: "Custom prefix.\nStay concise.",
            instructions: "Turn this into a short email."
        )

        XCTAssertTrue(prompt.contains("Custom prefix.\nStay concise."))
        XCTAssertTrue(prompt.contains("Rewrite instructions:\nTurn this into a short email."))
        XCTAssertFalse(prompt.contains("You are a local text rewriting assistant."))
    }

    func testMakeRewritePromptUsesSafeDefaultWhenInstructionsAreEmpty() {
        let prompt = LocalRewriteService.makeRewritePrompt(
            body: "Keep this exactly.",
            instructions: "   "
        )

        XCTAssertTrue(prompt.contains("Rewrite instructions:\nReturn the source text exactly as written."))
        XCTAssertTrue(prompt.contains("Source text:\nKeep this exactly."))
    }

    func testBlankPromptPrefixFallsBackToDefaultPrefix() {
        let prompt = LocalRewriteService.makeRewriteInstructions(
            promptPrefix: "   ",
            instructions: "Keep this tidy."
        )

        XCTAssertTrue(prompt.contains(LocalRewriteService.defaultRewritePromptPrefix))
        XCTAssertTrue(prompt.contains("Rewrite instructions:\nKeep this tidy."))
    }

    func testResolveAssistantSystemPromptSubstitutesAssistantNamePlaceholder() {
        let resolved = LocalRewriteService.resolveAssistantSystemPrompt(
            promptTemplate: LocalRewriteService.defaultAssistantSystemPromptTemplate,
            assistantName: "Ava"
        )

        XCTAssertTrue(resolved.contains("You are Ava"))
        XCTAssertFalse(resolved.contains(LocalRewriteService.assistantNamePlaceholder))
    }

    func testBlankAssistantPromptTemplateFallsBackToAssistantDefault() {
        let resolved = LocalRewriteService.resolveAssistantSystemPrompt(
            promptTemplate: "   ",
            assistantName: "Ava"
        )

        XCTAssertEqual(
            resolved,
            LocalRewriteService.resolveAssistantSystemPrompt(
                promptTemplate: LocalRewriteService.defaultAssistantSystemPromptTemplate,
                assistantName: "Ava"
            )
        )
    }

    func testSanitizeGeneratedOutputExtractsQuotedArtifactAfterMetaPreamble() {
        let output = """
        Sure, here is a draft message you can send to Caroline:

        "Hi Caroline, just wanted to drop a quick note. I'm a bit stuck on how to handle this customer."
        """

        XCTAssertEqual(
            LocalRewriteService.sanitizeGeneratedOutput(output),
            "Hi Caroline, just wanted to drop a quick note. I'm a bit stuck on how to handle this customer."
        )
    }

    func testSanitizeGeneratedOutputStripsSimpleLeadingArtifactLabel() {
        let output = "Message: Hi Caroline, can you take a look at this when you have a minute?"

        XCTAssertEqual(
            LocalRewriteService.sanitizeGeneratedOutput(output),
            "Hi Caroline, can you take a look at this when you have a minute?"
        )
    }

    func testSanitizeGeneratedOutputLeavesStandaloneQuotedTextUntouched() {
        let output = "\"Keep the quotes exactly like this.\""

        XCTAssertEqual(
            LocalRewriteService.sanitizeGeneratedOutput(output),
            "\"Keep the quotes exactly like this.\""
        )
    }

    // MARK: - setTier tests (Phase 2)

    func testSetTierClearsCachedModelAndLoadTaskForNextCall() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _ in
                await loadCounter.increment()
                return .init()
            },
            streamFactory: { _, _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        // First rewrite loads the model once.
        _ = try await service.rewrite(body: "one", instructions: "")
        let countAfterFirst = await loadCounter.value()
        XCTAssertEqual(countAfterFirst, 1)

        // Changing tier clears the cache; next rewrite loads again.
        await service.setTier(.standard4B)
        _ = try await service.rewrite(body: "two", instructions: "")
        let countAfterTierChange = await loadCounter.value()
        XCTAssertEqual(countAfterTierChange, 2)
    }

    func testSetTierToSameTierDoesNotInvalidateCache() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _ in
                await loadCounter.increment()
                return .init()
            },
            streamFactory: { _, _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        _ = try await service.rewrite(body: "one", instructions: "")
        await service.setTier(.standard2B) // same tier — no-op
        _ = try await service.rewrite(body: "two", instructions: "")

        let count = await loadCounter.value()
        XCTAssertEqual(count, 1)
    }

    func testUnloadClearsCachedModelAndForcesReloadOnNextUse() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _ in
                await loadCounter.increment()
                return .init()
            },
            streamFactory: { _, _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        try await service.prewarm()
        await service.unload()
        _ = try await service.rewrite(body: "two", instructions: "")

        let count = await loadCounter.value()
        XCTAssertEqual(count, 2)
    }

    func testScheduledIdleUnloadClearsCachedModelAfterDelay() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _ in
                await loadCounter.increment()
                return .init()
            },
            streamFactory: { _, _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        try await service.prewarm()
        await service.scheduleIdleUnload(afterNanoseconds: 20_000_000)
        try await Task.sleep(nanoseconds: 60_000_000)
        _ = try await service.rewrite(body: "two", instructions: "")

        let count = await loadCounter.value()
        XCTAssertEqual(count, 2)
    }

    func testDownloadFilesAndRewriteShareInflightDownloadTask() async throws {
        let downloadCounter = CallCounter()
        let loadCounter = CallCounter()
        let modelDirectory = URL(fileURLWithPath: "/tmp/LocalRewriteServiceTests.shared-download")
        let service = makeService(
            loader: { _ in
                await loadCounter.increment()
                return .init()
            },
            fileDownloader: { _, progressHandler in
                await downloadCounter.increment()
                let progress = Progress(totalUnitCount: 1)
                progress.completedUnitCount = 0
                progressHandler(progress)
                try await Task.sleep(nanoseconds: 50_000_000)
                progress.completedUnitCount = 1
                progressHandler(progress)
                return modelDirectory
            },
            streamFactory: { _, _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        async let backgroundDownload: URL = service.downloadFiles(for: .standard2B)
        try await Task.sleep(nanoseconds: 20_000_000)
        async let rewrite: String = service.rewrite(body: "one", instructions: "")
        _ = try await (backgroundDownload, rewrite)

        let downloadCount = await downloadCounter.value()
        let loadCount = await loadCounter.value()
        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(loadCount, 1)
    }

    func testDownloadedModelDetectionReturnsFalseWhenBuiltInTierDirectoryLacksRequiredArtifacts() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalRewriteServiceTests.Downloaded.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = try LocalRewriteService.downloadedModelDirectory(
            for: .standard2B,
            baseURL: baseURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data("weights".utf8).write(to: modelDirectory.appendingPathComponent("model.safetensors"))

        XCTAssertFalse(
            LocalRewriteService.isModelDownloaded(.standard2B, baseURL: baseURL, fileManager: fileManager)
        )
    }

    func testDownloadedModelDetectionReturnsTrueWhenBuiltInTierDirectoryHasCurrentArtifacts() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalRewriteServiceTests.CurrentArtifacts.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = try LocalRewriteService.downloadedModelDirectory(
            for: .standard2B,
            baseURL: baseURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer_config.json"))
        try Data("{% raw %}".utf8).write(to: modelDirectory.appendingPathComponent("chat_template.jinja"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("processor_config.json"))
        try Data("weights".utf8).write(to: modelDirectory.appendingPathComponent("model.safetensors"))

        XCTAssertTrue(
            LocalRewriteService.isModelDownloaded(.standard2B, baseURL: baseURL, fileManager: fileManager)
        )
    }

    func testPreparedModelDetectionReturnsFalseWithoutPreparedMarker() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalRewriteServiceTests.PreparedMissing.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = try LocalRewriteService.downloadedModelDirectory(
            for: .standard2B,
            baseURL: baseURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer_config.json"))
        try Data("{% raw %}".utf8).write(to: modelDirectory.appendingPathComponent("chat_template.jinja"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("processor_config.json"))
        try Data("weights".utf8).write(to: modelDirectory.appendingPathComponent("model.safetensors"))

        XCTAssertFalse(
            LocalRewriteService.isModelPrepared(.standard2B, baseURL: baseURL, fileManager: fileManager)
        )
    }

    func testPreparedModelDetectionReturnsTrueWithPreparedMarker() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalRewriteServiceTests.PreparedPresent.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = try LocalRewriteService.downloadedModelDirectory(
            for: .standard2B,
            baseURL: baseURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer_config.json"))
        try Data("{% raw %}".utf8).write(to: modelDirectory.appendingPathComponent("chat_template.jinja"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("processor_config.json"))
        try Data("weights".utf8).write(to: modelDirectory.appendingPathComponent("model.safetensors"))
        fileManager.createFile(
            atPath: modelDirectory.appendingPathComponent(".typelessbuddy-prepared").path,
            contents: Data(),
            attributes: nil
        )

        XCTAssertTrue(
            LocalRewriteService.isModelPrepared(.standard2B, baseURL: baseURL, fileManager: fileManager)
        )
    }

    func testDownloadedModelDetectionReturnsFalseWhenTierDirectoryIsMissingRequiredArtifacts() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalRewriteServiceTests.Incomplete.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = try LocalRewriteService.downloadedModelDirectory(
            for: .standard2B,
            baseURL: baseURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))

        XCTAssertFalse(
            LocalRewriteService.isModelDownloaded(.standard2B, baseURL: baseURL, fileManager: fileManager)
        )
    }

    func testRequiredDownloadPatternsCoverCurrentBuiltInArtifacts() {
        let requiredArtifacts = ["config.json", "tokenizer.json", "tokenizer_config.json", "processor_config.json", "chat_template.jinja"]
        let patterns = LocalRewriteService.requiredDownloadPatterns(for: .standard4B)

        for artifact in requiredArtifacts {
            XCTAssertTrue(
                patterns.contains { patternMatches($0, fileName: artifact) },
                "Expected download patterns \(patterns) to cover \(artifact)"
            )
        }
    }

    func testOnlyIdleAllowsRewriteModelManagement() {
        XCTAssertTrue(RecordingState.idle.allowsRewriteModelManagement)
        XCTAssertFalse(RecordingState.recording.allowsRewriteModelManagement)
        XCTAssertFalse(RecordingState.processing.allowsRewriteModelManagement)
        XCTAssertFalse(RecordingState.modelDownloading(model: .baseEN, progress: 0.5).allowsRewriteModelManagement)
        XCTAssertFalse(RecordingState.converting.allowsRewriteModelManagement)
        XCTAssertFalse(RecordingState.success(text: "ok", pasted: false, converted: true).allowsRewriteModelManagement)
        XCTAssertFalse(RecordingState.failure(reason: .noSpeechDetected).allowsRewriteModelManagement)
    }

    func testDeleteIncompleteDownloadedModelFilesIfNeededRemovesPartialTierDirectory() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalRewriteServiceTests.RepairIncomplete.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = try LocalRewriteService.downloadedModelDirectory(
            for: .standard4B,
            baseURL: baseURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer_config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("processor_config.json"))
        try Data("weights".utf8).write(to: modelDirectory.appendingPathComponent("model.safetensors"))

        try LocalRewriteService.deleteIncompleteDownloadedModelFilesIfNeeded(
            for: .standard4B,
            baseURL: baseURL,
            fileManager: fileManager
        )

        XCTAssertFalse(fileManager.fileExists(atPath: modelDirectory.path))
    }

    func testDeleteIncompleteDownloadedModelFilesIfNeededPreservesCompleteTierDirectory() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalRewriteServiceTests.PreserveComplete.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = try LocalRewriteService.downloadedModelDirectory(
            for: .standard4B,
            baseURL: baseURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("tokenizer_config.json"))
        try Data("{% raw %}".utf8).write(to: modelDirectory.appendingPathComponent("chat_template.jinja"))
        try Data("{}".utf8).write(to: modelDirectory.appendingPathComponent("processor_config.json"))
        try Data("weights".utf8).write(to: modelDirectory.appendingPathComponent("model.safetensors"))

        try LocalRewriteService.deleteIncompleteDownloadedModelFilesIfNeeded(
            for: .standard4B,
            baseURL: baseURL,
            fileManager: fileManager
        )

        XCTAssertTrue(fileManager.fileExists(atPath: modelDirectory.path))
    }

    func testDeleteDownloadedModelFilesRemovesOnlySelectedTierDirectory() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalRewriteServiceTests.Delete.\(UUID().uuidString)", isDirectory: true)
        let standard2BDirectory = try LocalRewriteService.downloadedModelDirectory(
            for: .standard2B,
            baseURL: baseURL,
            fileManager: fileManager
        )
        let standard4BDirectory = try LocalRewriteService.downloadedModelDirectory(
            for: .standard4B,
            baseURL: baseURL,
            fileManager: fileManager
        )

        try fileManager.createDirectory(at: standard2BDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: standard4BDirectory, withIntermediateDirectories: true)
        try Data("2b".utf8).write(to: standard2BDirectory.appendingPathComponent("config.json"))
        try Data("4b".utf8).write(to: standard4BDirectory.appendingPathComponent("config.json"))

        try LocalRewriteService.deleteDownloadedModelFiles(
            for: .standard2B,
            baseURL: baseURL,
            fileManager: fileManager
        )

        XCTAssertFalse(fileManager.fileExists(atPath: standard2BDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: standard4BDirectory.path))
    }

    func testModelTooLargeForDeviceIsThrownOnMemoryPressureError() async throws {
        struct FakeOOMError: LocalizedError {
            var errorDescription: String? { "out of memory: alloc failed" }
        }

        let service = makeService(
            loader: { _ in throw FakeOOMError() },
            streamFactory: { _, _, _, _, _ in
                XCTFail("Stream should not run when model loading fails")
                return stream(events: [])
            }
        )

        await assertRewriteError(.modelTooLargeForDevice) {
            try await service.rewrite(body: "raw", instructions: "")
        }
    }

    func testRegularLoadFailureThrowsModelLoadFailed() async throws {
        struct OtherError: Error {}

        let service = makeService(
            loader: { _ in throw OtherError() },
            streamFactory: { _, _, _, _, _ in
                XCTFail("Stream should not run when model loading fails")
                return stream(events: [])
            }
        )

        await assertRewriteError(.modelLoadFailed) {
            try await service.rewrite(body: "raw", instructions: "")
        }
    }

    private func makeService(
        tier: RewriteModelTier = .standard2B,
        loader: @escaping LocalRewriteService.Loader = { _ in .init() },
        fileDownloader: LocalRewriteService.FileDownloader? = nil,
        streamFactory: @escaping LocalRewriteService.StreamFactory
    ) -> LocalRewriteService {
        LocalRewriteService(
            tier: tier,
            loader: loader,
            fileDownloader: fileDownloader,
            streamFactory: streamFactory,
            hubFactory: { HubApi(downloadBase: URL(fileURLWithPath: "/tmp")) }
        )
    }

    private func assertRewriteError(
        _ expected: RewriteError,
        operation: () async throws -> String
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected) to be thrown")
        } catch let error as RewriteError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Expected \(expected), got \(error)")
        }
    }
}

private func stream(
    events: [LocalRewriteService.RewriteEvent],
    error: Error? = nil
) -> AsyncThrowingStream<LocalRewriteService.RewriteEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            for event in events {
                continuation.yield(event)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

private func patternMatches(_ pattern: String, fileName: String) -> Bool {
    let escaped = NSRegularExpression.escapedPattern(for: pattern)
        .replacingOccurrences(of: "\\*", with: ".*")
        .replacingOccurrences(of: "\\?", with: ".")
    let regex = try? NSRegularExpression(pattern: "^\(escaped)$", options: [.caseInsensitive])
    let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
    return regex?.firstMatch(in: fileName, options: [], range: range) != nil
}

extension LocalRewriteServiceTests {
    func testThinkStripperSimpleNoThink() {
        var stripper = ThinkStripper()
        let result = stripper.process("Hello world!") + stripper.flush()
        XCTAssertEqual(result, "Hello world!")
    }

    func testThinkStripperCompleteThinkBlock() {
        var stripper = ThinkStripper()
        let result = stripper.process("Hello <think> internal thought </think> world!") + stripper.flush()
        XCTAssertEqual(result, "Hello  world!")
    }

    func testThinkStripperFragmentedTags() {
        var stripper = ThinkStripper()
        var result = ""
        result += stripper.process("Hello <")
        result += stripper.process("th")
        result += stripper.process("ink>")
        result += stripper.process(" internal ")
        result += stripper.process("</thi")
        result += stripper.process("nk> world!")
        result += stripper.flush()
        
        XCTAssertEqual(result, "Hello  world!")
    }

    func testThinkStripperPartialMatchThatWasntATag() {
        var stripper = ThinkStripper()
        var result = ""
        result += stripper.process("This costs <")
        result += stripper.process("5 dollars.")
        result += stripper.flush()
        
        XCTAssertEqual(result, "This costs <5 dollars.")
    }

    func testThinkStripperMultipleThinkBlocks() {
        var stripper = ThinkStripper()
        let text = "a<think>b</think>c<think>d</think>e"
        let result = stripper.process(text) + stripper.flush()
        XCTAssertEqual(result, "ace")
    }
}
