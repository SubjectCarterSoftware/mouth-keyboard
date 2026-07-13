import AppKit
import Combine
import Foundation
import MLXLMCommon

// `ActivationSoundPlayer`, the `Sleeping`/`SystemSleeper` clock abstraction, and
// the `ReadinessProviding`/`WhisperModelLoadStateProviding` adapter protocols
// live in `ActivationSupport.swift`. The transcription/rewrite pipeline, model
// warmup, and note/history capture are split into `ActivationStore+Pipeline`,
// `ActivationStore+Models`, and `ActivationStore+Notes`.

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
        localRewriteService: LocalRewriteService.shared,
        noteCaptureService: NoteCaptureService(),
        historyCaptureService: HistoryCaptureService(),
        clipboardService: ClipboardService(),
        pasteService: PasteService(),
        bufferAccumulator: AudioBufferAccumulator(),
        resetSessionMonitoring: {}
    )

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var recoveryFeedback: RecordingState.RecoveryFeedback?
    @Published private(set) var lastTranscription: String?
    @Published private(set) var lastRewrittenTranscription: String?
    @Published private(set) var successDismissStartedAt: Date?
    @Published private(set) var successDismissDeadline: Date?
    @Published private(set) var successNoteSaveState: SuccessNoteSaveState?

    // These dependencies are `internal` (not `private`) so the `+Pipeline`-style
    // extensions in ActivationStore+Models / +Notes / +Rewrite can reach them.
    let preferences: ShellPreferences
    private let readinessProvider: any ReadinessProviding
    let whisperModelLoadState: any WhisperModelLoadStateProviding
    let whisperService: any WhisperTranscribing
    let localRewriteService: any Rewriting
    let contextRouter: any AssistantContextRouting
    let noteCaptureService: any NoteCapturing
    let historyCaptureService: any HistoryCapturing
    private let clipboardService: ClipboardService
    private let pasteService: any PasteServicing
    private let dateProvider: () -> Date
    private let sleeper: any Sleeping
    private let resetSessionMonitoring: @MainActor () -> Void
    let bufferAccumulator: AudioBufferAccumulator
    var soundPlayer: ActivationSoundPlayer = .init()
    var finalizeAudioCaptureBeforeTranscription: @MainActor () async -> Void = {}
    private static let maxRecordingDuration: UInt64 = 15 * 60 * 1_000_000_000 // 15 minutes
    private static let minimumTranscriptionAudioDuration: TimeInterval = 1.0
    private static let appendedTrailingSilenceDuration: TimeInterval = 0.35
    private static let minimumRewritingDisplayDuration: UInt64 = 200_000_000
    static let whisperModelIdleUnloadDelay: UInt64 = WhisperService.idleUnloadDelayNanoseconds
    static let rewriteModelIdleUnloadDelay: UInt64 = LocalRewriteService.idleUnloadDelayNanoseconds
    private static let whisperPrepareTimeout: UInt64 = 20_000_000_000
    // Transcription time grows with audio length, so the timeout is a hang-guard
    // that scales with duration rather than a flat ceiling that long recordings
    // would falsely trip. Base covers model warmup + short clips; the per-second
    // allowance is generous enough for slower (e.g. Intel) hardware.
    private static let whisperTranscriptionBaseTimeout: UInt64 = 45_000_000_000
    private static let whisperTranscriptionTimeoutPerAudioSecond: UInt64 = 4_000_000_000
    private static let whisperSampleRate: Double = 16_000
    // Sized to the 9B tier at near-cap input (~28k tokens), measured at ~90s end-to-end.
    private static let rewriteTimeout: UInt64 = 120_000_000_000
    static let minimumDirectAssistantPromptWordLimit = 1_500
    private static let lastTranscriptionContextMaxAge: TimeInterval = 30 * 60
    private static let clipboardRestoreDelay: UInt64 = 150_000_000
    // Copy is delivered asynchronously to the foreground app. 120 ms was short
    // enough to miss valid selections when the target app or macOS was briefly
    // busy, leaving an otherwise explicit selection request without its source.
    private static let selectedTextCaptureTimeout: UInt64 = 500_000_000
    private static let selectedTextCapturePollInterval: UInt64 = 15_000_000
    private static let minimumStartSoundInterval: TimeInterval = 0.15
    private static let successDismissDelay: UInt64 = 10_000_000_000
    private static let successDismissDurationSeconds = TimeInterval(successDismissDelay) / 1_000_000_000
    static let noteTitleGenerationTimeout: UInt64 = 8_000_000_000
    static let noteTitleSystemPrompt = """
    You create concise note titles.
    Return only a short title of 2 to 6 words.
    Do not use quotes, markdown, labels, emojis, or trailing punctuation.
    Prefer concrete words already present in the content.
    """

    var onPastePermissionNeeded: () -> Void = {}

    private struct SelectedClipboardCapture: Equatable {
        let text: String?
        let imageContent: ClipboardImageContent?

        static let empty = Self(text: nil, imageContent: nil)
    }

    private var requestsPasteOnCompletion = false
    private var activeSessionID = UUID()
    private var activeActivationOrigin: ActivationOrigin?
    private var transcriptionTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var feedbackClearTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var sessionClipboardSnapshot: ClipboardSnapshot?
    private var lastTranscriptionCapturedAt: Date?
    private var currentSuccessNoteContent: NoteCaptureContent?
    private var initialSelectedCapture: SelectedClipboardCapture?
    private var finalSelectedCapture: SelectedClipboardCapture?
    private var initialSelectedCaptureTask: Task<SelectedClipboardCapture, Never>?
    private var downloadGateCancellable: AnyCancellable?
    private var lastStartSoundAt: Date?

    convenience init(preferences: ShellPreferences, readinessStore: ReadinessStore) {
        self.init(
            preferences: preferences,
            readinessProvider: readinessStore,
            whisperModelLoadState: WhisperModelLoadState.shared,
            whisperService: WhisperService(),
            noteCaptureService: NoteCaptureService(),
            historyCaptureService: HistoryCaptureService(),
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
        localRewriteService: any Rewriting = LocalRewriteService.shared,
        contextRouter: any AssistantContextRouting = LocalModelAssistantContextRouter.shared,
        noteCaptureService: any NoteCapturing = NoteCaptureService(),
        historyCaptureService: any HistoryCapturing = HistoryCaptureService(),
        clipboardService: ClipboardService = ClipboardService(),
        pasteService: any PasteServicing = PasteService(),
        bufferAccumulator: AudioBufferAccumulator = AudioBufferAccumulator(),
        dateProvider: @escaping () -> Date = { Date() },
        sleeper: any Sleeping = SystemSleeper(),
        resetSessionMonitoring: @escaping @MainActor () -> Void = {}
    ) {
        self.preferences = preferences
        self.readinessProvider = readinessProvider
        self.whisperModelLoadState = whisperModelLoadState
        self.whisperService = whisperService
        self.localRewriteService = localRewriteService
        self.contextRouter = contextRouter
        self.noteCaptureService = noteCaptureService
        self.historyCaptureService = historyCaptureService
        self.clipboardService = clipboardService
        self.pasteService = pasteService
        self.bufferAccumulator = bufferAccumulator
        self.dateProvider = dateProvider
        self.sleeper = sleeper
        self.resetSessionMonitoring = resetSessionMonitoring
    }

    /// Returns the cloud service when cloud LLM is enabled, otherwise the local on-device service.
    /// Rebuilds the cloud service each call to pick up any config changes between sessions.
    private var activeRewriteService: any Rewriting {
        let config = preferences.cloudLLMConfig
        guard config.isEnabled, !config.modelID.isEmpty else {
            return localRewriteService
        }
        guard let apiKey = CloudLLMKeychain.loadAPIKey(for: config.provider), !apiKey.isEmpty else {
            return localRewriteService
        }
        return CloudRewriteService(config: config, apiKey: apiKey)
    }

    // MARK: - Public API

    func arm() {
        guard state != .recording else { return }
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
                || state == .rewriting
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

    /// Copies the last rewritten transcription to the clipboard.
    func copyLastRewrittenTranscription() {
        if let text = lastRewrittenTranscription {
            clipboardService.writeToClipboard(text)
        }
    }

    func copyCurrentSuccessResult() {
        guard let successText = currentSuccessText else { return }
        clipboardService.writeToClipboard(successText)
        refreshSuccessDismissTimer()
    }

    func requestCurrentSessionResultAsNote() {
        switch state {
        case .recording, .processing, .rewriting:
            guard successNoteSaveState?.canQueueSave == true else { return }
            successNoteSaveState = .queued
        case .success:
            saveCurrentSuccessResultAsNote()
        case .idle, .modelDownloading, .modelPrewarming, .failure:
            return
        }
    }

    func saveCurrentSuccessResultAsNote() {
        guard currentSuccessText != nil else { return }
        guard let noteContent = currentSuccessNoteContent else { return }
        guard successNoteSaveState?.canStartSave == true else { return }

        let configuration = preferences.assistantNoteConfiguration
        guard configuration.isConfigured else {
            successNoteSaveState = .disabledMissingConfiguration
            refreshSuccessDismissTimer()
            return
        }

        successNoteSaveState = .saving
        refreshSuccessDismissTimer()

        Task { [weak self] in
            guard let self else { return }
            let didSave = await self.saveNoteIfPossible(content: noteContent)
            guard case .success = self.state else { return }

            self.successNoteSaveState = didSave ? .saved : .available
            if didSave {
                self.refreshSuccessDismissTimer()
                self.playNoteSavedSoundIfNeeded()
            }
        }
    }

    func dismissCurrentSuccess() {
        guard case .success = state else { return }

        dismissTask?.cancel()
        dismissTask = nil
        clearSuccessDismissTiming()
        successNoteSaveState = nil
        currentSuccessNoteContent = nil
        recoveryFeedback = nil
        state = .idle
        scheduleWhisperModelIdleUnload()
        scheduleRewriteModelIdleUnload()
    }

    /// Append from success: re-enters recording and pastes the new result after the existing paste.
    func appendFromSuccess() {
        guard state.isSuccess else { return }
        requestsPasteOnCompletion = true
        _ = beginRecording(origin: .toggle)
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
            await self.finalizeAudioCaptureBeforeTranscription()
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
            successNoteSaveState = nil
            currentSuccessNoteContent = nil
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
        successNoteSaveState = nil
        currentSuccessNoteContent = nil
        sessionClipboardSnapshot = clipboardService.snapshotCurrentClipboard()
        initialSelectedCapture = nil
        finalSelectedCapture = nil
        initialSelectedCaptureTask?.cancel()
        initialSelectedCaptureTask = nil
        activeActivationOrigin = origin
        bufferAccumulator.reset()
        successNoteSaveState = configuredSuccessNoteSaveState(noteWasSaved: false)
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

    /// Orchestrates the post-recording pipeline: transcribe, route on trigger
    /// detection, then deliver either the raw transcript or the rewritten result.
    /// Each step is an extracted private method; the failure handling for thrown
    /// pipeline errors stays here so all terminal-state transitions live together.
    private func finalizeSession(sessionID: UUID) async {
        do {
            guard isCurrentSession(sessionID) else { return }
            guard let processed = try await transcribeForSession(sessionID: sessionID) else { return }

            let triggerNames = preferences.activeTriggerProfile.allCanonicalNames
            let detection = TriggerTranscriptParser.detect(transcript: processed, triggerNames: triggerNames)
            let shouldRewrite: Bool
            switch detection {
            case .noTrigger:
                shouldRewrite = false
            case .triggered:
                shouldRewrite = true
            }

            if !shouldRewrite {
                await deliverPassthroughSuccess(processed: processed, sessionID: sessionID)
            } else {
                let clipboardSnapshot = sessionClipboardSnapshot
                guard await rewriteAndDeliver(
                    processed: processed,
                    clipboardSnapshot: clipboardSnapshot,
                    sessionID: sessionID
                ) else {
                    return
                }
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

    /// Prepares the Whisper model, captures the selected-text context, transcribes
    /// the recorded audio, and applies dictionary replacements. Returns the
    /// processed transcript, or `nil` if the session was superseded mid-flight
    /// (mirroring the original early-`return` guards). Pipeline errors are thrown
    /// for `finalizeSession` to handle.
    private func transcribeForSession(sessionID: UUID) async throws -> String? {
        if let initialSelectedCaptureTask, initialSelectedCapture == nil {
            initialSelectedCapture = await initialSelectedCaptureTask.value
        }
        guard isCurrentSession(sessionID) else { return nil }
        finalSelectedCapture = await captureSelectedContent()

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
        guard isCurrentSession(sessionID) else { return nil }

        let samples = AudioBufferAccumulator.prepareForTranscription(
            try bufferAccumulator.convertToWhisperFormat(),
            minimumDuration: Self.minimumTranscriptionAudioDuration,
            trailingSilenceDuration: Self.appendedTrailingSilenceDuration
        )
        let text = try await runWithTimeout(
            nanoseconds: Self.whisperTranscriptionTimeout(forSampleCount: samples.count),
            step: "Whisper transcription"
        ) { [whisperService] in
            try await whisperService.transcribe(samples: samples)
        }
        let trimmed = TriggerTranscriptParser.normalizeTranscript(text)
        let processed = TextReplacementEngine.applyReplacements(
            to: trimmed,
            replacements: preferences.activeDictionaryData.replacements
        )

        guard isCurrentSession(sessionID) else { return nil }
        guard !processed.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }

        return processed
    }

    /// Delivers the raw transcript (no trigger matched): copy or auto-paste, set
    /// the success state, persist history, and start the dismiss countdown.
    private func deliverPassthroughSuccess(processed: String, sessionID: UUID) async {
        let didPaste = shouldPasteOnSuccessfulFinish
        requestsPasteOnCompletion = false
        recordLastTranscription(processed)
        let noteContent = noteCaptureContent(
            rawTranscription: processed,
            assistantOutput: nil
        )
        let queuedNoteWasSaved = successNoteSaveState == .queued
            ? await saveNoteIfPossible(content: noteContent)
            : false
        currentSuccessNoteContent = noteContent
        var syntheticPasteSucceeded = false
        if didPaste {
            syntheticPasteSucceeded = await pasteWithClipboardProtection(text: processed)
        } else {
            clipboardService.writeToClipboard(processed)
        }
        successNoteSaveState = configuredSuccessNoteSaveState(noteWasSaved: queuedNoteWasSaved)
        state = .success(
            text: processed,
            pasted: syntheticPasteSucceeded,
            rewritten: false,
            noMatchPassthrough: false
        )
        persistHistoryIfEnabled(
            HistoryCaptureContent(
                rawTranscription: processed,
                assistantOutput: nil
            )
        )
        if queuedNoteWasSaved {
            playSuccessThenNoteSavedSoundIfNeeded()
        } else {
            playSuccessSoundIfNeeded()
        }
        beginSuccessDismissTiming(sessionID: sessionID)
    }

    /// Runs the rewrite branch (a trigger matched): builds the prompt, calls the
    /// active rewrite service, and delivers the rewritten result. Returns `true`
    /// when the caller should fall through to its tail cleanup, or `false` when
    /// the session bailed early — preserving the original early-`return` semantics
    /// that skip that cleanup (session superseded, word limit, or rewrite error).
    private func rewriteAndDeliver(
        processed: String,
        clipboardSnapshot: ClipboardSnapshot?,
        sessionID: UUID
    ) async -> Bool {
        let didPaste = shouldPasteOnSuccessfulFinish
        requestsPasteOnCompletion = false

        guard isCurrentSession(sessionID) else { return false }
        state = .rewriting
        let rewritingStartedAt = DispatchTime.now().uptimeNanoseconds
        let assistantName = preferences.activeTriggerProfile.activePrimary
        let systemPrompt = LocalRewriteService.resolveAssistantSystemPrompt(
            promptTemplate: preferences.rewriteSystemPromptPrefix,
            assistantName: assistantName
        )
        let noteIntent = AssistantNoteIntentClassifier.classify(
            message: processed,
            matchedAlias: assistantName
        )
        if shouldAutomaticallySaveAssistantNote(classification: noteIntent),
           successNoteSaveState?.canQueueSave == true {
            successNoteSaveState = .queued
        }
        let dictatedAssistantPrompt = noteIntent.sanitizedPrompt

        // Route external text context into the rewrite prompt when requested.
        let externalTextInputs = validatedExternalTextInputs(
            selectedText: await preferredSelectedText(),
            clipboardText: clipboardSnapshot?.plainText,
            lastTranscription: freshLastTranscriptionForRouting(),
            selectedImageContent: await preferredSelectedImageContent(),
            clipboardImageContent: clipboardSnapshot?.imageContent
        )
        let routingContext = ExternalTextSourceContext(
            selectedTextAvailable: externalTextInputs.selectedText != nil
                || externalTextInputs.selectedImageContent != nil,
            clipboardTextAvailable: externalTextInputs.clipboardText != nil
                || externalTextInputs.clipboardImageContent != nil,
            lastTranscriptionAvailable: externalTextInputs.lastTranscription != nil
        )
        let routingDecision: AssistantContextRoutingDecision
        do {
            routingDecision = try await runWithTimeout(
                nanoseconds: Self.rewriteTimeout,
                step: "Context routing"
            ) { [contextRouter] in
                try await contextRouter.route(
                    request: dictatedAssistantPrompt,
                    availableSources: routingContext
                )
            }
        } catch {
            // Do not silently continue with a direct prompt if the narrow classifier
            // fails. That recreates the original failure mode: the final model would
            // receive no selected/captured text and could only guess what to edit.
            guard isCurrentSession(sessionID) else { return false }
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("TypeLessBuddy: context routing failed — \(errorDescription)")
            recordLastTranscription(processed)
            if !didPaste {
                clipboardService.writeToClipboard(processed)
            }
            clearSuccessDismissTiming()
            state = .failure(reason: .modelError("Context routing failed: \(errorDescription)"))
            playFailureSoundIfNeeded()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
            return false
        }

        let promptConfiguration = buildRewritePromptBody(
            dictatedContent: dictatedAssistantPrompt,
            inputs: externalTextInputs,
            decision: routingDecision
        )
        let routingDecisionForPrompt = promptConfiguration.decisionUsed
        let externalTextWasInjected = promptConfiguration.externalTextInjected
        let effectiveBody = promptConfiguration.body
        let referencedNoteContexts = noteReferencedContexts(
            from: routingDecisionForPrompt.matchedSources,
            inputs: externalTextInputs
        )
        let assistantImages = assistantInputImages(
            from: routingDecisionForPrompt.matchedSources,
            inputs: externalTextInputs
        )

        // Direct assistant prompts keep the historical 1500-word floor,
        // while context-injected prompts still use the stricter model limit.
        let wordLimit = rewritePromptWordLimit(
            for: routingDecisionForPrompt,
            externalTextInjected: externalTextWasInjected
        )
        let effectiveWordCount = Self.rewriteWordCount(for: effectiveBody)
        guard effectiveWordCount <= wordLimit else {
            guard isCurrentSession(sessionID) else { return false }
            recordLastTranscription(processed)
            if !didPaste {
                clipboardService.writeToClipboard(processed)
            }
            let failureSessionID = activeSessionID
            clearSuccessDismissTiming()
            state = .failure(reason: .wordLimitExceeded)
            playFailureSoundIfNeeded()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: failureSessionID)
            return false
        }

        // LLM call — routes to cloud or local service based on config
        let rewritten: String
        do {
            let promptBody = effectiveBody
            if !preferences.cloudLLMConfig.isEnabled {
                await configureLocalRewriteServiceSelection()
            }
            rewritten = try await runWithTimeout(
                nanoseconds: Self.rewriteTimeout,
                step: "Assistant rewrite"
            ) { [activeRewriteService] in
                try await activeRewriteService.generate(
                    prompt: promptBody,
                    systemPrompt: systemPrompt,
                    images: assistantImages
                )
            }
        } catch {
            // Surface rewrite errors visibly. Clipboard-only mode keeps the raw
            // transcript as fallback; protected auto-paste preserves the original
            // clipboard instead.
            guard isCurrentSession(sessionID) else { return false }
            let errorDescription = (error as? RewriteError)?.errorDescription ?? error.localizedDescription
            NSLog("TypeLessBuddy: assistant rewrite failed — \(errorDescription)")
            recordLastTranscription(processed)
            if !didPaste {
                clipboardService.writeToClipboard(processed)
            }
            clearSuccessDismissTiming()
            state = .failure(reason: .modelError("Rewrite failed: \(errorDescription)"))
            playFailureSoundIfNeeded()
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)
            return false
        }

        guard isCurrentSession(sessionID) else { return false }
        let elapsed = DispatchTime.now().uptimeNanoseconds - rewritingStartedAt
        if elapsed < Self.minimumRewritingDisplayDuration {
            try? await Task.sleep(
                nanoseconds: Self.minimumRewritingDisplayDuration - elapsed
            )
        }

        guard isCurrentSession(sessionID) else { return false }
        let noteContent = noteCaptureContent(
            rawTranscription: processed,
            referencedContexts: referencedNoteContexts,
            assistantOutput: rewritten
        )
        let queuedNoteWasSaved = successNoteSaveState == .queued
            ? await saveNoteIfPossible(content: noteContent)
            : false
        var syntheticPasteSucceeded = false
        if didPaste {
            syntheticPasteSucceeded = await pasteWithClipboardProtection(text: rewritten)
        } else {
            clipboardService.writeToClipboard(rewritten)
        }
        recordLastTranscription(processed)
        lastRewrittenTranscription = rewritten
        currentSuccessNoteContent = noteContent
        successNoteSaveState = configuredSuccessNoteSaveState(
            noteWasSaved: queuedNoteWasSaved
        )
        state = .success(
            text: rewritten,
            pasted: syntheticPasteSucceeded,
            rewritten: true,
            externalTextInjected: externalTextWasInjected
        )
        persistHistoryIfEnabled(
            HistoryCaptureContent(
                rawTranscription: processed,
                assistantOutput: rewritten
            )
        )
        if queuedNoteWasSaved {
            playSuccessThenNoteSavedSoundIfNeeded()
        } else {
            playSuccessSoundIfNeeded()
        }
        beginSuccessDismissTiming(sessionID: sessionID)
        return true
    }

    private func invalidateActiveSession() {
        requestsPasteOnCompletion = false
        sessionClipboardSnapshot = nil
        successNoteSaveState = nil
        currentSuccessNoteContent = nil
        initialSelectedCapture = nil
        finalSelectedCapture = nil
        initialSelectedCaptureTask?.cancel()
        initialSelectedCaptureTask = nil
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
        let now = dateProvider()
        if let lastStartSoundAt,
           now.timeIntervalSince(lastStartSoundAt) < Self.minimumStartSoundInterval {
            return
        }
        lastStartSoundAt = now
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

    private func playNoteSavedSoundIfNeeded() {
        guard !shouldMuteSoundEffects else { return }
        soundPlayer.playNoteSaved()
    }

    private func playSuccessThenNoteSavedSoundIfNeeded() {
        guard !shouldMuteSoundEffects else { return }
        soundPlayer.playSuccessThenNoteSaved()
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

        initialSelectedCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return .empty }
            let capturedContent = await self.captureSelectedContent()
            guard self.isCurrentSession(sessionID) else { return capturedContent }
            self.initialSelectedCapture = capturedContent
            return capturedContent
        }
    }

    private func preferredSelectedText() async -> String? {
        if let capture = finalSelectedCapture, let text = capture.text {
            return text
        }

        if let capture = initialSelectedCapture, let text = capture.text {
            return text
        }

        guard let initialSelectedCaptureTask else {
            return nil
        }

        let capturedContent = await initialSelectedCaptureTask.value
        if capturedContent != initialSelectedCapture {
            initialSelectedCapture = capturedContent
        }
        return capturedContent.text
    }

    private func preferredSelectedImageContent() async -> ClipboardImageContent? {
        if let capture = finalSelectedCapture, let imageContent = capture.imageContent {
            return imageContent
        }

        if let capture = initialSelectedCapture, let imageContent = capture.imageContent {
            return imageContent
        }

        guard let initialSelectedCaptureTask else {
            return nil
        }

        let capturedContent = await initialSelectedCaptureTask.value
        if capturedContent != initialSelectedCapture {
            initialSelectedCapture = capturedContent
        }
        return capturedContent.imageContent
    }

    private func captureSelectedContent() async -> SelectedClipboardCapture {
        guard isPostEventPermissionGranted else { return .empty }

        let originalClipboard = clipboardService.snapshotCurrentClipboard()
        guard pasteService.copySelectedTextToClipboard() == .dispatched else {
            return .empty
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
                let normalizedText = copiedText.flatMap { $0.isEmpty ? nil : $0 }
                return SelectedClipboardCapture(
                    text: normalizedText,
                    imageContent: currentClipboard.imageContent
                )
            }

            try? await Task.sleep(nanoseconds: Self.selectedTextCapturePollInterval)
        }

        return .empty
    }

    private var currentSuccessText: String? {
        guard case .success(let text, _, _, _, _) = state else {
            return nil
        }
        return text
    }

    // Internal so the `ActivationStore+Rewrite` extension's word-limit checks can
    // reuse it alongside the in-flow check in `rewriteAndDeliver`.
    static func rewriteWordCount(for body: String) -> Int {
        body.split(whereSeparator: { $0.isWhitespace }).count
    }

    private func recordLastTranscription(_ text: String) {
        lastTranscription = text
        lastTranscriptionCapturedAt = dateProvider()
    }

    private func freshLastTranscriptionForRouting() -> String? {
        guard let lastTranscription else { return nil }
        guard let lastTranscriptionCapturedAt else {
            return lastTranscription
        }

        let age = dateProvider().timeIntervalSince(lastTranscriptionCapturedAt)
        guard age <= Self.lastTranscriptionContextMaxAge else {
            return nil
        }

        return lastTranscription
    }

    var isHoldSessionActive: Bool {
        state == .recording && activeActivationOrigin == .hold
    }

    private func refreshSuccessDismissTimer() {
        guard state.isTerminal, case .success = state else { return }
        let start = dateProvider()
        successDismissStartedAt = start
        successDismissDeadline = start.addingTimeInterval(Self.successDismissDurationSeconds)
        scheduleDismissToIdle(
            afterNanoseconds: Self.successDismissDelay,
            sessionID: activeSessionID
        )
    }

    private func beginSuccessDismissTiming(sessionID: UUID) {
        let start = dateProvider()
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
        let sleeper = sleeper
        dismissTask = Task { [weak self] in
            await sleeper.sleep(nanoseconds: duration)
            guard let self, self.isCurrentSession(sessionID) else { return }
            switch self.state {
            case .success, .failure:
                self.clearSuccessDismissTiming()
                self.successNoteSaveState = nil
                self.state = .idle
                self.scheduleWhisperModelIdleUnload()
                self.scheduleRewriteModelIdleUnload()
            case .idle, .recording, .processing, .modelDownloading, .modelPrewarming, .rewriting:
                break
            }
            self.dismissTask = nil
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        !Task.isCancelled && sessionID == activeSessionID
    }

    private static func whisperTranscriptionTimeout(forSampleCount sampleCount: Int) -> UInt64 {
        let audioSeconds = Double(max(0, sampleCount)) / whisperSampleRate
        return whisperTranscriptionBaseTimeout
            + UInt64(audioSeconds) * whisperTranscriptionTimeoutPerAudioSecond
    }

    // Internal so `ActivationStore+Notes` can reuse the timeout wrapper for note
    // title generation alongside the pipeline's prepare/transcribe/rewrite steps.
    func runWithTimeout<T>(
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

    /// Internal (not `private`) so `observeWhisperModelDownloadProgress` in the
    /// `ActivationStore+Models` extension can drive it. This stays in the main
    /// file because it mutates the `private(set)` published `state`.
    func syncWhisperModelDownloadState(
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
