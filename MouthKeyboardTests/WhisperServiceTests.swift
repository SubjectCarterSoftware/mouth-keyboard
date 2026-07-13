import XCTest
@testable import TypeLessBuddy

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
        try createCompleteModelArtifacts(in: modelDirectory, fileManager: fileManager)

        XCTAssertTrue(WhisperService.isModelDownloaded(.baseEN, baseURL: baseURL, fileManager: fileManager))
    }

    func testDownloadedModelDetectionReturnsFalseWhenCompiledModelArtifactsAreIncomplete() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("WhisperServiceTests.Incomplete.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = WhisperService.downloadedModelDirectory(for: .baseEN, baseURL: baseURL)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try createCompleteModelArtifacts(in: modelDirectory, fileManager: fileManager)
        try fileManager.removeItem(
            at: modelDirectory
                .appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true)
                .appendingPathComponent("weights", isDirectory: true)
                .appendingPathComponent("weight.bin", isDirectory: false)
        )

        XCTAssertFalse(WhisperService.isModelDownloaded(.baseEN, baseURL: baseURL, fileManager: fileManager))
    }

    func testDeleteDownloadedModelFilesRemovesOnlySelectedDirectory() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("WhisperServiceTests.Delete.\(UUID().uuidString)", isDirectory: true)
        let baseDirectory = WhisperService.downloadedModelDirectory(for: .baseEN, baseURL: baseURL)
        let smallDirectory = WhisperService.downloadedModelDirectory(for: .smallEN, baseURL: baseURL)

        for directory in [baseDirectory, smallDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try createCompleteModelArtifacts(in: directory, fileManager: fileManager)
        }

        try WhisperService.deleteDownloadedModelFiles(for: .baseEN, baseURL: baseURL, fileManager: fileManager)

        XCTAssertFalse(fileManager.fileExists(atPath: baseDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: smallDirectory.path))
    }

    func testDeleteLegacyUnsupportedModelFilesRemovesLargeTurboDirectoryAndCacheOnly() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("WhisperServiceTests.LegacyCleanup.\(UUID().uuidString)", isDirectory: true)
        let supportedDirectory = WhisperService.downloadedModelDirectory(for: .baseEN, baseURL: baseURL)
        let legacyDirectory = WhisperService.downloadedModelDirectory(
            forModelIdentifier: WhisperModelChoice.legacyLargeTurboRawValue,
            baseURL: baseURL
        )
        let legacyCacheDirectory = WhisperService.downloadedModelCacheDirectory(
            forModelIdentifier: WhisperModelChoice.legacyLargeTurboRawValue,
            baseURL: baseURL
        )

        try fileManager.createDirectory(at: supportedDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: legacyCacheDirectory, withIntermediateDirectories: true)

        try WhisperService.deleteLegacyUnsupportedModelFiles(baseURL: baseURL, fileManager: fileManager)

        XCTAssertTrue(fileManager.fileExists(atPath: supportedDirectory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyDirectory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyCacheDirectory.path))
    }

    func testDeleteIncompleteDownloadedModelFilesIfNeededRemovesInvalidDirectory() throws {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("WhisperServiceTests.PruneIncomplete.\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = WhisperService.downloadedModelDirectory(for: .smallEN, baseURL: baseURL)
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try createCompleteModelArtifacts(in: modelDirectory, fileManager: fileManager)
        try fileManager.removeItem(
            at: modelDirectory
                .appendingPathComponent("TextDecoder.mlmodelc", isDirectory: true)
                .appendingPathComponent("metadata.json", isDirectory: false)
        )

        try WhisperService.deleteIncompleteDownloadedModelFilesIfNeeded(
            for: .smallEN,
            baseURL: baseURL,
            fileManager: fileManager
        )

        XCTAssertFalse(fileManager.fileExists(atPath: modelDirectory.path))
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

    private func createCompleteModelArtifacts(in modelDirectory: URL, fileManager: FileManager) throws {
        for artifact in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            let artifactDirectory = modelDirectory.appendingPathComponent(artifact, isDirectory: true)
            try fileManager.createDirectory(
                at: artifactDirectory.appendingPathComponent("weights", isDirectory: true),
                withIntermediateDirectories: true
            )
            for file in ["coremldata.bin", "metadata.json", "model.mil"] {
                let fileURL = artifactDirectory.appendingPathComponent(file, isDirectory: false)
                XCTAssertTrue(fileManager.createFile(atPath: fileURL.path, contents: Data([0x0])))
            }
            let weightURL = artifactDirectory
                .appendingPathComponent("weights", isDirectory: true)
                .appendingPathComponent("weight.bin", isDirectory: false)
            XCTAssertTrue(fileManager.createFile(atPath: weightURL.path, contents: Data([0x0])))
        }
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
