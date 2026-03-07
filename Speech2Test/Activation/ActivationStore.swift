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

    private let preferences: ShellPreferences
    private let readinessProvider: any ReadinessProviding
    private let whisperService: any WhisperTranscribing
    private let clipboardService: ClipboardService
    let bufferAccumulator: AudioBufferAccumulator
    var soundPlayer: ActivationSoundPlayer = .init()

    convenience init(preferences: ShellPreferences, readinessStore: ReadinessStore) {
        self.init(
            preferences: preferences,
            readinessProvider: readinessStore,
            whisperService: WhisperService(),
            clipboardService: ClipboardService(),
            bufferAccumulator: AudioBufferAccumulator()
        )
    }

    init(
        preferences: ShellPreferences,
        readinessProvider: any ReadinessProviding,
        whisperService: any WhisperTranscribing = WhisperService(),
        clipboardService: ClipboardService = ClipboardService(),
        bufferAccumulator: AudioBufferAccumulator = AudioBufferAccumulator()
    ) {
        self.preferences = preferences
        self.readinessProvider = readinessProvider
        self.whisperService = whisperService
        self.clipboardService = clipboardService
        self.bufferAccumulator = bufferAccumulator
    }

    // MARK: - Public API

    func arm() {
        // Toggle: if already recording, finish (trigger transcription flow).
        if state == .recording {
            finish()
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

        bufferAccumulator.reset()
        state = .recording
    }

    /// Hard stop — transitions directly to idle without transcribing. Used for cancel (Phase 4).
    func stop() {
        state = .idle
    }

    /// Finish recording: stops capture and runs the transcription -> clipboard -> dismiss flow.
    func finish() {
        guard state == .recording else { return }
        state = .processing

        Task {
            await transcribeAndDispatch()
        }
    }

    /// Called by AudioLevelMonitor's onSilenceTimeout callback.
    /// Attempts transcription of whatever audio was captured during the session.
    func handleSilenceTimeout() {
        // Per plan decision: still attempt transcription on whatever audio was captured.
        finish()
    }

    // MARK: - Private transcription flow

    private func transcribeAndDispatch() async {
        do {
            let samples = try bufferAccumulator.convertToWhisperFormat()
            let text = try await whisperService.transcribe(samples: samples)

            // Success path
            state = .success(text: text)
            clipboardService.writeToClipboard(text)
            if preferences.autoPasteEnabled {
                clipboardService.autoPaste()
            }

            // Auto-dismiss to idle after 1.5s
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if case .success = self.state {
                    self.state = .idle
                }
            }

        } catch TranscriptionError.noSpeechDetected {
            state = .failure(reason: .noSpeechDetected)
            scheduleDismissToIdle()

        } catch {
            state = .failure(reason: .modelError(error.localizedDescription))
            scheduleDismissToIdle()
        }
    }

    private func scheduleDismissToIdle() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if case .failure = self.state {
                self.state = .idle
            }
        }
    }
}
