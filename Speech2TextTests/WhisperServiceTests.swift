import XCTest
@testable import Speech2Text

// MARK: - Mock

final class MockWhisperTranscriber: WhisperTranscribing, @unchecked Sendable {
    var resultToReturn: String = "hello world"
    var errorToThrow: Error? = nil

    func transcribe(samples: [Float]) async throws -> String {
        if let error = errorToThrow {
            throw error
        }
        return resultToReturn
    }
}

// MARK: - Tests

final class WhisperServiceTests: XCTestCase {
    func testMockReturnsExpectedText() async throws {
        let mock = MockWhisperTranscriber()
        mock.resultToReturn = "unit test text"
        let result = try await mock.transcribe(samples: [0.1, 0.2])
        XCTAssertEqual(result, "unit test text")
    }

    func testMockThrowsNoSpeechDetectedForEmptyResult() async throws {
        let mock = MockWhisperTranscriber()
        mock.errorToThrow = TranscriptionError.noSpeechDetected
        do {
            _ = try await mock.transcribe(samples: [0.0])
            XCTFail("Expected noSpeechDetected to be thrown")
        } catch TranscriptionError.noSpeechDetected {
            // expected
        }
    }

    func testTranscriptionErrorCasesHaveDescriptions() {
        let errors: [TranscriptionError] = [
            .modelLoadFailed,
            .noModel,
            .inferenceFailed,
            .noSpeechDetected
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                           "\(error) should have a non-empty errorDescription")
        }
    }

    func testWhisperServiceThrowsNoModelBeforePrepare() async throws {
        let service = WhisperService()
        do {
            _ = try await service.transcribe(samples: [0.1, 0.2])
            XCTFail("Expected noModel to be thrown")
        } catch TranscriptionError.noModel {
            // expected
        }
    }

    func testConcurrentPrepareRequestsShareInflightLoadTask() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _, _ in
                await loadCounter.increment()
                try await Task.sleep(nanoseconds: 50_000_000)
                return .init()
            }
        )

        async let first: Void = service.prepare(model: .baseEN)
        async let second: Void = service.prepare(model: .baseEN)
        _ = try await (first, second)

        let count = await loadCounter.value()
        XCTAssertEqual(count, 1)
    }

    func testDownloadFilesAndPrepareShareInflightDownloadTask() async throws {
        let downloadCounter = CallCounter()
        let loadCounter = CallCounter()
        let modelDirectory = URL(fileURLWithPath: "/tmp/WhisperServiceTests.shared-download")
        let service = makeService(
            loader: { _, _ in
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
            }
        )

        async let backgroundDownload: URL = service.downloadFiles(for: .baseEN)
        try await Task.sleep(nanoseconds: 20_000_000)
        async let prepare: Void = service.prepare(model: .baseEN)
        _ = try await (backgroundDownload, prepare)

        let downloadCount = await downloadCounter.value()
        let loadCount = await loadCounter.value()
        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(loadCount, 1)
    }

    func testUnloadClearsCachedModelAndForcesReloadOnNextPrepare() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _, _ in
                await loadCounter.increment()
                return .init()
            }
        )

        try await service.prepare(model: .baseEN)
        await service.unload()
        try await service.prepare(model: .baseEN)

        let count = await loadCounter.value()
        XCTAssertEqual(count, 2)
    }

    func testScheduledIdleUnloadClearsCachedModelAfterDelay() async throws {
        let loadCounter = CallCounter()
        let service = makeService(
            loader: { _, _ in
                await loadCounter.increment()
                return .init()
            }
        )

        try await service.prepare(model: .baseEN)
        await service.scheduleIdleUnload(afterNanoseconds: 20_000_000)
        try await Task.sleep(nanoseconds: 60_000_000)
        try await service.prepare(model: .baseEN)

        let count = await loadCounter.value()
        XCTAssertEqual(count, 2)
    }

    func testDownloadedModelDetectionReturnsTrueWhenDirectoryHasRequiredArtifacts() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("WhisperServiceTests.Downloaded.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = WhisperService.downloadedModelDirectory(for: .baseEN, baseURL: baseURL)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        for artifact in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            try fileManager.createDirectory(
                at: modelDirectory.appendingPathComponent(artifact, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        XCTAssertTrue(WhisperService.isModelDownloaded(.baseEN, baseURL: baseURL, fileManager: fileManager))
    }

    func testDeleteDownloadedModelFilesRemovesOnlySelectedDirectory() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("WhisperServiceTests.Delete.\(UUID().uuidString)", isDirectory: true)
        let baseDirectory = WhisperService.downloadedModelDirectory(for: .baseEN, baseURL: baseURL)
        let smallDirectory = WhisperService.downloadedModelDirectory(for: .smallEN, baseURL: baseURL)

        for directory in [baseDirectory, smallDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for artifact in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
                try fileManager.createDirectory(
                    at: directory.appendingPathComponent(artifact, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
        }

        try WhisperService.deleteDownloadedModelFiles(for: .baseEN, baseURL: baseURL, fileManager: fileManager)

        XCTAssertFalse(fileManager.fileExists(atPath: baseDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: smallDirectory.path))
    }

    private func makeService(
        loader: @escaping WhisperService.Loader = { _, _ in .init() },
        fileDownloader: WhisperService.FileDownloader? = nil,
        transcriber: @escaping WhisperService.Transcriber = { _, _ in "ok" },
        unloader: @escaping WhisperService.Unloader = { _ in }
    ) -> WhisperService {
        WhisperService(
            loader: loader,
            fileDownloader: fileDownloader,
            transcriber: transcriber,
            unloader: unloader
        )
    }
}

private actor CallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
