import AppKit
import Combine
import Foundation
import MLXLMCommon

// MARK: - ActivationSoundPlayer

struct ActivationSoundPlayer {
    private let playStartImpl: () -> Void
    private let playSuccessImpl: () -> Void
    private let playFailureImpl: () -> Void
    private let playNoteSavedImpl: () -> Void
    private let playSuccessThenNoteSavedImpl: () -> Void

    init(
        playStart: @escaping () -> Void = { Self.playNamedSound("Tink") },
        playSuccess: @escaping () -> Void = { Self.playNamedSound("Glass") },
        playFailure: @escaping () -> Void = { Self.playNamedSound("Basso") },
        playNoteSaved: @escaping () -> Void = { Self.playNamedSound("NoteSaved") },
        playSuccessThenNoteSaved: @escaping () -> Void = { Self.playSuccessThenNoteSavedDefault() }
    ) {
        self.playStartImpl = playStart
        self.playSuccessImpl = playSuccess
        self.playFailureImpl = playFailure
        self.playNoteSavedImpl = playNoteSaved
        self.playSuccessThenNoteSavedImpl = playSuccessThenNoteSaved
    }

    /// A no-op player. Useful in tests so running the suite does not play real
    /// system sounds for every simulated success/failure.
    static let silent = ActivationSoundPlayer(
        playStart: {},
        playSuccess: {},
        playFailure: {},
        playNoteSaved: {},
        playSuccessThenNoteSaved: {}
    )

    func play() {
        playStartImpl()
    }

    func playSuccess() {
        playSuccessImpl()
    }

    func playFailure() {
        playFailureImpl()
    }

    func playNoteSaved() {
        playNoteSavedImpl()
    }

    func playSuccessThenNoteSaved() {
        playSuccessThenNoteSavedImpl()
    }

    private static func playSuccessThenNoteSavedDefault() {
        let successSound = sound(named: "Glass")
        guard let noteSound = sound(named: "NoteSaved") else {
            successSound?.play()
            return
        }
        guard let successSound else {
            noteSound.play()
            return
        }

        let delay = max(successSound.duration, 0.1)
        successSound.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [successSound, noteSound] in
            _ = successSound
            noteSound.play()
        }
    }

    private static func playNamedSound(_ name: String) {
        sound(named: name)?.play()
    }

    private static func sound(named name: String) -> NSSound? {
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

// MARK: - Sleeping

/// Abstraction over time-based suspension so background timers (e.g. the
/// success-dismiss countdown) can be driven by virtual time in tests instead
/// of real wall-clock sleeps. Production uses `SystemSleeper`, which is a thin
/// wrapper over `Task.sleep` and preserves the previous behaviour exactly.
protocol Sleeping: Sendable {
    func sleep(nanoseconds: UInt64) async
}

struct SystemSleeper: Sleeping {
    func sleep(nanoseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: nanoseconds)
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

    private let preferences: ShellPreferences
    private let readinessProvider: any ReadinessProviding
    private let whisperModelLoadState: any WhisperModelLoadStateProviding
    private let whisperService: any WhisperTranscribing
    private let localRewriteService: any Rewriting
    private let noteCaptureService: any NoteCapturing
    private let historyCaptureService: any HistoryCapturing
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
    private static let whisperModelIdleUnloadDelay: UInt64 = WhisperService.idleUnloadDelayNanoseconds
    private static let rewriteModelIdleUnloadDelay: UInt64 = LocalRewriteService.idleUnloadDelayNanoseconds
    private static let whisperPrepareTimeout: UInt64 = 20_000_000_000
    // Transcription time grows with audio length, so the timeout is a hang-guard
    // that scales with duration rather than a flat ceiling that long recordings
    // would falsely trip. Base covers model warmup + short clips; the per-second
    // allowance is generous enough for slower (e.g. Intel) hardware.
    private static let whisperTranscriptionBaseTimeout: UInt64 = 45_000_000_000
    private static let whisperTranscriptionTimeoutPerAudioSecond: UInt64 = 4_000_000_000
    private static let whisperSampleRate: Double = 16_000
    private static let rewriteTimeout: UInt64 = 45_000_000_000
    private static let minimumDirectAssistantPromptWordLimit = 1_500
    private static let lastTranscriptionContextMaxAge: TimeInterval = 30 * 60
    private static let clipboardRestoreDelay: UInt64 = 150_000_000
    private static let selectedTextCaptureTimeout: UInt64 = 120_000_000
    private static let selectedTextCapturePollInterval: UInt64 = 15_000_000
    private static let minimumStartSoundInterval: TimeInterval = 0.15
    private static let successDismissDelay: UInt64 = 10_000_000_000
    private static let successDismissDurationSeconds = TimeInterval(successDismissDelay) / 1_000_000_000
    private static let noteTitleGenerationTimeout: UInt64 = 8_000_000_000
    private static let noteTitleSystemPrompt = """
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

    /// Word-count ceiling for the rewrite prompt body, matched to the active service.
    /// Built-in local tiers keep their guardrails; cloud models are allowed to
    /// attempt full input without an app-side context cap.
    private var effectivePromptWordLimit: Int {
        let config = preferences.cloudLLMConfig
        guard config.isEnabled, !config.modelID.isEmpty else {
            return preferences.rewriteModelTier.rewritePromptWordLimit
        }
        guard let apiKey = CloudLLMKeychain.loadAPIKey(for: config.provider), !apiKey.isEmpty else {
            return preferences.rewriteModelTier.rewritePromptWordLimit
        }
        return .max
    }

    private func configureLocalRewriteServiceSelection() async {
        await localRewriteService.setTier(preferences.rewriteModelTier)
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
            if let initialSelectedCaptureTask, initialSelectedCapture == nil {
                initialSelectedCapture = await initialSelectedCaptureTask.value
            }
            guard isCurrentSession(sessionID) else { return }
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
            guard isCurrentSession(sessionID) else { return }

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
            let triggerNames = preferences.activeTriggerProfile.allCanonicalNames

            guard isCurrentSession(sessionID) else { return }
            guard !processed.isEmpty else {
                throw TranscriptionError.noSpeechDetected
            }

            let detection = TriggerTranscriptParser.detect(transcript: processed, triggerNames: triggerNames)
            let clipboardSnapshot = sessionClipboardSnapshot
            let shouldRewrite: Bool
            switch detection {
            case .noTrigger:
                shouldRewrite = false
            case .triggered:
                shouldRewrite = true
            }

            if !shouldRewrite {
                let didPaste = shouldPasteOnSuccessfulFinish
                requestsPasteOnCompletion = false
                recordLastTranscription(processed)
                currentSuccessNoteContent = noteCaptureContent(
                    rawTranscription: processed,
                    assistantOutput: nil
                )
                var syntheticPasteSucceeded = false
                if didPaste {
                    syntheticPasteSucceeded = await pasteWithClipboardProtection(text: processed)
                } else {
                    clipboardService.writeToClipboard(processed)
                }
                successNoteSaveState = configuredSuccessNoteSaveState(noteWasSaved: false)
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
                playSuccessSoundIfNeeded()
                beginSuccessDismissTiming(sessionID: sessionID)
            } else {
                let didPaste = shouldPasteOnSuccessfulFinish
                requestsPasteOnCompletion = false

                guard isCurrentSession(sessionID) else { return }
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
                let routingDecision = ExternalTextSourceClassifier.classify(
                    message: dictatedAssistantPrompt,
                    availableSources: routingContext
                )

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
                    guard isCurrentSession(sessionID) else { return }
                    recordLastTranscription(processed)
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
                    guard isCurrentSession(sessionID) else { return }
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
                    return
                }

                guard isCurrentSession(sessionID) else { return }
                let elapsed = DispatchTime.now().uptimeNanoseconds - rewritingStartedAt
                if elapsed < Self.minimumRewritingDisplayDuration {
                    try? await Task.sleep(
                        nanoseconds: Self.minimumRewritingDisplayDuration - elapsed
                    )
                }

                guard isCurrentSession(sessionID) else { return }
                let noteContent = noteCaptureContent(
                    rawTranscription: processed,
                    referencedContexts: referencedNoteContexts,
                    assistantOutput: rewritten
                )
                let automaticNoteWasSaved = shouldAutomaticallySaveAssistantNote(
                    classification: noteIntent
                )
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
                    noteWasSaved: automaticNoteWasSaved
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
                if automaticNoteWasSaved {
                    playSuccessThenNoteSavedSoundIfNeeded()
                } else {
                    playSuccessSoundIfNeeded()
                }
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

    private static func rewriteWordCount(for body: String) -> Int {
        body.split(whereSeparator: { $0.isWhitespace }).count
    }

    private func normalizedExternalText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private func recordLastTranscription(_ text: String) {
        lastTranscription = text
        lastTranscriptionCapturedAt = dateProvider()
    }

    private func noteCaptureContent(
        rawTranscription: String,
        referencedContexts: [NoteCaptureReferencedContext] = [],
        assistantOutput: String?
    ) -> NoteCaptureContent {
        NoteCaptureContent(
            title: nil,
            rawTranscription: rawTranscription,
            referencedContexts: referencedContexts,
            assistantOutput: assistantOutput
        )
    }

    private func configuredSuccessNoteSaveState(noteWasSaved: Bool) -> SuccessNoteSaveState {
        if noteWasSaved {
            return .saved
        }

        return preferences.assistantNoteConfiguration.isConfigured
            ? .available
            : .disabledMissingConfiguration
    }

    private func shouldAutomaticallySaveAssistantNote(
        classification: AssistantNoteIntentClassification
    ) -> Bool {
        classification.requestsAutomaticNoteSave
            && preferences.assistantNoteConfiguration.isConfigured
    }

    @discardableResult
    private func saveNoteIfPossible(content: NoteCaptureContent) async -> Bool {
        let configuration = preferences.assistantNoteConfiguration
        guard configuration.isConfigured else {
            return false
        }

        do {
            let titledContent = await noteCaptureContentWithGeneratedTitle(from: content)
            _ = try noteCaptureService.saveNote(content: titledContent, configuration: configuration)
            return true
        } catch {
            NSLog("TypeLessBuddy: failed to save note: \(error.localizedDescription)")
            return false
        }
    }

    private func persistHistoryIfEnabled(_ content: HistoryCaptureContent) {
        let configuration = preferences.historyConfiguration
        guard configuration.isEnabled else {
            return
        }

        let historyCaptureService = self.historyCaptureService
        DispatchQueue.global(qos: .utility).async {
            do {
                _ = try historyCaptureService.saveEntry(content: content, configuration: configuration)
            } catch {
                NSLog("TypeLessBuddy: failed to save history entry: \(error.localizedDescription)")
            }
        }
    }

    private func noteCaptureContentWithGeneratedTitle(
        from content: NoteCaptureContent
    ) async -> NoteCaptureContent {
        guard content.resolvedTitle == nil else {
            return content
        }

        guard let generatedTitle = await generateNoteTitle(for: content) else {
            return content
        }

        return NoteCaptureContent(
            title: generatedTitle,
            rawTranscription: content.rawTranscription,
            referencedContexts: content.referencedContexts,
            assistantOutput: content.assistantOutput
        )
    }

    private func generateNoteTitle(for content: NoteCaptureContent) async -> String? {
        let prompt = noteTitlePrompt(for: content)
        guard !prompt.isEmpty else {
            return nil
        }

        await localRewriteService.cancelScheduledUnload()
        await configureLocalRewriteServiceSelection()
        defer {
            Task { [localRewriteService] in
                await localRewriteService.scheduleIdleUnload(
                    afterNanoseconds: Self.rewriteModelIdleUnloadDelay
                )
            }
        }

        do {
            let generatedTitle = try await runWithTimeout(
                nanoseconds: Self.noteTitleGenerationTimeout,
                step: "Note title generation"
            ) { [localRewriteService] in
                try await localRewriteService.generate(
                    prompt: prompt,
                    systemPrompt: Self.noteTitleSystemPrompt
                )
            }
            return normalizedGeneratedNoteTitle(generatedTitle)
        } catch {
            NSLog("TypeLessBuddy: note title generation failed — \(error.localizedDescription)")
            return nil
        }
    }

    private func noteTitlePrompt(for content: NoteCaptureContent) -> String {
        var parts: [String] = []

        let rawTranscription = content.resolvedRawTranscription
        if !rawTranscription.isEmpty {
            parts.append("Raw transcription:\n\(rawTranscription)")
        }

        for referencedContext in content.resolvedReferencedContexts {
            parts.append("\(referencedContext.title):\n\(referencedContext.content)")
        }

        if let assistantOutput = content.resolvedAssistantOutput {
            parts.append("Assistant output:\n\(assistantOutput)")
        }

        return parts.joined(separator: "\n\n")
    }

    private func normalizedGeneratedNoteTitle(_ title: String) -> String? {
        let singleLine = title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !singleLine.isEmpty else {
            return nil
        }

        let strippedLabel: String
        if singleLine.lowercased().hasPrefix("title:") {
            strippedLabel = String(singleLine.dropFirst("title:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            strippedLabel = singleLine
        }

        let trimmedPunctuation = strippedLabel.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'`#*:-. ")
        )
        guard !trimmedPunctuation.isEmpty else {
            return nil
        }

        return String(trimmedPunctuation.prefix(80))
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

    private func rewritePromptWordLimit(
        for _: AssistantContextRoutingDecision,
        externalTextInjected: Bool
    ) -> Int {
        guard !externalTextInjected else {
            return effectivePromptWordLimit
        }

        return max(
            effectivePromptWordLimit,
            Self.minimumDirectAssistantPromptWordLimit
        )
    }

    private struct ExternalTextInputs {
        let selectedText: String?
        let clipboardText: String?
        let lastTranscription: String?
        let selectedImageContent: ClipboardImageContent?
        let clipboardImageContent: ClipboardImageContent?
    }

    private func validatedExternalTextInputs(
        selectedText: String?,
        clipboardText: String?,
        lastTranscription: String?,
        selectedImageContent: ClipboardImageContent?,
        clipboardImageContent: ClipboardImageContent?
    ) -> ExternalTextInputs {
        let normalizedSelectedText = normalizedExternalText(selectedText)
        let normalizedLastTranscription = normalizedExternalText(lastTranscription)
        let normalizedClipboardText = normalizedExternalText(clipboardText)

        return ExternalTextInputs(
            selectedText: validatedSizedContext(normalizedSelectedText),
            clipboardText: validatedSizedContext(normalizedClipboardText),
            lastTranscription: normalizedLastTranscription,
            selectedImageContent: selectedImageContent,
            clipboardImageContent: clipboardImageContent
        )
    }

    private func validatedSizedContext(_ text: String?) -> String? {
        guard let text else { return nil }
        guard Self.rewriteWordCount(for: text) <= effectivePromptWordLimit else {
            return nil
        }
        return text
    }

    private func buildRewritePromptBody(
        dictatedContent: String,
        inputs: ExternalTextInputs,
        decision: AssistantContextRoutingDecision
    ) -> (body: String, externalTextInjected: Bool, decisionUsed: AssistantContextRoutingDecision) {
        let matchedSources = adjustedMatchedSources(for: decision.matchedSources, inputs: inputs)
        let decisionUsed = AssistantContextRoutingDecision(
            matchedSources: matchedSources,
            decisionSource: matchedSources.isEmpty
                ? (decision.decisionSource == .noAvailableContext ? .noAvailableContext : .noDeterministicMatch)
                : decision.decisionSource
        )

        guard decisionUsed.injectsExternalText else {
            let directBody = ExternalTextPromptBuilder.buildDirectBody(
                dictatedContent: dictatedContent
            )
            return (directBody, false, decisionUsed)
        }

        let body = ExternalTextPromptBuilder.buildBody(
            dictatedContent: dictatedContent,
            selectedText: inputs.selectedText,
            clipboardText: inputs.clipboardText,
            lastTranscription: inputs.lastTranscription,
            routingDecision: decisionUsed
        )
        let injected = decisionUsed.injectsExternalText
        return (body, injected, decisionUsed)
    }

    private func adjustedMatchedSources(
        for matchedSources: [AssistantContextMatchedSource],
        inputs: ExternalTextInputs
    ) -> [AssistantContextMatchedSource] {
        matchedSources.filter { matchedSource in
            switch matchedSource.targetMode {
            case .selectedText:
                return inputs.selectedText != nil || inputs.selectedImageContent != nil
            case .clipboard:
                return inputs.clipboardText != nil || inputs.clipboardImageContent != nil
            case .lastTranscription:
                return inputs.lastTranscription != nil
            case .none:
                return false
            }
        }
    }

    private func assistantInputImages(
        from matchedSources: [AssistantContextMatchedSource],
        inputs: ExternalTextInputs
    ) -> [UserInput.Image] {
        guard shouldAttachAssistantImages else {
            return []
        }

        for matchedSource in matchedSources {
            let content: ClipboardImageContent?
            switch matchedSource.targetMode {
            case .selectedText:
                content = inputs.selectedImageContent
            case .clipboard:
                content = inputs.clipboardImageContent
            case .lastTranscription, .none:
                content = nil
            }

            if let image = makeUserInputImage(from: content) {
                return [image]
            }
        }

        // Image-only clipboard/selection context still needs to reach image-capable
        // models even when there is no companion text to inject into the prompt body.
        let fallbackContents: [ClipboardImageContent?] = [
            inputs.selectedText == nil ? inputs.selectedImageContent : nil,
            inputs.clipboardText == nil ? inputs.clipboardImageContent : nil,
        ]
        for content in fallbackContents {
            if let image = makeUserInputImage(from: content) {
                return [image]
            }
        }

        return []
    }

    private var shouldAttachAssistantImages: Bool {
        false
    }

    private func makeUserInputImage(from content: ClipboardImageContent?) -> UserInput.Image? {
        guard let content else { return nil }

        switch content.source {
        case .fileURL(let url):
            return .url(url)
        case .data(let data):
            if let ciImage = CIImage(data: data) {
                return .ciImage(ciImage)
            }

            guard let image = NSImage(data: data),
                  let tiffData = image.tiffRepresentation,
                  let ciImage = CIImage(data: tiffData) else {
                return nil
            }
            return .ciImage(ciImage)
        }
    }

    private func noteReferencedContexts(
        from matchedSources: [AssistantContextMatchedSource],
        inputs: ExternalTextInputs
    ) -> [NoteCaptureReferencedContext] {
        matchedSources.compactMap { matchedSource in
            let content: String?
            let title: String

            switch matchedSource.targetMode {
            case .selectedText:
                title = "Selected text"
                content = inputs.selectedText
            case .clipboard:
                title = "Clipboard text"
                content = inputs.clipboardText
            case .lastTranscription:
                title = "Last transcription"
                content = inputs.lastTranscription
            case .none:
                return nil
            }

            guard let content else {
                return nil
            }

            return NoteCaptureReferencedContext(
                title: title,
                content: content
            )
        }
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
            await self.localRewriteService.cancelScheduledUnload()
            await self.configureLocalRewriteServiceSelection()
            try? await self.localRewriteService.prewarm()
        }
    }

    private func scheduleRewriteModelIdleUnload() {
        guard !preferences.cloudLLMConfig.isEnabled else { return }
        Task { [localRewriteService] in
            await localRewriteService.scheduleIdleUnload(
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
