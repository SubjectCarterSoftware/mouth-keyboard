import XCTest
@testable import Speech2Test

@MainActor
final class LongDictationFlowTests: XCTestCase {
    func testLongDictationSettlesMultipleSegmentsBeforePublishingSingleResult() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let buffer = SealingBufferAccumulator()
        let store = makeStore(
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 300_000_000, result: .success("alpha")),
                    2.0: .init(delayNanoseconds: 50_000_000, result: .success("beta")),
                    3.0: .init(delayNanoseconds: 150_000_000, result: .success("gamma"))
                ]
            ),
            clipboard: clipboard,
            bufferAccumulator: buffer
        )

        recordThreeSegmentLongSession(on: store)
        XCTAssertEqual(clipboard.writeCount, 0)

        store.finish()
        XCTAssertEqual(store.state, .processing)

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(clipboard.writeCount, 0)

        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(clipboard.writeCount, 1)
        XCTAssertEqual(clipboard.lastWrittenText, "alpha beta gamma")
        XCTAssertEqual(buffer.sealCalls.map(\.reason), [.pause, .softCap, .finish])
        XCTAssertNil(store.resultNotice)
        if case .success(let text) = store.state {
            XCTAssertEqual(text, "alpha beta gamma")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testOutOfOrderSegmentCompletionStillPublishesSpokenOrder() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 350_000_000, result: .success("first")),
                    2.0: .init(delayNanoseconds: 10_000_000, result: .success("second")),
                    3.0: .init(delayNanoseconds: 150_000_000, result: .success("third"))
                ]
            ),
            clipboard: clipboard,
            bufferAccumulator: SealingBufferAccumulator()
        )

        recordThreeSegmentLongSession(on: store)
        store.finish()

        try await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(clipboard.lastWrittenText, "first second third")
        if case .success(let text) = store.state {
            XCTAssertEqual(text, "first second third")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testContinuousSpeechSoftCapPreservesEarlierAudio() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let buffer = SealingBufferAccumulator()
        let store = makeStore(
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 0, result: .success("early")),
                    2.0: .init(delayNanoseconds: 0, result: .success("late"))
                ]
            ),
            clipboard: clipboard,
            bufferAccumulator: buffer
        )

        store.arm()
        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .softCap))

        store.finish()
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(buffer.sealCalls.map(\.reason), [.softCap, .finish])
        XCTAssertEqual(clipboard.lastWrittenText, "early late")
        if case .success(let text) = store.state {
            XCTAssertEqual(text, "early late")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testInjectedSegmentFailureStillPublishesBestEffortClipboardAndWarning() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 0, result: .success("kept")),
                    2.0: .init(delayNanoseconds: 0, result: .success("should not appear")),
                    3.0: .init(delayNanoseconds: 0, result: .success("tail"))
                ]
            ),
            clipboard: clipboard,
            bufferAccumulator: SealingBufferAccumulator()
        )
        store.configureUITestingLongSessionFailure(segmentIndex: 1)

        recordThreeSegmentLongSession(on: store)
        store.finish()

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(clipboard.writeCount, 1)
        XCTAssertEqual(clipboard.lastWrittenText, "kept tail")
        XCTAssertEqual(
            store.resultNotice,
            LongSessionResultNotice(failedSegmentCount: 1, successfulSegmentCount: 2)
        )
        if case .success(let text) = store.state {
            XCTAssertEqual(text, "kept tail")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testAllFailureLongSessionsDoNotWriteClipboard() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 0, result: .failure(TranscriptionError.noSpeechDetected)),
                    2.0: .init(delayNanoseconds: 0, result: .failure(TranscriptionError.inferenceFailed)),
                    3.0: .init(delayNanoseconds: 0, result: .failure(TranscriptionError.noSpeechDetected))
                ]
            ),
            clipboard: clipboard,
            bufferAccumulator: SealingBufferAccumulator()
        )

        recordThreeSegmentLongSession(on: store)
        store.finish()

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(clipboard.writeCount, 0)
        XCTAssertNil(store.resultNotice)
        XCTAssertEqual(store.longSessionStatus, .inactive)
        XCTAssertTrue(store.queuedSegments.isEmpty)
        if case .failure = store.state {
            return
        }

        XCTFail("Expected .failure state, got \(store.state)")
    }

    func testShortSessionsBelowThresholdUseExistingNonSegmentedPath() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let buffer = SealingBufferAccumulator()
        let store = makeStore(
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    0.0: .init(delayNanoseconds: 0, result: .success("short path"))
                ]
            ),
            clipboard: clipboard,
            bufferAccumulator: buffer
        )

        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(store.queuedSegments.isEmpty)
        XCTAssertEqual(store.longSessionStatus, .inactive)
        XCTAssertTrue(buffer.sealCalls.isEmpty)
        XCTAssertEqual(clipboard.writeCount, 1)
        XCTAssertEqual(clipboard.lastWrittenText, "short path")
        if case .success(let text) = store.state {
            XCTAssertEqual(text, "short path")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    private func recordThreeSegmentLongSession(on store: ActivationStore) {
        store.arm()
        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))
        store.handleLongDictationBoundary(.segmentBoundary(reason: .softCap))
    }

    private func makeStore(
        transcriber: any WhisperTranscribing,
        clipboard: ClipboardService,
        bufferAccumulator: AudioBufferAccumulator
    ) -> ActivationStore {
        let suiteName = "LongDictationFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        return ActivationStore(
            preferences: ShellPreferences(userDefaults: defaults),
            readinessProvider: LongDictationFlowReadinessProvider(),
            whisperService: transcriber,
            clipboardService: clipboard,
            bufferAccumulator: bufferAccumulator
        )
    }
}

@MainActor
private struct LongDictationFlowReadinessProvider: ReadinessProviding {
    var snapshot: ReadinessSnapshot {
        let permissions = PermissionKind.allCases.map {
            PermissionChecklistItem(kind: $0, status: .authorized, message: "")
        }

        return ReadinessSnapshot(
            state: .ready,
            title: "",
            message: "",
            primaryActionTitle: "",
            permissions: permissions
        )
    }
}
