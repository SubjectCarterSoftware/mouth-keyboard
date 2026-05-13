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
    private static let cloudRewritePromptWordLimit = 4_000
    private static let clipboardRestoreDelay: UInt64 = 150_000_000
    private static let selectedTextCaptureTimeout: UInt64 = 120_000_000
    private static let selectedTextCapturePollInterval: UInt64 = 15_000_000
    private static let successDismissDelay: UInt64 = 10_000_000_000
    private static let successDismissDurationSeconds = TimeInterval(successDismissDelay) / 1_000_000_000

    var onPastePermissionNeeded: () -> Void = {}

    private var requestsPasteOnCompletion = false
    private var forceLLMNextSession = false
    private var restartFromSuccessNextSession = false
    private var retryHistory: [(instruction: String, output: String)] = []
    private var activeSessionID = UUID()
    private var activeActivationOrigin: ActivationOrigin?
    private var transcriptionTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var feedbackClearTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var sessionClipboardSnapshot: ClipboardSnapshot?
    private var initialSelectedText: String?
    private var finalSelectedText: String?
    private var initialSelectedTextCaptureTask: Task<String?, Never>?
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

    /// Word-count ceiling for the rewrite prompt body, matched to the active service.
    /// Mirrors the cloud-vs-local check in activeRewriteService so the limit always
    /// corresponds to the model that will actually run.
    private var effectivePromptWordLimit: Int {
        let config = preferences.cloudLLMConfig
        guard config.isEnabled, !config.modelID.isEmpty else {
            return preferences.rewriteModelTier.rewritePromptWordLimit
        }
        guard let apiKey = CloudLLMKeychain.loadAPIKey(for: config.provider), !apiKey.isEmpty else {
            return preferences.rewriteModelTier.rewritePromptWordLimit
        }
        return Self.cloudRewritePromptWordLimit
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
        recoveryFeedback = nil
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

        Task { [weak self] in
            guard let self else { return }
            _ = await self.pasteWithClipboardProtection(text: successText)
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
        restartFromSuccessNextSession = true
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
        initialSelectedText = nil
        finalSelectedText = nil
        initialSelectedTextCaptureTask?.cancel()
        initialSelectedTextCaptureTask = nil
        activeActivationOrigin = origin
        bufferAccumulator.reset()
        state = .recording
        beginWhisperModelWarmup()
        beginRewriteModelWarmup()
        beginInitialSelectedTextCapture(sessionID: activeSessionID)

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
            if let initialSelectedTextCaptureTask, initialSelectedText == nil {
                initialSelectedText = await initialSelectedTextCaptureTask.value
            }
            guard isCurrentSession(sessionID) else { return }
            finalSelectedText = await captureSelectedText()

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
            let trimmed = TriggerTranscriptParser.normalizeTranscript(text)
            let processed = TextReplacementEngine.applyReplacements(
                to: trimmed,
                replacements: preferences.activeDictionaryData.replacements
            )
            let triggerNames = preferences.activeTriggerProfile.allCanonicalNames

            guard isCurrentSession(sessionID) else { return }
            guard !processed.isEmpty else {
                throw TranscriptionError.noSpeechDetected
            }

            let detection = TriggerTranscriptParser.detect(transcript: processed, triggerNames: triggerNames)
            let clipboardSnapshot = sessionClipboardSnapshot
            let wasForcedRetrySession = forceLLMNextSession
            let restartedFromSuccess = restartFromSuccessNextSession
            let isRetrySession = wasForcedRetrySession || restartedFromSuccess || !retryHistory.isEmpty
            let shouldConvert: Bool
            switch detection {
            case .noTrigger:
                shouldConvert = forceLLMNextSession
            case .triggered:
                shouldConvert = true
            }
            forceLLMNextSession = false
            restartFromSuccessNextSession = false

            if !shouldConvert {
                let didPaste = shouldPasteOnSuccessfulFinish
                requestsPasteOnCompletion = false
                lastTranscription = processed
                var syntheticPasteSucceeded = false
                if didPaste {
                    syntheticPasteSucceeded = await pasteWithClipboardProtection(text: processed)
                } else {
                    clipboardService.writeToClipboard(processed)
                }
                state = .success(
                    text: processed,
                    pasted: syntheticPasteSucceeded,
                    converted: false,
                    noMatchPassthrough: false
                )
                playSuccessSoundIfNeeded()
                beginSuccessDismissTiming(sessionID: sessionID)
            } else {
                let didPaste = shouldPasteOnSuccessfulFinish
                requestsPasteOnCompletion = false

                guard isCurrentSession(sessionID) else { return }
                state = .converting
                let convertingStartedAt = DispatchTime.now().uptimeNanoseconds
                let assistantName = preferences.activeTriggerProfile.activePrimary
                let systemPrompt = LLMRewriteService.resolveAssistantSystemPrompt(
                    promptTemplate: preferences.rewriteSystemPromptPrefix,
                    assistantName: assistantName
                )

                // Route external text context into the rewrite prompt when requested.
                let externalTextSources = normalizedExternalTextSources(
                    selectedText: await preferredSelectedText(),
                    clipboardText: clipboardSnapshot?.plainText,
                    lastTranscription: isRetrySession ? nil : lastTranscription
                )
                let routingContext = ExternalTextSourceContext(
                    selectedTextAvailable: externalTextSources.selectedText != nil,
                    clipboardTextAvailable: externalTextSources.clipboardText != nil,
                    lastTranscriptionAvailable: externalTextSources.lastTranscription != nil
                )
                let routedSource: ExternalTextSource

                if routingContext.hasAvailableSource {
                    routedSource = try await runWithTimeout(
                        nanoseconds: Self.clipboardIntentTimeout,
                        step: "External text source routing"
                    ) { [llmRewriteService] in
                        await ExternalTextSourceClassifier.classify(
                            message: processed,
                            availableSources: routingContext,
                            using: llmRewriteService
                        )
                    }

                    guard isCurrentSession(sessionID) else { return }
                } else {
                    routedSource = .none
                }

                var promptConfiguration = buildRewritePromptBody(
                    dictatedContent: processed,
                    sources: externalTextSources,
                    route: routedSource
                )
                var externalTextWasInjected = promptConfiguration.externalTextInjected
                var effectiveRoute = promptConfiguration.routeUsed
                var effectiveBody = prependRetryHistory(to: promptConfiguration.body)

                while Self.rewriteWordCount(for: effectiveBody) > effectivePromptWordLimit,
                      let reducedRoute = reducedRouteForPromptLimit(from: effectiveRoute) {
                    promptConfiguration = buildRewritePromptBody(
                        dictatedContent: processed,
                        sources: externalTextSources,
                        route: reducedRoute
                    )
                    externalTextWasInjected = promptConfiguration.externalTextInjected
                    effectiveRoute = promptConfiguration.routeUsed
                    effectiveBody = prependRetryHistory(to: promptConfiguration.body)
                }

                // Apply the per-model rewrite prompt limit to the final effective body.
                let wordLimit = effectivePromptWordLimit
                let effectiveWordCount = Self.rewriteWordCount(for: effectiveBody)
                guard effectiveWordCount <= wordLimit else {
                    guard isCurrentSession(sessionID) else { return }
                    lastTranscription = processed
                    if !didPaste {
                        clipboardService.writeToClipboard(processed)
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
                    let promptBody = effectiveBody
                    rewritten = try await runWithTimeout(
                        nanoseconds: Self.rewriteTimeout,
                        step: "Assistant rewrite"
                    ) { [activeRewriteService] in
                        try await activeRewriteService.generate(
                            prompt: promptBody,
                            systemPrompt: systemPrompt
                        )
                    }
                } catch {
                    // Surface rewrite errors visibly. Clipboard-only mode keeps the raw
                    // transcript as fallback; protected auto-paste preserves the original
                    // clipboard instead.
                    guard isCurrentSession(sessionID) else { return }
                    let errorDescription = (error as? LLMRewriteError)?.errorDescription ?? error.localizedDescription
                    NSLog("TypeLessBuddy: assistant rewrite failed — \(errorDescription)")
                    lastTranscription = processed
                    if !didPaste {
                        clipboardService.writeToClipboard(processed)
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
                    syntheticPasteSucceeded = await pasteWithClipboardProtection(text: rewritten)
                } else {
                    clipboardService.writeToClipboard(rewritten)
                }
                lastTranscription = processed
                lastConvertedTranscription = rewritten
                state = .success(
                    text: rewritten,
                    pasted: syntheticPasteSucceeded,
                    converted: true,
                    externalTextInjected: externalTextWasInjected
                )
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
        restartFromSuccessNextSession = false
        retryHistory = []
        sessionClipboardSnapshot = nil
        initialSelectedText = nil
        finalSelectedText = nil
        initialSelectedTextCaptureTask?.cancel()
        initialSelectedTextCaptureTask = nil
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

    private func pasteWithClipboardProtection(text: String) async -> Bool {
        let originalClipboard = shouldRestorePreviousClipboardAfterAutoPaste
            ? clipboardService.snapshotCurrentClipboard()
            : nil
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

    private func beginInitialSelectedTextCapture(sessionID: UUID) {
        guard isPostEventPermissionGranted else { return }

        initialSelectedTextCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return nil }
            let capturedText = await self.captureSelectedText()
            guard self.isCurrentSession(sessionID) else { return capturedText }
            self.initialSelectedText = capturedText
            return capturedText
        }
    }

    private func preferredSelectedText() async -> String? {
        if let finalSelectedText {
            return finalSelectedText
        }

        if let initialSelectedText {
            return initialSelectedText
        }

        guard let initialSelectedTextCaptureTask else {
            return nil
        }

        let capturedText = await initialSelectedTextCaptureTask.value
        if let capturedText, capturedText != initialSelectedText {
            initialSelectedText = capturedText
        }
        return capturedText
    }

    private func captureSelectedText() async -> String? {
        guard isPostEventPermissionGranted else { return nil }

        let originalClipboard = clipboardService.snapshotCurrentClipboard()
        guard pasteService.copySelectedTextToClipboard() == .dispatched else {
            return nil
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + Self.selectedTextCaptureTimeout
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let currentClipboard = clipboardService.snapshotCurrentClipboard()
            if currentClipboard.changeCount != originalClipboard.changeCount {
                let copiedText = currentClipboard.plainText?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let receipt = ClipboardWriteReceipt(changeCount: currentClipboard.changeCount)
                _ = clipboardService.restoreClipboard(
                    from: originalClipboard,
                    ifUnchangedSince: receipt
                )
                if let copiedText, !copiedText.isEmpty {
                    return copiedText
                }
                return nil
            }

            try? await Task.sleep(nanoseconds: Self.selectedTextCapturePollInterval)
        }

        return nil
    }

    private var currentSuccessText: String? {
        guard case .success(let text, _, _, _, _) = state else {
            return nil
        }
        return text
    }

    private static func rewriteWordCount(for body: String) -> Int {
        body.split(whereSeparator: { $0.isWhitespace }).count
    }

    private func normalizedExternalText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private struct ExternalTextInputs {
        let selectedText: String?
        let clipboardText: String?
        let lastTranscription: String?

        var route: ExternalTextSource {
            var route: ExternalTextSource = .none

            if selectedText != nil {
                route.insert(.selectedText)
            }

            if clipboardText != nil {
                route.insert(.clipboard)
            }

            if lastTranscription != nil {
                route.insert(.lastTranscription)
            }

            return route
        }

        func filtered(by route: ExternalTextSource) -> ExternalTextInputs {
            ExternalTextInputs(
                selectedText: route.contains(.selectedText) ? selectedText : nil,
                clipboardText: route.contains(.clipboard) ? clipboardText : nil,
                lastTranscription: route.contains(.lastTranscription) ? lastTranscription : nil
            )
        }
    }

    private func normalizedExternalTextSources(
        selectedText: String?,
        clipboardText: String?,
        lastTranscription: String?
    ) -> ExternalTextInputs {
        let normalizedSelectedText = normalizedExternalText(selectedText)
        let normalizedLastTranscription = normalizedExternalText(lastTranscription)
        let normalizedClipboardText = normalizedExternalText(clipboardText)

        var seenTexts = Set<String>()

        let dedupedSelectedText = dedupedExternalText(normalizedSelectedText, seenTexts: &seenTexts)
        let dedupedLastTranscription = dedupedExternalText(normalizedLastTranscription, seenTexts: &seenTexts)
        let dedupedClipboardText = dedupedExternalText(normalizedClipboardText, seenTexts: &seenTexts)

        return ExternalTextInputs(
            selectedText: dedupedSelectedText,
            clipboardText: dedupedClipboardText,
            lastTranscription: dedupedLastTranscription
        )
    }

    private func dedupedExternalText(_ text: String?, seenTexts: inout Set<String>) -> String? {
        guard let text else { return nil }
        guard seenTexts.insert(text).inserted else { return nil }
        return text
    }

    private func reducedRouteForPromptLimit(from route: ExternalTextSource) -> ExternalTextSource? {
        guard let primaryTarget = route.primaryRewriteTarget else {
            return nil
        }

        for supportingSource in [ExternalTextSource.clipboard, .lastTranscription, .selectedText] {
            guard supportingSource != primaryTarget, route.contains(supportingSource) else {
                continue
            }

            var reducedRoute = route
            reducedRoute.remove(supportingSource)
            return reducedRoute.hasAnySource ? reducedRoute : nil
        }

        return nil
    }

    private func buildRewritePromptBody(
        dictatedContent: String,
        sources: ExternalTextInputs,
        route: ExternalTextSource
    ) -> (body: String, externalTextInjected: Bool, routeUsed: ExternalTextSource) {
        let promptSources = sources.filtered(by: route)
        let effectiveRoute = promptSources.route

        guard effectiveRoute.hasAnySource else {
            return (dictatedContent, false, .none)
        }

        return (
            ExternalTextPromptBuilder.buildBody(
                dictatedContent: dictatedContent,
                selectedText: promptSources.selectedText,
                clipboardText: promptSources.clipboardText,
                lastTranscription: promptSources.lastTranscription
            ),
            true,
            effectiveRoute
        )
    }

    private func prependRetryHistory(to body: String) -> String {
        guard !retryHistory.isEmpty else { return body }

        let turns = retryHistory.map {
            "<user>\($0.instruction)</user>\n<assistant>\($0.output)</assistant>"
        }.joined(separator: "\n")
        return "<prior_conversation>\n\(turns)\n</prior_conversation>\n\n\(body)"
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
        feedbackClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
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
