import XCTest
@testable import Speech2Test

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

    func testWhisperServiceThrowsNoModelBeforeLoadingModel() async throws {
        let service = WhisperService()
        do {
            _ = try await service.transcribe(samples: [0.1, 0.2])
            XCTFail("Expected noModel to be thrown")
        } catch TranscriptionError.noModel {
            // expected
        }
    }

    func testWhisperServiceThrowsModelLoadFailedForInvalidPath() async throws {
        let service = WhisperService()
        do {
            try await service.loadModel(at: "/nonexistent/path/model.bin")
            XCTFail("Expected modelLoadFailed to be thrown")
        } catch TranscriptionError.modelLoadFailed {
            // expected
        }
    }
}
