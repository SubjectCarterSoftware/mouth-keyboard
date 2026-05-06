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

    private enum PipelineTimeoutError: LocalizedError {
        case stepTimedOut(String)

        var errorDescription: String? {
            switch self {
            case .stepTimedOut(let step):
                return "\(step) timed out."
            }
        }
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
    @Published private(set) var successDismissStartedAt: Date?
    @Published private(set) var successDismissDeadline: Date?

    private let preferences: ShellPreferences
    private let readinessProvider: any ReadinessProviding
    private let whisperModelLoadState: any WhisperModelLoadStateProviding
    private let whisperService: any WhisperTranscribing
    private let llmRewriteService: any LLMRewriting
    private let clipboardService: ClipboardService
    private let pasteService: any PasteServicing
    private let resetSessionMonitoring: @MainActor () -> Void
    let bufferAccumulator: AudioBufferAccumulator
    var soundPlayer: ActivationSoundPlayer = .init()
    private static let maxRecordingDuration: UInt64 = 5 * 60 * 1_000_000_000 // 5 minutes
    private static let audioCaptureStopSettleDelay: UInt64 = 40_000_000
    private static let minimumTranscriptionAudioDuration: TimeInterval = 1.0
    private static let appendedTrailingSilenceDuration: TimeInterval = 0.35
    private static let minimumConvertingDisplayDuration: UInt64 = 200_000_000
    private static let whisperModelIdleUnloadDelay: UInt64 = WhisperService.idleUnloadDelayNanoseconds
    private static let rewriteModelIdleUnloadDelay: UInt64 = LLMRewriteService.idleUnloadDelayNanoseconds
    private static let whisperPrepareTimeout: UInt64 = 20_000_000_000
    private static let whisperTranscriptionTimeout: UInt64 = 45_000_000_000
    private static let clipboardIntentTimeout: UInt64 = 8_000_000_000
    private static let rewriteTimeout: UInt64 = 45_000_000_000
    private static let clipboardRestoreDelay: UInt64 = 150_000_000
    private static let successDismissDelay: UInt64 = 6_000_000_000
    private static let successDismissDurationSeconds = TimeInterval(successDismissDelay) / 1_000_000_000

    var onPastePermissionNeeded: () -> Void = {}

    private var requestsPasteOnCompletion = false
    private var forceLLMNextSession = false
    private var retryHistory: [(instruction: String, output: String)] = []
    private var activeSessionID = UUID()
    private var activeActivationOrigin: ActivationOrigin?
    private var transcriptionTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var feedbackClearTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var sessionClipboardSnapshot: ClipboardSnapshot?
    private var downloadGateCancellable: AnyCancellable?

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

    private var shouldRestorePreviousClipboardAfterAutoPaste: Bool {
        preferences.restorePreviousClipboardAfterAutoPaste
    }

    private var shouldMuteSoundEffects: Bool {
        preferences.muteSoundEffects
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
        bufferAccumulator.reset()
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
        bufferAccumulator.reset()
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

    func pasteCurrentSuccessResult() {
        guard let successText = currentSuccessText else { return }

        refreshSuccessDismissTimer()
        guard isPostEventPermissionGranted else {
            onPastePermissionNeeded()
            return
        }

        let originalClipboard = shouldRestorePreviousClipboardAfterAutoPaste
            ? clipboardService.snapshotCurrentClipboard()
            : nil
        Task { [weak self] in
            guard let self else { return }
            _ = await self.pasteWithClipboardProtection(
                text: successText,
                originalClipboard: originalClipboard
            )
        }
    }

    func copyCurrentSuccessResult() {
        guard let successText = currentSuccessText else { return }
        clipboardService.writeToClipboard(successText)
        refreshSuccessDismissTimer()
    }

    func dismissCurrentSuccess() {
        guard case .success = state else { return }

        dismissTask?.cancel()
        dismissTask = nil
        clearSuccessDismissTiming()
        retryHistory = []
        recoveryFeedback = nil
        state = .idle
        scheduleWhisperModelIdleUnload()
        scheduleRewriteModelIdleUnload()
    }

    /// Restart from success: undoes the paste, re-enters recording, and re-enables LLM if it was used.
    func restartFromSuccess() {
        guard case .success(_, let pasted, let converted, _, _) = state else { return }
        if pasted { sendUndo() }
        if converted {
            forceLLMNextSession = true
            if let raw = lastTranscription, let output = lastConvertedTranscription {
                retryHistory.append((instruction: raw, output: output))
            }
        }
        requestsPasteOnCompletion = pasted
        _ = beginRecording(origin: .toggle)
    }

    /// Append from success: re-enters recording and pastes the new result after the existing paste.
    func appendFromSuccess() {
        guard state.isSuccess else { return }
        retryHistory = []
        requestsPasteOnCompletion = true
        _ = beginRecording(origin: .toggle)
    }

    private func sendUndo() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 6, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 6, keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
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
            try? await Task.sleep(nanoseconds: Self.audioCaptureStopSettleDelay)
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
        recoveryFeedback = nil

        let failureSessionID = activeSessionID
        state = .failure(reason: failureReason(for: error))
        playFailureSoundIfNeeded()
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
            clearSuccessDismissTiming()
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

        // Block recording until the selected Whisper model is available on disk.
        // If it's still downloading, show the progress pill and wait for completion.
        let selectedModel = preferences.whisperModel
        if !isWhisperModelReady(selectedModel) {
            beginModelDownloadGate(for: selectedModel)
            return false
        }

        playStartSoundIfNeeded()

        invalidateScheduledWork()
        recoveryFeedback = nil
        activeSessionID = UUID()
        sessionClipboardSnapshot = clipboardService.snapshotCurrentClipboard()
        activeActivationOrigin = origin
        bufferAccumulator.reset()
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
            NSLog("TypeLessBuddy: finalize session started (\(sessionID.uuidString.prefix(8))) using Whisper \(selectedModel.rawValue)")
            do {
                let downloadObserver = observeWhisperModelDownloadProgress(
                    for: selectedModel,
                    sessionID: sessionID
                )
                defer {
                    downloadObserver.cancel()
                    syncWhisperModelDownloadState(for: selectedModel, phase: .idle, sessionID: sessionID)
                }

                try await runWithTimeout(
                    nanoseconds: Self.whisperPrepareTimeout,
                    step: "Whisper model prepare"
                ) { [whisperService] in
                    try await whisperService.prepare(model: selectedModel)
                }
            }
            guard isCurrentSession(sessionID) else { return }

            let samples = AudioBufferAccumulator.prepareForTranscription(
                try bufferAccumulator.convertToWhisperFormat(),
                minimumDuration: Self.minimumTranscriptionAudioDuration,
                trailingSilenceDuration: Self.appendedTrailingSilenceDuration
            )
            let text = try await runWithTimeout(
                nanoseconds: Self.whisperTranscriptionTimeout,
                step: "Whisper transcription"
            ) { [whisperService] in
                try await whisperService.transcribe(samples: samples)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let triggerNames = preferences.activeTriggerProfile.allCanonicalNames

            guard isCurrentSession(sessionID) else { return }
            guard !trimmed.isEmpty else {
                throw TranscriptionError.noSpeechDetected
            }

            let detection = TriggerTranscriptParser.detect(transcript: trimmed, triggerNames: triggerNames)
            let clipboardSnapshot = sessionClipboardSnapshot
            let shouldConvert: Bool
            switch detection {
            case .noTrigger:
                shouldConvert = forceLLMNextSession
            case .triggered:
                shouldConvert = true
            }
            forceLLMNextSession = false

            if !shouldConvert {
                let didPaste = shouldPasteOnSuccessfulFinish
                let originalClipboardForPaste = shouldRestorePreviousClipboardAfterAutoPaste
                    ? clipboardSnapshot
                    : nil
                requestsPasteOnCompletion = false
                lastTranscription = trimmed
                var syntheticPasteSucceeded = false
                if didPaste {
                    syntheticPasteSucceeded = await pasteWithClipboardProtection(
                        text: trimmed,
                        originalClipboard: originalClipboardForPaste
                    )
                } else {
                    clipboardService.writeToClipboard(trimmed)
                }
                state = .success(
                    text: trimmed,
                    pasted: syntheticPasteSucceeded,
                    converted: false,
                    noMatchPassthrough: false
                )
                playSuccessSoundIfNeeded()
                beginSuccessDismissTiming(sessionID: sessionID)
            } else {
                let didPaste = shouldPasteOnSuccessfulFinish
                let originalClipboardForPaste = shouldRestorePreviousClipboardAfterAutoPaste
                    ? clipboardSnapshot
                    : nil
                requestsPasteOnCompletion = false

                guard isCurrentSession(sessionID) else { return }
                state = .converting
                let convertingStartedAt = DispatchTime.now().uptimeNanoseconds
                let assistantName = preferences.activeTriggerProfile.activePrimary
                let systemPrompt = LLMRewriteService.resolveAssistantSystemPrompt(
                    promptTemplate: preferences.rewriteSystemPromptPrefix,
                    assistantName: assistantName
                )

                // Clipboard-aware content injection
                var effectiveBody = trimmed
                var clipboardWasInjected = false

                let intent = try await runWithTimeout(
                    nanoseconds: Self.clipboardIntentTimeout,
                    step: "Clipboard intent classification"
                ) { [llmRewriteService] in
                    await ClipboardIntentClassifier.classify(
                        message: trimmed,
                        using: llmRewriteService
                    )
                }

                guard isCurrentSession(sessionID) else { return }

                if intent == .detected {
                    if let clipboardText = clipboardSnapshot?.plainText,
                       !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        effectiveBody = ClipboardAwarePromptBuilder.buildBody(
                            dictatedContent: trimmed,
                            clipboardContent: clipboardText
                        )
                        clipboardWasInjected = true
                    }
                }

                // Prepend conversation history for retry sessions so the model
                // sees prior attempts before the new instruction.
                if !retryHistory.isEmpty {
                    let turns = retryHistory.map {
                        "<user>\($0.instruction)</user>\n<assistant>\($0.output)</assistant>"
                    }.joined(separator: "\n")
                    effectiveBody = "<prior_conversation>\n\(turns)\n</prior_conversation>\n\n\(effectiveBody)"
                }

                // Apply word limit to the effective body (including any clipboard content)
                let effectiveWordCount = effectiveBody
                    .split(separator: " ", omittingEmptySubsequences: true).count
                guard effectiveWordCount <= 350 else {
                    guard isCurrentSession(sessionID) else { return }
                    lastTranscription = trimmed
                    if !didPaste {
                        clipboardService.writeToClipboard(trimmed)
                    }
                    let failureSessionID = activeSessionID
                    clearSuccessDismissTiming()
                    state = .failure(reason: .wordLimitExceeded)
                    playFailureSoundIfNeeded()
                    scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: failureSessionID)
                    return
                }

                // LLM call — routes to cloud or local service based on config
                let rewritten: String
                do {
                    rewritten = try await runWithTimeout(
                        nanoseconds: Self.rewriteTimeout,
                        step: "Assistant rewrite"
                    ) { [activeRewriteService] in
                        try await activeRewriteService.generate(
                            prompt: effectiveBody,
                            systemPrompt: systemPrompt
                        )
                    }
                } catch {
                    // Surface rewrite errors visibly. In clipboard-only mode we keep the
                    // raw transcript as a fallback; protected auto-paste preserves the
                    // original clipboard instead.
                    guard isCurrentSession(sessionID) else { return }
                    let errorDescription = (error as? LLMRewriteError)?.errorDescription ?? error.localizedDescription
                    NSLog("TypeLessBuddy: assistant rewrite failed — \(errorDescription)")
                    lastTranscription = trimmed
                    if !didPaste {
                        clipboardService.writeToClipboard(trimmed)
                    }
                    clearSuccessDismissTiming()
                    state = .failure(reason: .modelError("Rewrite failed: \(errorDescription)"))
                    playFailureSoundIfNeeded()
                    scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
                    return
                }

                guard isCurrentSession(sessionID) else { return }
                let elapsed = DispatchTime.now().uptimeNanoseconds - convertingStartedAt
                if elapsed < Self.minimumConvertingDisplayDuration {
                    try? await Task.sleep(
                        nanoseconds: Self.minimumConvertingDisplayDuration - elapsed
                    )
                }

                guard isCurrentSession(sessionID) else { return }
                var syntheticPasteSucceeded = false
                if didPaste {
                    syntheticPasteSucceeded = await pasteWithClipboardProtection(
                        text: rewritten,
                        originalClipboard: originalClipboardForPaste
                    )
                } else {
                    clipboardService.writeToClipboard(rewritten)
                }
                lastTranscription = trimmed          // raw always stored
                lastConvertedTranscription = rewritten
                state = .success(text: rewritten, pasted: syntheticPasteSucceeded, converted: true, clipboardInjected: clipboardWasInjected)
                playSuccessSoundIfNeeded()
                beginSuccessDismissTiming(sessionID: sessionID)
            }
        } catch TranscriptionError.noSpeechDetected {
            guard isCurrentSession(sessionID) else { return }
            clearSuccessDismissTiming()
            state = .failure(reason: .noSpeechDetected)
            playFailureSoundIfNeeded()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        } catch AudioBufferAccumulatorError.emptyBuffers {
            guard isCurrentSession(sessionID) else { return }
            clearSuccessDismissTiming()
            state = .failure(reason: .noSpeechDetected)
            playFailureSoundIfNeeded()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        } catch AudioBufferAccumulatorError.overflow {
            guard isCurrentSession(sessionID) else { return }
            clearSuccessDismissTiming()
            state = .failure(reason: .wordLimitExceeded)
            playFailureSoundIfNeeded()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        } catch {
            guard isCurrentSession(sessionID) else { return }
            clearSuccessDismissTiming()
            state = .failure(reason: .modelError(error.localizedDescription))
            playFailureSoundIfNeeded()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
        }

        if sessionID == activeSessionID {
            transcriptionTask = nil
        }
    }

    private func invalidateActiveSession() {
        requestsPasteOnCompletion = false
        forceLLMNextSession = false
        retryHistory = []
        sessionClipboardSnapshot = nil
        clearSuccessDismissTiming()
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

    private func playStartSoundIfNeeded() {
        guard !shouldMuteSoundEffects else { return }
        soundPlayer.play()
    }

    private func playSuccessSoundIfNeeded() {
        guard !shouldMuteSoundEffects else { return }
        soundPlayer.playSuccess()
    }

    private func playFailureSoundIfNeeded() {
        guard !shouldMuteSoundEffects else { return }
        soundPlayer.playFailure()
    }

    private func pasteWithClipboardProtection(
        text: String,
        originalClipboard: ClipboardSnapshot?
    ) async -> Bool {
        guard let receipt = clipboardService.writeTemporaryText(text) else {
            return false
        }

        let outcome = pasteService.pasteCurrentClipboard()
        guard let originalClipboard else {
            return outcome == .pasted
        }

        if outcome == .pasted {
            try? await Task.sleep(nanoseconds: Self.clipboardRestoreDelay)
        }

        _ = clipboardService.restoreClipboard(from: originalClipboard, ifUnchangedSince: receipt)
        return outcome == .pasted
    }

    private var currentSuccessText: String? {
        guard case .success(let text, _, _, _, _) = state else {
            return nil
        }
        return text
    }

    var isHoldSessionActive: Bool {
        state == .recording && activeActivationOrigin == .hold
    }

    private func refreshSuccessDismissTimer() {
        guard state.isTerminal, case .success = state else { return }
        let start = Date()
        successDismissStartedAt = start
        successDismissDeadline = start.addingTimeInterval(Self.successDismissDurationSeconds)
        scheduleDismissToIdle(
            afterNanoseconds: Self.successDismissDelay,
            sessionID: activeSessionID
        )
    }

    private func beginSuccessDismissTiming(sessionID: UUID) {
        let start = Date()
        successDismissStartedAt = start
        successDismissDeadline = start.addingTimeInterval(Self.successDismissDurationSeconds)
        scheduleDismissToIdle(afterNanoseconds: Self.successDismissDelay, sessionID: sessionID)
    }

    private func clearSuccessDismissTiming() {
        successDismissStartedAt = nil
        successDismissDeadline = nil
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
                self.clearSuccessDismissTiming()
                self.state = .idle
                self.scheduleWhisperModelIdleUnload()
                self.scheduleRewriteModelIdleUnload()
            case .idle, .recording, .processing, .modelDownloading, .modelPrewarming, .converting:
                break
            }
            self.dismissTask = nil
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        !Task.isCancelled && sessionID == activeSessionID
    }

    private func runWithTimeout<T>(
        nanoseconds: UInt64,
        step: String,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw PipelineTimeoutError.stepTimedOut(step)
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw PipelineTimeoutError.stepTimedOut(step)
            }
            return result
        }
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
        case .prewarming(let activeModel) where activeModel == model:
            state = .modelPrewarming(model: activeModel)
        default:
            if case .modelDownloading(let activeModel, _) = state, activeModel == model {
                state = .processing
            } else if case .modelPrewarming(let activeModel) = state, activeModel == model {
                state = .processing
            }
        }
    }

    private func isWhisperModelReady(_ model: WhisperModelChoice) -> Bool {
        switch whisperModelLoadState.phase {
        case .downloading(let active, _) where active == model:
            return false
        case .prewarming(let active) where active == model:
            return false
        case .ready(let loaded) where loaded == model:
            return true
        default:
            return WhisperService.isModelDownloaded(model)
        }
    }

    private func beginModelDownloadGate(for model: WhisperModelChoice) {
        // If a download isn't already running for this model, kick one off.
        if case .downloading(let active, _) = whisperModelLoadState.phase, active == model {
            // Already in progress — just attach observer.
        } else {
            WhisperModelLoadState.shared.startDownload(for: model)
        }

        if case .prewarming(let active) = whisperModelLoadState.phase, active == model {
            state = .modelPrewarming(model: model)
        } else {
            let initialProgress: Double
            if case .downloading(_, let p) = whisperModelLoadState.phase { initialProgress = p } else { initialProgress = 0 }
            state = .modelDownloading(model: model, progress: initialProgress)
        }

        downloadGateCancellable = whisperModelLoadState.phasePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .downloading(let active, let progress) where active == model:
                    self.state = .modelDownloading(model: model, progress: progress)
                case .prewarming(let active) where active == model:
                    self.state = .modelPrewarming(model: model)
                case .ready(let active) where active == model:
                    self.downloadGateCancellable = nil
                    self.state = .idle
                case .failed(let active, let message) where active == model:
                    self.downloadGateCancellable = nil
                    let gateID = UUID()
                    self.activeSessionID = gateID
                    self.state = .failure(reason: .modelError(message))
                    self.scheduleDismissToIdle(afterNanoseconds: 3_000_000_000, sessionID: gateID)
                default:
                    break
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
