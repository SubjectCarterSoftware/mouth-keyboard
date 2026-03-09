import AppKit
import Combine
import Foundation

// MARK: - ActivationSoundPlayer

struct ActivationSoundPlayer {
    func play() {
        if let sound = NSSound(named: "Tink") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}

// MARK: - ReadinessProviding

@MainActor
protocol ReadinessProviding {
    var snapshot: ReadinessSnapshot { get }
}

extension ReadinessStore: ReadinessProviding {}

// MARK: - ActivationStore

@MainActor
final class ActivationStore: ObservableObject {
    static let shared = ActivationStore(
        preferences: .shared,
        readinessProvider: ReadinessStore.shared,
        whisperService: WhisperService.shared,
        clipboardService: ClipboardService(),
        bufferAccumulator: AudioBufferAccumulator()
    )

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var recoveryFeedback: RecordingState.RecoveryFeedback?
    @Published private(set) var longSessionStatus: LongSessionStatus = .inactive
    @Published private(set) var resultNotice: LongSessionResultNotice?

    private let preferences: ShellPreferences
    private let readinessProvider: any ReadinessProviding
    private let whisperService: any WhisperTranscribing
    private let clipboardService: ClipboardService
    private let resetSessionMonitoring: @MainActor () -> Void
    let bufferAccumulator: AudioBufferAccumulator
    private(set) var queuedSegments: [QueuedSegment] = []
    var soundPlayer: ActivationSoundPlayer = .init()
    private var uiTestingLongSessionFailureSegmentIndex: Int?
    private var activeSessionID = UUID()
    private var transcriptionTask: Task<Void, Never>?
    private var queuedSegmentTasks: [Int: Task<Void, Never>] = [:]
    private var dismissTask: Task<Void, Never>?
    private var feedbackClearTask: Task<Void, Never>?
    private var nextQueuedSegmentIndex = 0

    convenience init(preferences: ShellPreferences, readinessStore: ReadinessStore) {
        self.init(
            preferences: preferences,
            readinessProvider: readinessStore,
            whisperService: WhisperService(),
            clipboardService: ClipboardService(),
            bufferAccumulator: AudioBufferAccumulator(),
            resetSessionMonitoring: {}
        )
    }

    init(
        preferences: ShellPreferences,
        readinessProvider: any ReadinessProviding,
        whisperService: any WhisperTranscribing = WhisperService(),
        clipboardService: ClipboardService = ClipboardService(),
        bufferAccumulator: AudioBufferAccumulator = AudioBufferAccumulator(),
        resetSessionMonitoring: @escaping @MainActor () -> Void = {}
    ) {
        self.preferences = preferences
        self.readinessProvider = readinessProvider
        self.whisperService = whisperService
        self.clipboardService = clipboardService
        self.bufferAccumulator = bufferAccumulator
        self.resetSessionMonitoring = resetSessionMonitoring
    }

    // MARK: - Public API

    func arm() {
        // Toggle: if already recording, finish (trigger transcription flow).
        if state == .recording {
            finish()
            return
        }

        // Ignore activation while transcription is in flight, but allow a new
        // recording to interrupt terminal feedback instead of waiting for the
        // auto-dismiss timer to return to idle.
        guard state == .idle || state.isTerminal else {
            return
        }

        // Require all permissions to be granted, but do NOT require setup to be
        // "finalized" (hasCompletedInitialSetup). The finalize step is an
        // onboarding UX gate, not a runtime safety requirement. Recording must
        // work as soon as microphone and keyboard-monitoring permissions are
        // authorized, even if the user dismissed the setup window early.
        let snapshot = readinessProvider.snapshot
        guard snapshot.permissions.allSatisfy(\.isAuthorized) else {
            return
        }

        if preferences.activationSoundEnabled {
            soundPlayer.play()
        }

        invalidateScheduledWork()
        recoveryFeedback = nil
        activeSessionID = UUID()
        bufferAccumulator.reset()
        resetLongSessionState()
        state = .recording
    }

    /// Hard stop — transitions directly to idle without transcribing. Used for cancel (Phase 4).
    func stop() {
        cancelCurrentSession()
    }

    func cancelCurrentSession() {
        guard state == .recording || state == .processing else { return }

        invalidateActiveSession()
        bufferAccumulator.reset()
        resetLongSessionState()
        publishRecoveryFeedback(.canceled)
        state = .idle
    }

    func restartCurrentSession() {
        guard state == .recording else { return }

        invalidateActiveSession()
        bufferAccumulator.reset()
        resetLongSessionState()
        resetSessionMonitoring()
        publishRecoveryFeedback(.restarted)
        state = .recording
    }

    /// Finish recording: stops capture and runs the transcription -> clipboard -> dismiss flow.
    func finish() {
        guard state == .recording else { return }
        invalidateScheduledWork()
        recoveryFeedback = nil
        let sessionID = activeSessionID
        if shouldFinalizeLongDictation {
            refreshLongSessionStatus(phase: .finalizing)
        }
        state = .processing
        let task = Task { [weak self] in
            guard let self else { return }
            // Let state observers stop audio capture before we snapshot and
            // convert the accumulated buffers for Whisper.
            await Task.yield()
            await self.finalizeSession(sessionID: sessionID)
        }
        transcriptionTask = task
    }

    /// Called by AudioLevelMonitor's onSilenceTimeout callback.
    /// Attempts transcription of whatever audio was captured during the session.
    func handleSilenceTimeout() {
        // Per plan decision: still attempt transcription on whatever audio was captured.
        finish()
    }

    func handleCaptureFailure(_ error: AudioCaptureError) {
        invalidateActiveSession()
        bufferAccumulator.reset()
        resetLongSessionState()
        recoveryFeedback = nil

        let failureSessionID = activeSessionID
        state = .failure(reason: failureReason(for: error))
        scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: failureSessionID)
    }

    func handleLongDictationBoundary(_ event: LongDictationBoundaryEvent) {
        guard state == .recording else { return }

        switch event {
        case .thresholdReached:
            activateLongDictationIfNeeded()
        case .segmentBoundary(let reason):
            guard longSessionStatus.phase != .inactive else { return }
            sealAndQueueCurrentSegment(reason: reason, phase: .recordingSegmented, sessionID: activeSessionID)
        }
    }

    func configureUITestingLongSessionFailure(segmentIndex: Int?) {
        uiTestingLongSessionFailureSegmentIndex = segmentIndex
    }

    // MARK: - Private transcription flow

    private var shouldFinalizeLongDictation: Bool {
        longSessionStatus.phase != .inactive || !queuedSegments.isEmpty
    }

    private func finalizeSession(sessionID: UUID) async {
        do {
            guard isCurrentSession(sessionID) else { return }
            resultNotice = nil

            if shouldFinalizeLongDictation {
                try await finalizeLongDictation(sessionID: sessionID)
            } else {
                try await transcribeSingleSession(sessionID: sessionID)
            }
        } catch TranscriptionError.noSpeechDetected {
            guard isCurrentSession(sessionID) else { return }
            resultNotice = nil
            state = .failure(reason: .noSpeechDetected)
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        } catch {
            guard isCurrentSession(sessionID) else { return }
            resultNotice = nil
            state = .failure(reason: .modelError(error.localizedDescription))
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        }

        if sessionID == activeSessionID {
            transcriptionTask = nil
        }
    }

    private func invalidateActiveSession() {
        activeSessionID = UUID()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        for task in queuedSegmentTasks.values {
            task.cancel()
        }
        queuedSegmentTasks.removeAll()
        invalidateScheduledWork()
    }

    private func invalidateScheduledWork() {
        dismissTask?.cancel()
        dismissTask = nil
        feedbackClearTask?.cancel()
        feedbackClearTask = nil
    }

    private func activateLongDictationIfNeeded() {
        guard longSessionStatus.phase == .inactive else { return }
        refreshLongSessionStatus(phase: .recordingSegmented)
    }

    private func resetLongSessionState() {
        queuedSegments.removeAll()
        queuedSegmentTasks.removeAll()
        nextQueuedSegmentIndex = 0
        longSessionStatus = .inactive
        resultNotice = nil
    }

    private func refreshLongSessionStatus(phase: LongSessionStatus.Phase) {
        longSessionStatus = LongSessionStatus(
            phase: phase,
            nextSegmentIndex: nextQueuedSegmentIndex,
            queuedSegmentCount: queuedSegments.count,
            completedSegmentCount: queuedSegments.reduce(into: 0) { count, segment in
                if case .completed = segment.transcriptionState {
                    count += 1
                }
            },
            failedSegmentCount: queuedSegments.reduce(into: 0) { count, segment in
                if case .failed = segment.transcriptionState {
                    count += 1
                }
            }
        )
    }

    private func publishRecoveryFeedback(_ feedback: RecordingState.RecoveryFeedback) {
        feedbackClearTask?.cancel()
        recoveryFeedback = feedback
        feedbackClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.recoveryFeedback = nil
            self.feedbackClearTask = nil
        }
    }

    private func scheduleDismissToIdle(afterNanoseconds duration: UInt64, sessionID: UUID) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: duration)
            guard let self, self.isCurrentSession(sessionID) else { return }
            switch self.state {
            case .success, .failure:
                self.state = .idle
            case .idle, .recording, .processing:
                break
            }
            self.dismissTask = nil
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        !Task.isCancelled && sessionID == activeSessionID
    }

    private func prepareWhisperModelIfNeeded() async throws {
        if let whisperService = whisperService as? WhisperService,
           let modelPath = Bundle.main.path(forResource: "ggml-small.en", ofType: "bin") {
            try await whisperService.ensureModelLoaded(at: modelPath)
        }
    }

    private func transcribeSingleSession(sessionID: UUID) async throws {
        try await prepareWhisperModelIfNeeded()
        guard isCurrentSession(sessionID) else { return }

        let samples = try bufferAccumulator.convertToWhisperFormat()
        let text = try await whisperService.transcribe(samples: samples)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isCurrentSession(sessionID) else { return }
        guard !trimmed.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }

        state = .success(text: trimmed)
        clipboardService.writeToClipboard(trimmed)
        scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
    }

    private func finalizeLongDictation(sessionID: UUID) async throws {
        sealAndQueueCurrentSegment(reason: .finish, phase: .finalizing, sessionID: sessionID)
        await settleQueuedSegmentWork(sessionID: sessionID)
        guard isCurrentSession(sessionID) else { return }

        let assembledTranscript = LongDictationAssembler.assemble(queuedSegments)
        let failureReason = failureReasonForQueuedSegments()
        queuedSegments.removeAll()
        queuedSegmentTasks.removeAll()
        nextQueuedSegmentIndex = 0
        longSessionStatus = .inactive

        guard let assembledTranscript else {
            resultNotice = nil
            throw failureReason
        }

        if assembledTranscript.failedSegmentCount > 0 {
            resultNotice = LongSessionResultNotice(
                failedSegmentCount: assembledTranscript.failedSegmentCount,
                successfulSegmentCount: assembledTranscript.successfulSegmentCount
            )
        } else {
            resultNotice = nil
        }

        state = .success(text: assembledTranscript.text)
        clipboardService.writeToClipboard(assembledTranscript.text)
        scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
    }

    private func sealAndQueueCurrentSegment(
        reason: SegmentSealReason,
        phase: LongSessionStatus.Phase,
        sessionID: UUID
    ) {
        do {
            let sealedSegment = try bufferAccumulator.sealSegment(index: nextQueuedSegmentIndex, reason: reason)
            queuedSegments.append(sealedSegment)
            nextQueuedSegmentIndex += 1
            refreshLongSessionStatus(phase: phase)
            beginQueuedSegmentTranscription(for: sealedSegment, sessionID: sessionID)
        } catch AudioBufferAccumulatorError.emptyBuffers {
            refreshLongSessionStatus(phase: phase)
        } catch {
            NSLog("ActivationStore: failed to seal long dictation segment: \(error.localizedDescription)")
        }
    }

    private func beginQueuedSegmentTranscription(for segment: QueuedSegment, sessionID: UUID) {
        updateQueuedSegment(index: segment.index) { $0.transcriptionState = .transcribing }
        refreshLongSessionStatus(phase: longSessionStatus.phase)

        queuedSegmentTasks[segment.index] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.queuedSegmentTasks[segment.index] = nil
                if self.isCurrentSession(sessionID) {
                    self.refreshLongSessionStatus(phase: self.longSessionStatus.phase)
                }
            }

            do {
                if self.shouldInjectUITestingFailure(for: segment.index) {
                    self.updateQueuedSegment(index: segment.index) {
                        $0.transcriptionState = .failed(message: TranscriptionError.inferenceFailed.localizedDescription)
                    }
                    return
                }

                try await self.prepareWhisperModelIfNeeded()
                guard self.isCurrentSession(sessionID) else { return }

                let text = try await self.whisperService.transcribe(samples: segment.audio.samples)
                guard self.isCurrentSession(sessionID) else { return }

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.updateQueuedSegment(index: segment.index) {
                        $0.transcriptionState = .failed(message: TranscriptionError.noSpeechDetected.localizedDescription)
                    }
                } else {
                    self.updateQueuedSegment(index: segment.index) {
                        $0.transcriptionState = .completed(text: trimmed)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrentSession(sessionID) else { return }
                self.updateQueuedSegment(index: segment.index) {
                    $0.transcriptionState = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    private func shouldInjectUITestingFailure(for segmentIndex: Int) -> Bool {
        uiTestingLongSessionFailureSegmentIndex == segmentIndex
    }

    private func settleQueuedSegmentWork(sessionID: UUID) async {
        let tasks = Array(queuedSegmentTasks.values)
        for task in tasks {
            await task.value
            guard isCurrentSession(sessionID) else { return }
        }
    }

    private func updateQueuedSegment(index: Int, _ mutate: (inout QueuedSegment) -> Void) {
        guard let segmentIndex = queuedSegments.firstIndex(where: { $0.index == index }) else { return }
        mutate(&queuedSegments[segmentIndex])
    }

    private func failureReasonForQueuedSegments() -> Error {
        let failureMessages = queuedSegments.compactMap { segment -> String? in
            guard case .failed(let message) = segment.transcriptionState else {
                return nil
            }
            return message
        }

        if let modelFailure = failureMessages.first(where: {
            $0 != TranscriptionError.noSpeechDetected.localizedDescription
        }) {
            return NSError(
                domain: "ActivationStore.LongDictation",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: modelFailure]
            )
        }

        return TranscriptionError.noSpeechDetected
    }

    private func failureReason(for error: AudioCaptureError) -> RecordingState.FailureReason {
        switch error {
        case .microphonePermissionDenied:
            return .microphonePermissionDenied
        case .selectedInputUnavailable:
            return .selectedMicrophoneUnavailable
        case .noUsableInputDevice:
            return .microphoneUnavailable
        case .selectedInputDisconnected:
            return .selectedMicrophoneDisconnected
        case .engineException(let underlyingError):
            return .modelError(underlyingError.localizedDescription)
        }
    }
}
