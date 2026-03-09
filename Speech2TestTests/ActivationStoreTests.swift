import XCTest
@testable import Speech2Test

@MainActor
final class ActivationStoreTests: XCTestCase {
    func testInitialStateIsIdle() {
        let store = makeStore(permissionsAuthorized: true)

        XCTAssertEqual(store.state, .idle)
    }

    func testArmTransitionsToRecordingSynchronouslyWhenReady() {
        let store = makeStore(permissionsAuthorized: true)

        store.arm()

        XCTAssertEqual(store.state, .recording)
    }

    func testStopTransitionsToIdle() {
        let store = makeStore(permissionsAuthorized: true)
        store.arm()

        store.stop()

        XCTAssertEqual(store.state, .idle)
    }

    // arm() is blocked when permissions are not yet authorized — readiness
    // state alone is not the gate; the individual permission items are checked.
    func testArmDoesNotTransitionWhenPermissionsNotAuthorized() {
        let store = makeStore(permissionsAuthorized: false)

        store.arm()

        XCTAssertEqual(store.state, .idle)
    }

    // arm() succeeds when all permissions are authorized, even if the user has
    // not yet pressed "Finish Setup" (hasCompletedInitialSetup == false).
    // The setup-finalize step is an onboarding UX gate, not a runtime gate.
    func testArmSucceedsWhenPermissionsAuthorizedRegardlessOfSetupCompletion() {
        let store = makeStore(permissionsAuthorized: true)

        store.arm()

        XCTAssertEqual(store.state, .recording)
    }

    // MARK: - finish() tests

    func test_finish_transitions_to_processing() {
        let store = makeStore(permissionsAuthorized: true)
        store.arm()
        XCTAssertEqual(store.state, .recording)

        store.finish()

        XCTAssertEqual(store.state, .processing)
    }

    func test_finish_no_op_when_not_recording() {
        let store = makeStore(permissionsAuthorized: true)
        // state is .idle
        store.finish()

        XCTAssertEqual(store.state, .idle)
    }

    func test_finish_succeeds_writes_clipboard() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success("Hello world"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        // Wait for async transcription
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mockClipboard.lastWrittenText, "Hello world")
        if case .success(let text) = store.state {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testCancelDuringRecordingReturnsToIdleWithoutClipboardWrite() {
        let mockClipboard = ActivationStoreMockClipboard()
        let buffer = SealingBufferAccumulator()
        let store = makeStore(
            permissionsAuthorized: true,
            clipboard: mockClipboard,
            bufferAccumulator: buffer
        )
        store.arm()
        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))

        store.cancelCurrentSession()

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.recoveryFeedback, .canceled)
        XCTAssertNil(mockClipboard.lastWrittenText)
        XCTAssertTrue(store.queuedSegments.isEmpty)
        XCTAssertEqual(store.longSessionStatus, .inactive)
    }

    func testCancelDuringProcessingSuppressesLateSuccessPublication() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: DelayedWhisperTranscriber(delayNanoseconds: 300_000_000, result: .success("late result")),
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        XCTAssertEqual(store.state, .processing)

        store.cancelCurrentSession()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.recoveryFeedback, .canceled)
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testRestartKeepsRecordingResetsBufferAndClearsFeedback() async throws {
        let buffer = SealingBufferAccumulator()
        let resetTracker = ResetHookTracker()
        let store = makeStore(
            permissionsAuthorized: true,
            bufferAccumulator: buffer,
            resetSessionMonitoring: { resetTracker.callCount += 1 }
        )
        store.arm()
        XCTAssertEqual(buffer.resetCount, 1)
        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))
        XCTAssertEqual(store.queuedSegments.count, 1)

        store.restartCurrentSession()

        XCTAssertEqual(store.state, .recording)
        XCTAssertEqual(store.recoveryFeedback, .restarted)
        XCTAssertEqual(buffer.resetCount, 2)
        XCTAssertEqual(resetTracker.callCount, 1)
        XCTAssertTrue(store.queuedSegments.isEmpty)
        XCTAssertEqual(store.longSessionStatus, .inactive)

        try await Task.sleep(nanoseconds: 1_700_000_000)

        XCTAssertNil(store.recoveryFeedback)
        XCTAssertEqual(store.state, .recording)
    }

    func testRestartLeavesClipboardUntouched() {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            clipboard: mockClipboard
        )
        store.arm()

        store.restartCurrentSession()

        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testSessionsUnderThresholdDoNotSealSegments() {
        let buffer = SealingBufferAccumulator()
        let store = makeStore(
            permissionsAuthorized: true,
            bufferAccumulator: buffer
        )
        store.arm()

        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))

        XCTAssertEqual(store.state, .recording)
        XCTAssertTrue(store.queuedSegments.isEmpty)
        XCTAssertTrue(buffer.sealCalls.isEmpty)
        XCTAssertEqual(store.longSessionStatus, .inactive)
    }

    func testLongSessionsSealSegmentOnPauseAfterThresholdActivation() {
        let buffer = SealingBufferAccumulator()
        let store = makeStore(
            permissionsAuthorized: true,
            bufferAccumulator: buffer
        )
        store.arm()

        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))

        XCTAssertEqual(store.state, .recording)
        XCTAssertEqual(buffer.sealCalls.map(\.index), [0])
        XCTAssertEqual(buffer.sealCalls.map(\.reason), [.pause])
        XCTAssertEqual(store.queuedSegments.map(\.index), [0])
        XCTAssertEqual(store.queuedSegments.map(\.sealReason), [.pause])
        XCTAssertEqual(store.longSessionStatus.phase, .recordingSegmented)
        XCTAssertEqual(store.longSessionStatus.nextSegmentIndex, 1)
        XCTAssertEqual(store.longSessionStatus.queuedSegmentCount, 1)
    }

    func testLongSessionsSealSegmentOnSoftCapAfterThresholdActivation() {
        let buffer = SealingBufferAccumulator()
        let store = makeStore(
            permissionsAuthorized: true,
            bufferAccumulator: buffer
        )
        store.arm()

        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .softCap))

        XCTAssertEqual(store.state, .recording)
        XCTAssertEqual(buffer.sealCalls.map(\.index), [0])
        XCTAssertEqual(buffer.sealCalls.map(\.reason), [.softCap])
        XCTAssertEqual(store.queuedSegments.map(\.sealReason), [.softCap])
        XCTAssertEqual(store.longSessionStatus.phase, .recordingSegmented)
    }

    func testLongSessionWritesClipboardOnceAtFinalization() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 250_000_000, result: .success("first")),
                    2.0: .init(delayNanoseconds: 50_000_000, result: .success("second"))
                ]
            ),
            clipboard: mockClipboard,
            bufferAccumulator: SealingBufferAccumulator()
        )
        store.arm()
        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))

        store.finish()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(mockClipboard.writeCount, 1)
        XCTAssertEqual(mockClipboard.lastWrittenText, "first second")
        XCTAssertEqual(store.longSessionStatus, .inactive)
        XCTAssertNil(store.resultNotice)
        if case .success(let text) = store.state {
            XCTAssertEqual(text, "first second")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testLongSessionPartialFailureStillSucceedsWithWarningCount() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 0, result: .success("hello")),
                    2.0: .init(delayNanoseconds: 0, result: .failure(TranscriptionError.inferenceFailed))
                ]
            ),
            clipboard: mockClipboard,
            bufferAccumulator: SealingBufferAccumulator()
        )
        store.arm()
        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))

        store.finish()
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(mockClipboard.writeCount, 1)
        XCTAssertEqual(mockClipboard.lastWrittenText, "hello")
        XCTAssertEqual(
            store.resultNotice,
            LongSessionResultNotice(failedSegmentCount: 1, successfulSegmentCount: 1)
        )
        if case .success(let text) = store.state {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }
    }

    func testAllFailureLongSessionsDoNotWriteClipboard() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 0, result: .failure(TranscriptionError.noSpeechDetected)),
                    2.0: .init(delayNanoseconds: 0, result: .failure(TranscriptionError.inferenceFailed))
                ]
            ),
            clipboard: mockClipboard,
            bufferAccumulator: SealingBufferAccumulator()
        )
        store.arm()
        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))

        store.finish()
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(mockClipboard.writeCount, 0)
        XCTAssertNil(store.resultNotice)
        if case .failure = store.state {
            // pass
        } else {
            XCTFail("Expected .failure state, got \(store.state)")
        }
    }

    func testStaleLongSessionCompletionsAfterCancelAreIgnored() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 300_000_000, result: .success("late segment"))
                ]
            ),
            clipboard: mockClipboard,
            bufferAccumulator: SealingBufferAccumulator()
        )
        store.arm()
        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))

        store.cancelCurrentSession()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.recoveryFeedback, .canceled)
        XCTAssertEqual(mockClipboard.writeCount, 0)
        XCTAssertNil(store.resultNotice)
        XCTAssertTrue(store.queuedSegments.isEmpty)
        XCTAssertEqual(store.longSessionStatus, .inactive)
    }

    func testSegmentSealingKeepsStoreInRecordingState() {
        let buffer = SealingBufferAccumulator()
        let store = makeStore(
            permissionsAuthorized: true,
            bufferAccumulator: buffer
        )
        store.arm()

        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))

        XCTAssertEqual(store.state, .recording)
    }

    func testEmptyOrWhitespaceOnlyTranscriptionDoesNotReachClipboard() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: ActivationStoreMockTranscriber(result: .success("   \n  ")),
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.state, .failure(reason: .noSpeechDetected))
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testHandleCaptureFailureMapsPermissionDeniedAndAvoidsClipboardWrite() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            clipboard: mockClipboard
        )
        store.arm()

        store.handleCaptureFailure(.microphonePermissionDenied)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state, .failure(reason: .microphonePermissionDenied))
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func testHandleCaptureFailureDuringProcessingSuppressesLateClipboardWrite() async throws {
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: DelayedWhisperTranscriber(delayNanoseconds: 300_000_000, result: .success("late result")),
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()
        XCTAssertEqual(store.state, .processing)

        store.handleCaptureFailure(.selectedInputDisconnected)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(store.state, .failure(reason: .selectedMicrophoneDisconnected))
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func test_finish_fails_no_speech() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .failure(TranscriptionError.noSpeechDetected))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.state, .failure(reason: .noSpeechDetected))
        XCTAssertNil(mockClipboard.lastWrittenText)
    }

    func test_arm_while_recording_calls_finish() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success("toggled"))
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: ActivationStoreMockClipboard()
        )
        store.arm() // -> .recording
        XCTAssertEqual(store.state, .recording)

        store.arm() // second arm while recording should call finish()

        XCTAssertEqual(store.state, .processing)
    }

    func test_arm_while_processing_is_ignored() async throws {
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: DelayedWhisperTranscriber(delayNanoseconds: 500_000_000)
        )
        store.arm()
        store.finish()
        XCTAssertEqual(store.state, .processing)

        store.arm()

        XCTAssertEqual(store.state, .processing)
    }

    func test_arm_after_longSessionSuccess_restartsImmediatelyWithoutWaitingForAutoDismiss() async throws {
        let clipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: SampleMappingWhisperTranscriber(
                responses: [
                    1.0: .init(delayNanoseconds: 0, result: .success("first")),
                    2.0: .init(delayNanoseconds: 0, result: .success("second"))
                ]
            ),
            clipboard: clipboard,
            bufferAccumulator: SealingBufferAccumulator()
        )

        store.arm()
        store.handleLongDictationBoundary(.thresholdReached)
        store.handleLongDictationBoundary(.segmentBoundary(reason: .pause))
        store.finish()

        try await Task.sleep(nanoseconds: 250_000_000)

        if case .success(let text) = store.state {
            XCTAssertEqual(text, "first second")
        } else {
            XCTFail("Expected .success state, got \(store.state)")
        }

        store.arm()

        XCTAssertEqual(store.state, .recording)
        XCTAssertNil(store.resultNotice)
        XCTAssertEqual(store.longSessionStatus, .inactive)
        XCTAssertEqual(clipboard.writeCount, 1)
    }

    func test_failure_does_not_write_clipboard() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .failure(TranscriptionError.inferenceFailed))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: mockClipboard
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(mockClipboard.lastWrittenText)
        if case .failure = store.state {
            // pass
        } else {
            XCTFail("Expected .failure state, got \(store.state)")
        }
    }

    // MARK: - Helpers

    private func makeStore(
        permissionsAuthorized: Bool,
        transcriber: (any WhisperTranscribing)? = nil,
        clipboard: ClipboardService? = nil,
        bufferAccumulator: AudioBufferAccumulator? = nil,
        resetSessionMonitoring: (@MainActor () -> Void)? = nil
    ) -> ActivationStore {
        let suiteName = "ActivationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        return ActivationStore(
            preferences: ShellPreferences(userDefaults: defaults),
            readinessProvider: StubReadinessProvider(permissionsAuthorized: permissionsAuthorized),
            whisperService: transcriber ?? ActivationStoreMockTranscriber(result: .success("")),
            clipboardService: clipboard ?? ActivationStoreMockClipboard(),
            bufferAccumulator: bufferAccumulator ?? StubBufferAccumulator(),
            resetSessionMonitoring: resetSessionMonitoring ?? {}
        )
    }
}

// MARK: - Stubs / Mocks

@MainActor
private struct StubReadinessProvider: ReadinessProviding {
    let permissionsAuthorized: Bool

    var snapshot: ReadinessSnapshot {
        let status: PermissionGrantState = permissionsAuthorized ? .authorized : .denied
        let permissions = PermissionKind.allCases.map {
            PermissionChecklistItem(kind: $0, status: status, message: "")
        }
        // state is derived from permission statuses; supply a plausible value.
        let state: ReadinessState = permissionsAuthorized ? .ready : .blocked
        return ReadinessSnapshot(
            state: state,
            title: "",
            message: "",
            primaryActionTitle: "",
            permissions: permissions
        )
    }
}

/// Mock transcriber scoped to ActivationStoreTests to avoid conflict with WhisperServiceTests.MockWhisperTranscriber
final class ActivationStoreMockTranscriber: WhisperTranscribing, @unchecked Sendable {
    enum MockResult {
        case success(String)
        case failure(Error)
    }

    private let result: MockResult

    init(result: MockResult) {
        self.result = result
    }

    func transcribe(samples: [Float]) async throws -> String {
        switch result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

final class DelayedWhisperTranscriber: WhisperTranscribing, @unchecked Sendable {
    private let delayNanoseconds: UInt64
    private let result: ActivationStoreMockTranscriber.MockResult

    init(delayNanoseconds: UInt64, result: ActivationStoreMockTranscriber.MockResult = .success("delayed")) {
        self.delayNanoseconds = delayNanoseconds
        self.result = result
    }

    func transcribe(samples: [Float]) async throws -> String {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        switch result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

/// Mock clipboard service — subclasses ClipboardService (must be non-final) for test interception
class ActivationStoreMockClipboard: ClipboardService {
    private(set) var lastWrittenText: String?
    private(set) var writeCount = 0

    init() {
        // Use a named pasteboard to avoid polluting the general pasteboard
        let pb = NSPasteboard(name: NSPasteboard.Name("ActivationStoreMockClipboard.\(UUID().uuidString)"))
        super.init(pasteboard: pb)
    }

    @discardableResult
    override func writeToClipboard(_ text: String) -> Bool {
        writeCount += 1
        lastWrittenText = text
        return true
    }
}

/// Stub accumulator returns minimal samples to satisfy the transcription pipeline
class StubBufferAccumulator: AudioBufferAccumulator {
    override func convertToWhisperFormat() throws -> [Float] {
        return [0.0, 0.0, 0.0] // non-empty, won't throw emptyBuffers
    }
}

class TrackingBufferAccumulator: StubBufferAccumulator {
    private(set) var resetCount = 0

    override func reset() {
        resetCount += 1
        super.reset()
    }
}

final class SealingBufferAccumulator: TrackingBufferAccumulator {
    private(set) var sealCalls: [(index: Int, reason: SegmentSealReason)] = []

    override func sealSegment(index: Int, reason: SegmentSealReason) throws -> QueuedSegment {
        sealCalls.append((index, reason))
        return QueuedSegment(
            index: index,
            sealReason: reason,
            audio: SealedAudioSegment(
                samples: [Float(index + 1)],
                sourceFrameCount: 1,
                sourceSampleRate: SealedAudioSegment.whisperSampleRate
            )
        )
    }
}

final class SampleMappingWhisperTranscriber: WhisperTranscribing, @unchecked Sendable {
    struct Response {
        let delayNanoseconds: UInt64
        let result: ActivationStoreMockTranscriber.MockResult
    }

    private let responses: [Float: Response]

    init(responses: [Float: Response]) {
        self.responses = responses
    }

    func transcribe(samples: [Float]) async throws -> String {
        let sampleKey = samples.first ?? .zero
        guard let response = responses[sampleKey] else {
            throw TranscriptionError.inferenceFailed
        }

        if response.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: response.delayNanoseconds)
        }

        switch response.result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

final class ResetHookTracker {
    var callCount = 0
}
