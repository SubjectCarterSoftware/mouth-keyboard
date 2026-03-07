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

    func test_auto_paste_enabled() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success("paste me"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: mockClipboard,
            autoPasteEnabled: true
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(mockClipboard.autoPasteCalled)
    }

    func test_auto_paste_disabled() async throws {
        let mockTranscriber = ActivationStoreMockTranscriber(result: .success("no paste"))
        let mockClipboard = ActivationStoreMockClipboard()
        let store = makeStore(
            permissionsAuthorized: true,
            transcriber: mockTranscriber,
            clipboard: mockClipboard,
            autoPasteEnabled: false
        )
        store.arm()
        store.finish()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(mockClipboard.autoPasteCalled)
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
        autoPasteEnabled: Bool = true
    ) -> ActivationStore {
        let suiteName = "ActivationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(autoPasteEnabled, forKey: ShellPreferences.Keys.autoPasteEnabled)

        return ActivationStore(
            preferences: ShellPreferences(userDefaults: defaults),
            readinessProvider: StubReadinessProvider(permissionsAuthorized: permissionsAuthorized),
            whisperService: transcriber ?? ActivationStoreMockTranscriber(result: .success("")),
            clipboardService: clipboard ?? ActivationStoreMockClipboard(),
            bufferAccumulator: StubBufferAccumulator()
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

/// Mock clipboard service — subclasses ClipboardService (must be non-final) for test interception
class ActivationStoreMockClipboard: ClipboardService {
    private(set) var lastWrittenText: String?
    private(set) var autoPasteCalled: Bool = false

    init() {
        // Use a named pasteboard to avoid polluting the general pasteboard
        let pb = NSPasteboard(name: NSPasteboard.Name("ActivationStoreMockClipboard.\(UUID().uuidString)"))
        super.init(pasteboard: pb ?? .general)
    }

    @discardableResult
    override func writeToClipboard(_ text: String) -> Bool {
        lastWrittenText = text
        return true
    }

    override func autoPaste() {
        autoPasteCalled = true
    }
}

/// Stub accumulator returns minimal samples to satisfy the transcription pipeline
class StubBufferAccumulator: AudioBufferAccumulator {
    override func convertToWhisperFormat() throws -> [Float] {
        return [0.0, 0.0, 0.0] // non-empty, won't throw emptyBuffers
    }
}
