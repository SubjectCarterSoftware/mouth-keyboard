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

@MainActor
protocol WhisperModelLoadStateProviding: AnyObject {
    var phase: WhisperModelLoadState.Phase { get }
    var phasePublisher: AnyPublisher<WhisperModelLoadState.Phase, Never> { get }
}

extension WhisperModelLoadState: WhisperModelLoadStateProviding {
    var phasePublisher: AnyPublisher<WhisperModelLoadState.Phase, Never> {
        $phase.eraseToAnyPublisher()
    }
}

// MARK: - ActivationStore

@MainActor
final class ActivationStore: ObservableObject {
    private enum ActivationOrigin {
        case toggle
        case hold
    }

    static let shared = ActivationStore(
        preferences: .shared,
        readinessProvider: ReadinessStore.shared,
        whisperService: WhisperService.shared,
        llmRewriteService: LLMRewriteService.shared,
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
    private let whisperModelLoadState: any WhisperModelLoadStateProviding
    private let whisperService: any WhisperTranscribing
    private let llmRewriteService: any LLMRewriting
    private let clipboardService: ClipboardService
    private let pasteService: any PasteServicing
    private let resetSessionMonitoring: @MainActor () -> Void
    let bufferAccumulator: AudioBufferAccumulator
    let voiceActivityDetector: VoiceActivityDetector
    var soundPlayer: ActivationSoundPlayer = .init()
    private static let maxRecordingDuration: UInt64 = 5 * 60 * 1_000_000_000 // 5 minutes
    private static let whisperModelIdleUnloadDelay: UInt64 = WhisperService.idleUnloadDelayNanoseconds
    private static let rewriteModelIdleUnloadDelay: UInt64 = LLMRewriteService.idleUnloadDelayNanoseconds

    var onPastePermissionNeeded: () -> Void = {}

    private var requestsPasteOnCompletion = false
    private var activeSessionID = UUID()
    private var activeActivationOrigin: ActivationOrigin?
    private var transcriptionTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var feedbackClearTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?

    convenience init(preferences: ShellPreferences, readinessStore: ReadinessStore) {
        self.init(
            preferences: preferences,
            readinessProvider: readinessStore,
            whisperModelLoadState: WhisperModelLoadState.shared,
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
        whisperModelLoadState: any WhisperModelLoadStateProviding = WhisperModelLoadState.shared,
        whisperService: any WhisperTranscribing = WhisperService(),
        llmRewriteService: any LLMRewriting = LLMRewriteService.shared,
        clipboardService: ClipboardService = ClipboardService(),
        pasteService: any PasteServicing = PasteService(),
        bufferAccumulator: AudioBufferAccumulator = AudioBufferAccumulator(),
        resetSessionMonitoring: @escaping @MainActor () -> Void = {}
    ) {
        self.preferences = preferences
        self.readinessProvider = readinessProvider
        self.whisperModelLoadState = whisperModelLoadState
        self.whisperService = whisperService
        self.llmRewriteService = llmRewriteService
        self.clipboardService = clipboardService
        self.pasteService = pasteService
        self.bufferAccumulator = bufferAccumulator
        self.voiceActivityDetector = VoiceActivityDetector(destination: bufferAccumulator)
        self.resetSessionMonitoring = resetSessionMonitoring
    }

    /// Returns the cloud service when cloud LLM is enabled, otherwise the local on-device service.
    /// Rebuilds the cloud service each call to pick up any config changes between sessions.
    private var activeRewriteService: any LLMRewriting {
        let config = preferences.cloudLLMConfig
        guard config.isEnabled, !config.modelID.isEmpty else {
            return llmRewriteService
        }
        guard let apiKey = CloudLLMKeychain.loadAPIKey(for: config.provider), !apiKey.isEmpty else {
            return llmRewriteService
        }
        return CloudLLMRewriteService(config: config, apiKey: apiKey)
    }

    // MARK: - Public API

    func arm() {
        guard state != .recording else { return }
        _ = beginRecording(origin: .toggle)
    }

    /// Arm with paste intent: records then pastes the transcription to the active cursor position.
    func armAndPaste() {
        requestsPasteOnCompletion = true
        if !isPostEventPermissionGranted {
            onPastePermissionNeeded()
        }
        if state == .recording {
            finish()
            return
        }
        _ = beginRecording(origin: .toggle)
    }

    @discardableResult
    func beginHoldSession() -> Bool {
        beginRecording(origin: .hold)
    }

    func finishHoldSession() {
        guard state == .recording, activeActivationOrigin == .hold else { return }
        finish()
    }

    /// Finish recording and paste the transcription to the active cursor position.
    func finishAndPaste() {
        requestsPasteOnCompletion = true
        if !isPostEventPermissionGranted {
            onPastePermissionNeeded()
        }
        finish()
    }

    private var isPostEventPermissionGranted: Bool {
        readinessProvider.snapshot.permissions
            .first(where: { $0.kind == .postEvent })?.isAuthorized ?? false
    }

    private var shouldAlwaysAutoPaste: Bool {
        preferences.alwaysAutoPaste
    }

    private var shouldGuideForMissingAutoPastePermission: Bool {
        (requestsPasteOnCompletion || shouldAlwaysAutoPaste) && !isPostEventPermissionGranted
    }

    private var shouldPasteOnSuccessfulFinish: Bool {
        (requestsPasteOnCompletion || shouldAlwaysAutoPaste) && isPostEventPermissionGranted
    }

    /// Hard stop — transitions directly to idle without transcribing. Used for cancel (Phase 4).
    func stop() {
        cancelCurrentSession()
    }

    func cancelCurrentSession() {
        guard
            state == .recording
                || state == .processing
                || state.isModelDownloading
                || state == .converting
        else {
            return
        }

        invalidateActiveSession()
        voiceActivityDetector.reset()
        publishRecoveryFeedback(.canceled)
        state = .idle
        scheduleWhisperModelIdleUnload()
        scheduleRewriteModelIdleUnload()
    }

    func restartCurrentSession() {
        guard state == .recording else { return }

        let currentOrigin = activeActivationOrigin
        invalidateActiveSession()
        activeActivationOrigin = currentOrigin
        voiceActivityDetector.reset()
        resetSessionMonitoring()
        publishRecoveryFeedback(.restarted)
        state = .recording
        beginWhisperModelWarmup()
        beginRewriteModelWarmup()
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
        if shouldGuideForMissingAutoPastePermission {
            onPastePermissionNeeded()
        }
        invalidateScheduledWork()
        recoveryFeedback = nil
        activeActivationOrigin = nil
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

    @discardableResult
    private func beginRecording(origin: ActivationOrigin) -> Bool {
        // Ignore activation while transcription is in flight, but allow a new
        // recording to interrupt terminal feedback instead of waiting for the
        // auto-dismiss timer to return to idle.
        guard state == .idle || state.isTerminal else {
            return false
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
        // work as soon as all required permissions are authorized, even if the
        // user dismissed the setup window early.
        let snapshot = readinessProvider.snapshot
        guard snapshot.permissions.filter(\.isRequired).allSatisfy(\.isAuthorized) else {
            return false
        }

        soundPlayer.play()

        invalidateScheduledWork()
        recoveryFeedback = nil
        activeSessionID = UUID()
        activeActivationOrigin = origin
        voiceActivityDetector.reset()
        state = .recording
        beginWhisperModelWarmup()
        beginRewriteModelWarmup()

        // Auto-stop after 5 minutes to prevent runaway recordings.
        let sessionID = activeSessionID
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.maxRecordingDuration)
            guard let self, self.isCurrentSession(sessionID), self.state == .recording else { return }
            self.finish()
        }

        return true
    }

    private func finalizeSession(sessionID: UUID) async {
        do {
            guard isCurrentSession(sessionID) else { return }

            let selectedModel = preferences.whisperModel
            do {
                let downloadObserver = observeWhisperModelDownloadProgress(
                    for: selectedModel,
                    sessionID: sessionID
                )
                defer {
                    downloadObserver.cancel()
                    syncWhisperModelDownloadState(for: selectedModel, phase: .idle, sessionID: sessionID)
                }

                try await prepareWhisperModel(model: selectedModel)
            }
            guard isCurrentSession(sessionID) else { return }

            let samples = try bufferAccumulator.convertToWhisperFormat()
            let text = try await whisperService.transcribe(samples: samples)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let triggerAliases = TriggerAliasNormalizer.normalize(preferences.activeTriggerProfile.activeAliases)

            guard isCurrentSession(sessionID) else { return }
            guard !trimmed.isEmpty else {
                throw TranscriptionError.noSpeechDetected
            }

            let split = TriggerTranscriptParser.split(transcript: trimmed, activeAliases: triggerAliases)
            let shouldConvert: Bool
            let conversionBody: String
            let conversionInstructions: String?
            switch split {
            case .noTrigger:
                shouldConvert = false
                conversionBody = trimmed
                conversionInstructions = nil
            case .invalidTrigger:
                shouldConvert = false
                conversionBody = trimmed
                conversionInstructions = nil
            case .validTrigger(let content, let instruction, _):
                shouldConvert = true
                conversionBody = content.trimmingCharacters(in: .whitespacesAndNewlines)
                conversionInstructions = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if !shouldConvert {
                let didPaste = shouldPasteOnSuccessfulFinish
                requestsPasteOnCompletion = false
                lastTranscription = trimmed
                var syntheticPasteSucceeded = false
                if didPaste {
                    let outcome = pasteService.paste(text: trimmed)
                    syntheticPasteSucceeded = (outcome == .pasted)
                } else {
                    clipboardService.writeToClipboard(trimmed)
                }
                state = .success(
                    text: trimmed,
                    pasted: syntheticPasteSucceeded,
                    converted: false,
                    noMatchPassthrough: false
                )
                soundPlayer.playSuccess()
                scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
            } else {
                let didPaste = shouldPasteOnSuccessfulFinish
                requestsPasteOnCompletion = false

                let wordCount = conversionBody
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

                // LLM call — routes to cloud or local service based on config
                let rewritten: String
                do {
                    if let instructions = conversionInstructions {
                        rewritten = try await activeRewriteService.rewrite(
                            body: conversionBody,
                            instructions: instructions
                        )
                    } else {
                        rewritten = conversionBody
                    }
                } catch {
                    // GUARD-02: surface rewrite error visibly — raw transcript still goes to clipboard
                    guard isCurrentSession(sessionID) else { return }
                    let errorDescription = (error as? LLMRewriteError)?.errorDescription ?? error.localizedDescription
                    NSLog("Speech2Text: assistant rewrite failed — \(errorDescription)")
                    clipboardService.writeToClipboard(trimmed)
                    lastTranscription = trimmed
                    state = .failure(reason: .modelError("Rewrite failed: \(errorDescription)"))
                    soundPlayer.playFailure()
                    scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
                    return
                }

                guard isCurrentSession(sessionID) else { return }
                var syntheticPasteSucceeded = false
                if didPaste {
                    let outcome = pasteService.paste(text: rewritten)
                    syntheticPasteSucceeded = (outcome == .pasted)
                } else {
                    clipboardService.writeToClipboard(rewritten)
                }
                lastTranscription = trimmed          // raw always stored
                lastConvertedTranscription = rewritten
                state = .success(text: rewritten, pasted: syntheticPasteSucceeded, converted: true)
                soundPlayer.playSuccess()
                scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)
            }
        } catch TranscriptionError.noSpeechDetected {
            guard isCurrentSession(sessionID) else { return }
            state = .failure(reason: .noSpeechDetected)
            soundPlayer.playFailure()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        } catch AudioBufferAccumulatorError.emptyBuffers {
            guard isCurrentSession(sessionID) else { return }
            state = .failure(reason: .noSpeechDetected)
            soundPlayer.playFailure()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        } catch AudioBufferAccumulatorError.overflow {
            guard isCurrentSession(sessionID) else { return }
            state = .failure(reason: .wordLimitExceeded)
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
        requestsPasteOnCompletion = false
        activeSessionID = UUID()
        activeActivationOrigin = nil
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
                self.scheduleWhisperModelIdleUnload()
                self.scheduleRewriteModelIdleUnload()
            case .idle, .recording, .processing, .modelDownloading, .converting:
                break
            }
            self.dismissTask = nil
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        !Task.isCancelled && sessionID == activeSessionID
    }

    private func beginWhisperModelWarmup() {
        Task { [weak self] in
            guard let self else { return }
            await self.whisperService.cancelScheduledUnload()
            try? await self.whisperService.prepare(model: self.preferences.whisperModel)
        }
    }

    private func scheduleWhisperModelIdleUnload() {
        Task { [whisperService] in
            await whisperService.scheduleIdleUnload(
                afterNanoseconds: Self.whisperModelIdleUnloadDelay
            )
        }
    }

    private func prepareWhisperModel() async throws {
        try await whisperService.prepare(model: preferences.whisperModel)
    }

    private func prepareWhisperModel(model: WhisperModelChoice) async throws {
        try await whisperService.prepare(model: model)
    }

    private func observeWhisperModelDownloadProgress(
        for model: WhisperModelChoice,
        sessionID: UUID
    ) -> AnyCancellable {
        syncWhisperModelDownloadState(for: model, phase: whisperModelLoadState.phase, sessionID: sessionID)
        return whisperModelLoadState.phasePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.syncWhisperModelDownloadState(for: model, phase: phase, sessionID: sessionID)
            }
    }

    private func syncWhisperModelDownloadState(
        for model: WhisperModelChoice,
        phase: WhisperModelLoadState.Phase,
        sessionID: UUID
    ) {
        guard sessionID == activeSessionID else { return }

        switch phase {
        case .downloading(let activeModel, let progress) where activeModel == model:
            state = .modelDownloading(model: activeModel, progress: progress)
        default:
            if case .modelDownloading(let activeModel, _) = state, activeModel == model {
                state = .processing
            }
        }
    }

    private func beginRewriteModelWarmup() {
        // Cloud mode has no local model to warm up.
        guard !preferences.cloudLLMConfig.isEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.llmRewriteService.cancelScheduledUnload()
            await self.llmRewriteService.setTier(self.preferences.rewriteModelTier)
            try? await self.llmRewriteService.prewarm()
        }
    }

    private func scheduleRewriteModelIdleUnload() {
        guard !preferences.cloudLLMConfig.isEnabled else { return }
        Task { [llmRewriteService] in
            await llmRewriteService.scheduleIdleUnload(
                afterNanoseconds: Self.rewriteModelIdleUnloadDelay
            )
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
        case .captureBusy:
            return .modelError(error.localizedDescription)
        }
    }
}
