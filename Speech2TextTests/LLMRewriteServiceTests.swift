import XCTest
import Hub
import MLXLMCommon
@testable import Speech2Text

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

final class LLMRewriteServiceTests: XCTestCase {

    func testSuccessfulRewriteReturnsTrimmedNonEmptyText() async throws {
        let service = makeService { _, _, _, _ in
            stream(events: [.chunk("  rewritten text  "), .completion(.stop)])
        }

        let rewritten = try await service.rewrite(body: "raw", mode: .cleanEnglish)
        XCTAssertEqual(rewritten, "rewritten text")
    }

    func testRewriteUsesModeDefaultSystemPrompt() async throws {
        var capturedInstructions: String?
        let service = makeService { _, _, instructions, _ in
            capturedInstructions = instructions
            return stream(events: [.chunk("ok"), .completion(.stop)])
        }

        _ = try await service.rewrite(body: "raw", mode: .teams)
        XCTAssertEqual(capturedInstructions, ConvertMode.teams.defaultSystemPrompt)
    }

    func testSequentialRewritesReuseLoadedContainer() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _ in
                await loadCounter.increment()
                return .init()
            },
            streamFactory: { _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        _ = try await service.rewrite(body: "one", mode: .email)
        _ = try await service.rewrite(body: "two", mode: .email)

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
            streamFactory: { _, _, _, _ in
                stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        async let first: String = service.rewrite(body: "one", mode: .slack)
        async let second: String = service.rewrite(body: "two", mode: .slack)
        _ = try await (first, second)

        let loadCount = await loadCounter.value()
        XCTAssertEqual(loadCount, 1)
    }

    func testConcurrentRewritesDoNotOverlapGeneration() async throws {
        let probe = GenerationProbe()
        let service = makeService { _, _, _, _ in
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

        let firstTask = Task { try await service.rewrite(body: "first", mode: .aiPrompt) }
        try await Task.sleep(nanoseconds: 20_000_000)
        let secondTask = Task { try await service.rewrite(body: "second", mode: .aiPrompt) }
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
            streamFactory: { _, _, _, _ in
                streamCounter.increment()
                return stream(events: [.chunk("ok"), .completion(.stop)])
            }
        )

        _ = try await service.rewrite(body: "one", mode: .actionItems)
        _ = try await service.rewrite(body: "two", mode: .actionItems)

        XCTAssertEqual(streamCounter.count, 2)
    }

    func testLoaderFailureThrowsModelLoadFailed() async throws {
        let service = makeService(
            loader: { _ in throw StubError() },
            streamFactory: { _, _, _, _ in
                XCTFail("Stream should not run when model loading fails")
                return stream(events: [])
            }
        )

        await assertRewriteError(.modelLoadFailed) {
            try await service.rewrite(body: "raw", mode: .cleanEnglish)
        }
    }

    func testThrownStreamErrorThrowsGenerationFailed() async throws {
        let service = makeService { _, _, _, _ in
            stream(events: [.chunk("partial")], error: StubError())
        }

        await assertRewriteError(.generationFailed) {
            try await service.rewrite(body: "raw", mode: .cleanEnglish)
        }
    }

    func testCancelledCompletionThrowsCancelled() async throws {
        let service = makeService { _, _, _, _ in
            stream(events: [.chunk("partial"), .completion(.cancelled)])
        }

        await assertRewriteError(.cancelled) {
            try await service.rewrite(body: "raw", mode: .cleanEnglish)
        }
    }

    func testTaskCancellationThrowsCancelled() async throws {
        let service = makeService { _, _, _, _ in
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

        let rewriteTask = Task { try await service.rewrite(body: "raw", mode: .cleanEnglish) }
        try await Task.sleep(nanoseconds: 20_000_000)
        rewriteTask.cancel()

        await assertRewriteError(.cancelled) {
            try await rewriteTask.value
        }
    }

    func testLengthCompletionThrowsOutputTruncated() async throws {
        let service = makeService { _, _, _, _ in
            stream(events: [.chunk("partial"), .completion(.length)])
        }

        await assertRewriteError(.outputTruncated) {
            try await service.rewrite(body: "raw", mode: .cleanEnglish)
        }
    }

    func testWhitespaceOnlyOutputThrowsEmptyOutput() async throws {
        let service = makeService { _, _, _, _ in
            stream(events: [.chunk(" \n\t "), .completion(.stop)])
        }

        await assertRewriteError(.emptyOutput) {
            try await service.rewrite(body: "raw", mode: .cleanEnglish)
        }
    }

    func testChunkedTextIsNotReturnedWhenFailureOccursLater() async throws {
        let service = makeService { _, _, _, _ in
            stream(events: [.chunk("keep me out")], error: StubError())
        }

        await assertRewriteError(.generationFailed) {
            try await service.rewrite(body: "raw", mode: .cleanEnglish)
        }
    }

    private func makeService(
        loader: @escaping LLMRewriteService.Loader = { _ in .init() },
        streamFactory: @escaping LLMRewriteService.StreamFactory
    ) -> LLMRewriteService {
        LLMRewriteService(
            loader: loader,
            streamFactory: streamFactory,
            generationParameters: .init(maxTokens: 64, temperature: 0, topP: 1.0),
            hubFactory: { HubApi(downloadBase: URL(fileURLWithPath: "/tmp")) }
        )
    }

    private func assertRewriteError(
        _ expected: LLMRewriteError,
        operation: () async throws -> String
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected) to be thrown")
        } catch let error as LLMRewriteError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Expected \(expected), got \(error)")
        }
    }
}

private func stream(
    events: [LLMRewriteService.RewriteEvent],
    error: Error? = nil
) -> AsyncThrowingStream<LLMRewriteService.RewriteEvent, Error> {
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
