import AppKit
import Combine
import Foundation

// MARK: - ActivationSoundPlayer

struct ActivationSoundPlayer {
    func play() {
        sound(named: "Tink")?.play()
    }

    func playSuccess() {
        sound(named: "Glass")?.play()
    }

    func playFailure() {
        sound(named: "Basso")?.play()
    }

    private func sound(named name: String) -> NSSound? {
        if let url = Bundle.main.url(forResource: name, withExtension: "aiff") {
            return NSSound(contentsOf: url, byReference: false)
        }
        return NSSound(named: name)
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
        llmRewriteService: LLMRewriteService.shared,
        userIntentStore: UserIntentStore.shared,
        clipboardService: ClipboardService(),
        pasteService: PasteService(),
        bufferAccumulator: AudioBufferAccumulator(),
        resetSessionMonitoring: {}
    )

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var recoveryFeedback: RecordingState.RecoveryFeedback?
    @Published private(set) var lastTranscription: String?
    @Published private(set) var lastConvertedTranscription: String?

    private let preferences: ShellPreferences
    private let readinessProvider: any ReadinessProviding
    private let whisperService: any WhisperTranscribing
    private let llmRewriteService: any LLMRewriting
    private let userIntentStore: UserIntentStore
    private let clipboardService: ClipboardService
    private let pasteService: PasteService
    private let resetSessionMonitoring: @MainActor () -> Void
    let bufferAccumulator: AudioBufferAccumulator
    let voiceActivityDetector: VoiceActivityDetector
    var soundPlayer: ActivationSoundPlayer = .init()
    private static let maxRecordingDuration: UInt64 = 5 * 60 * 1_000_000_000 // 5 minutes

    var onPastePermissionNeeded: () -> Void = {}

    private var pasteOnCompletion = false
    private var activeSessionID = UUID()
    private var transcriptionTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var feedbackClearTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?

    convenience init(preferences: ShellPreferences, readinessStore: ReadinessStore) {
        self.init(
            preferences: preferences,
            readinessProvider: readinessStore,
            whisperService: WhisperService(),
            clipboardService: ClipboardService(),
            pasteService: PasteService(),
            bufferAccumulator: AudioBufferAccumulator(),
            resetSessionMonitoring: {}
        )
    }

    init(
        preferences: ShellPreferences,
        readinessProvider: any ReadinessProviding,
        whisperService: any WhisperTranscribing = WhisperService(),
        llmRewriteService: any LLMRewriting = LLMRewriteService.shared,
        userIntentStore: UserIntentStore = UserIntentStore.shared,
        clipboardService: ClipboardService = ClipboardService(),
        pasteService: PasteService = PasteService(),
        bufferAccumulator: AudioBufferAccumulator = AudioBufferAccumulator(),
        resetSessionMonitoring: @escaping @MainActor () -> Void = {}
    ) {
        self.preferences = preferences
        self.readinessProvider = readinessProvider
        self.whisperService = whisperService
        self.llmRewriteService = llmRewriteService
        self.userIntentStore = userIntentStore
        self.clipboardService = clipboardService
        self.pasteService = pasteService
        self.bufferAccumulator = bufferAccumulator
        self.voiceActivityDetector = VoiceActivityDetector(destination: bufferAccumulator)
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

        // If we're interrupting a terminal state, cancel the dismiss timer and
        // transition through idle first so observers (AppDelegate) can cleanly
        // tear down the previous session's resources before starting fresh.
        if state.isTerminal {
            invalidateScheduledWork()
            state = .idle
        }

        // Require all permissions to be granted, but do NOT require setup to be
        // "finalized" (hasCompletedInitialSetup). The finalize step is an
        // onboarding UX gate, not a runtime safety requirement. Recording must
        // work as soon as microphone and keyboard-monitoring permissions are
        // authorized, even if the user dismissed the setup window early.
        let snapshot = readinessProvider.snapshot
        guard snapshot.permissions.filter(\.isRequired).allSatisfy(\.isAuthorized) else {
            return
        }

        soundPlayer.play()

        invalidateScheduledWork()
        recoveryFeedback = nil
        activeSessionID = UUID()
        voiceActivityDetector.reset()
        state = .recording

        // Auto-stop after 5 minutes to prevent runaway recordings.
        let sessionID = activeSessionID
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.maxRecordingDuration)
            guard let self, self.isCurrentSession(sessionID), self.state == .recording else { return }
            self.finish()
        }

        // When auto-selection is off the model choice is fixed, so preload it
        // while the user is still speaking to eliminate load-time after recording.
        if !preferences.autoModelSelection {
            Task { [weak self] in
                try? await self?.prepareWhisperModel(for: nil)
            }
        }
    }

    /// Arm with paste intent: records then pastes the transcription to the active cursor position.
    func armAndPaste() {
        guard isPostEventPermissionGranted else {
            onPastePermissionNeeded()
            return
        }
        pasteOnCompletion = true
        arm()
    }

    /// Finish recording and paste the transcription to the active cursor position.
    func finishAndPaste() {
        if isPostEventPermissionGranted {
            pasteOnCompletion = true
        } else {
            onPastePermissionNeeded()
        }
        finish()
    }

    private var isPostEventPermissionGranted: Bool {
        readinessProvider.snapshot.permissions
            .first(where: { $0.kind == .postEvent })?.isAuthorized ?? false
    }

    /// Hard stop — transitions directly to idle without transcribing. Used for cancel (Phase 4).
    func stop() {
        cancelCurrentSession()
    }

    func cancelCurrentSession() {
        guard state == .recording || state == .processing else { return }

        invalidateActiveSession()
        voiceActivityDetector.reset()
        publishRecoveryFeedback(.canceled)
        state = .idle
    }

    func restartCurrentSession() {
        guard state == .recording else { return }

        invalidateActiveSession()
        voiceActivityDetector.reset()
        resetSessionMonitoring()
        publishRecoveryFeedback(.restarted)
        state = .recording
    }

    /// Copies the last transcription to the clipboard.
    func copyLastTranscription() {
        if let text = lastTranscription {
            clipboardService.writeToClipboard(text)
        }
    }

    /// Copies the last converted transcription to the clipboard.
    func copyLastConvertedTranscription() {
        if let text = lastConvertedTranscription {
            clipboardService.writeToClipboard(text)
        }
    }

    /// Finish recording: stops capture and runs the transcription -> clipboard -> dismiss flow.
    func finish() {
        guard state == .recording else { return }
        invalidateScheduledWork()
        recoveryFeedback = nil
        let sessionID = activeSessionID
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
        voiceActivityDetector.reset()
        recoveryFeedback = nil

        let failureSessionID = activeSessionID
        state = .failure(reason: failureReason(for: error))
        soundPlayer.playFailure()
        scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: failureSessionID)
    }

    // MARK: - Private transcription flow

    private func finalizeSession(sessionID: UUID) async {
        do {
            guard isCurrentSession(sessionID) else { return }

            try await prepareWhisperModel(for: bufferAccumulator.duration)
            guard isCurrentSession(sessionID) else { return }

            let samples = try bufferAccumulator.convertToWhisperFormat()
            let text = try await whisperService.transcribe(samples: samples)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard isCurrentSession(sessionID) else { return }
            guard !trimmed.isEmpty else {
                throw TranscriptionError.noSpeechDetected
            }

            // Snapshot merged catalog from UserIntentStore for detection
            let storeEntries = await userIntentStore.allEntries()
            let effectiveDefinitions = IntentCatalog.effective(store: storeEntries)
            let intent = IntentDetector.detect(transcript: trimmed, definitions: effectiveDefinitions)

            if intent.mode == .passthrough && intent.customIntentID == nil {
                // LLM-02: passthrough path completely unchanged
                let didPaste = pasteOnCompletion
                pasteOnCompletion = false
                lastTranscription = trimmed
                if didPaste {
                    pasteService.paste(text: trimmed)
                } else {
                    clipboardService.writeToClipboard(trimmed)
                }
                state = .success(text: trimmed, pasted: didPaste, converted: false, noMatchPassthrough: intent.hadCandidates)
                soundPlayer.playSuccess()
                scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
            } else {
                // Conversion path — paste is not supported for LLM output
                pasteOnCompletion = false

                // GUARD-01: 350-word gate (count on strippedBody, NOT trimmed)
                let wordCount = intent.strippedBody
                    .split(separator: " ", omittingEmptySubsequences: true).count
                guard wordCount <= 350 else {
                    guard isCurrentSession(sessionID) else { return }
                    clipboardService.writeToClipboard(trimmed)  // raw transcript to clipboard first
                    lastTranscription = trimmed
                    let failureSessionID = activeSessionID
                    state = .failure(reason: .wordLimitExceeded)
                    soundPlayer.playFailure()
                    scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: failureSessionID)
                    return
                }

                guard isCurrentSession(sessionID) else { return }
                state = .converting

                // Resolve effective system prompt from matched entry
                let resolvedInstructions: String?
                if let customID = intent.customIntentID {
                    // Custom mode: look up entry by modeName match
                    resolvedInstructions = storeEntries.first { !$0.isBuiltIn && $0.modeName == customID }?.systemPrompt
                } else if intent.mode != .passthrough {
                    // Built-in: check for store override
                    resolvedInstructions = storeEntries.first { $0.id == intent.mode.rawValue && $0.isBuiltIn }?.systemPrompt
                } else {
                    resolvedInstructions = nil
                }

                // LLM call — rewrite() hops to LLMRewriteService actor automatically
                let rewritten: String
                do {
                    if let instructions = resolvedInstructions {
                        rewritten = try await llmRewriteService.rewrite(
                            body: intent.strippedBody,
                            instructions: instructions
                        )
                    } else {
                        rewritten = try await llmRewriteService.rewrite(
                            body: intent.strippedBody,
                            mode: intent.mode
                        )
                    }
                } catch {
                    // GUARD-02 fallback: silent — raw transcript to clipboard
                    guard isCurrentSession(sessionID) else { return }
                    clipboardService.writeToClipboard(trimmed)
                    lastTranscription = trimmed
                    state = .success(text: trimmed, pasted: false, converted: false)
                    soundPlayer.playSuccess()
                    scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
                    return
                }

                guard isCurrentSession(sessionID) else { return }
                clipboardService.writeToClipboard(rewritten)
                lastTranscription = trimmed          // raw always stored
                lastConvertedTranscription = rewritten
                state = .success(text: rewritten, pasted: false, converted: true)
                soundPlayer.playSuccess()
                scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
            }
        } catch TranscriptionError.noSpeechDetected {
            guard isCurrentSession(sessionID) else { return }
            state = .failure(reason: .noSpeechDetected)
            soundPlayer.playFailure()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        } catch {
            guard isCurrentSession(sessionID) else { return }
            state = .failure(reason: .modelError(error.localizedDescription))
            soundPlayer.playFailure()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        }

        if sessionID == activeSessionID {
            transcriptionTask = nil
        }
    }

    private func invalidateActiveSession() {
        pasteOnCompletion = false
        activeSessionID = UUID()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        invalidateScheduledWork()
    }

    private func invalidateScheduledWork() {
        dismissTask?.cancel()
        dismissTask = nil
        feedbackClearTask?.cancel()
        feedbackClearTask = nil
        maxDurationTask?.cancel()
        maxDurationTask = nil
    }

    private func publishRecoveryFeedback(_ feedback: RecordingState.RecoveryFeedback) {
        feedbackClearTask?.cancel()
        recoveryFeedback = feedback
        let delay: UInt64 = feedback == .restarted ? 250_000_000 : 1_500_000_000
        feedbackClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
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
            case .idle, .recording, .processing, .converting:
                break
            }
            self.dismissTask = nil
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        !Task.isCancelled && sessionID == activeSessionID
    }

    private func prepareWhisperModel(for duration: TimeInterval?) async throws {
        if let whisperService = whisperService as? WhisperService {
            let modelChoice: WhisperModelChoice
            if preferences.autoModelSelection, let duration {
                modelChoice = WhisperModelChoice.forDuration(duration)
            } else {
                modelChoice = preferences.whisperModel
            }
            try await whisperService.prepare(model: modelChoice.rawValue)
        }
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
