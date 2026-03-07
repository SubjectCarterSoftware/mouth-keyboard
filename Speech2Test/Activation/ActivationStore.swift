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

    private let preferences: ShellPreferences
    private let readinessProvider: any ReadinessProviding
    private let whisperService: any WhisperTranscribing
    private let clipboardService: ClipboardService
    private let resetSessionMonitoring: @MainActor () -> Void
    let bufferAccumulator: AudioBufferAccumulator
    var soundPlayer: ActivationSoundPlayer = .init()
    private var activeSessionID = UUID()
    private var transcriptionTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var feedbackClearTask: Task<Void, Never>?

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

        // Ignore activation while transcription or terminal feedback is still
        // on-screen. The hotkey is a start/finish toggle, not a restart.
        guard state == .idle else {
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
        publishRecoveryFeedback(.canceled)
        state = .idle
    }

    func restartCurrentSession() {
        guard state == .recording else { return }

        invalidateActiveSession()
        bufferAccumulator.reset()
        resetSessionMonitoring()
        publishRecoveryFeedback(.restarted)
        state = .recording
    }

    /// Finish recording: stops capture and runs the transcription -> clipboard -> dismiss flow.
    func finish() {
        guard state == .recording else { return }
        invalidateScheduledWork()
        recoveryFeedback = nil
        state = .processing
        let sessionID = UUID()
        activeSessionID = sessionID
        let task = Task { [weak self] in
            guard let self else { return }
            // Let state observers stop audio capture before we snapshot and
            // convert the accumulated buffers for Whisper.
            await Task.yield()
            await self.transcribeAndDispatch(sessionID: sessionID)
        }
        transcriptionTask = task
    }

    /// Called by AudioLevelMonitor's onSilenceTimeout callback.
    /// Attempts transcription of whatever audio was captured during the session.
    func handleSilenceTimeout() {
        // Per plan decision: still attempt transcription on whatever audio was captured.
        finish()
    }

    // MARK: - Private transcription flow

    private func transcribeAndDispatch(sessionID: UUID) async {
        do {
            guard isCurrentSession(sessionID) else { return }

            if let whisperService = whisperService as? WhisperService,
               let modelPath = Bundle.main.path(forResource: "ggml-small.en", ofType: "bin") {
                try await whisperService.ensureModelLoaded(at: modelPath)
            }

            guard isCurrentSession(sessionID) else { return }
            let samples = try bufferAccumulator.convertToWhisperFormat()
            let text = try await whisperService.transcribe(samples: samples)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard isCurrentSession(sessionID) else { return }
            guard !trimmed.isEmpty else {
                throw TranscriptionError.noSpeechDetected
            }

            // Success path
            state = .success(text: trimmed)
            clipboardService.writeToClipboard(trimmed)

            // Auto-dismiss to idle after 1.5s
            scheduleDismissToIdle(afterNanoseconds: 1_500_000_000, sessionID: sessionID)

        } catch TranscriptionError.noSpeechDetected {
            guard isCurrentSession(sessionID) else { return }
            state = .failure(reason: .noSpeechDetected)
            scheduleDismissToIdle(afterNanoseconds: 2_000_000_000, sessionID: sessionID)

        } catch {
            guard isCurrentSession(sessionID) else { return }
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
        invalidateScheduledWork()
    }

    private func invalidateScheduledWork() {
        dismissTask?.cancel()
        dismissTask = nil
        feedbackClearTask?.cancel()
        feedbackClearTask = nil
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
}
