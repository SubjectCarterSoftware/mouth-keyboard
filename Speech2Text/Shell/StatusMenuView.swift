import SwiftUI

struct StatusMenuView: View {
    let recordingState: RecordingState
    let recoveryFeedback: RecordingState.RecoveryFeedback?
    let lastTranscription: String?
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    let recoveryActionPerformer: RecoveryActionPerformer = .live
    let cancelSession: () -> Void
    let restartSession: () -> Void
    let copyLastTranscription: () -> Void
    let lastConvertedTranscription: String?
    let copyLastConvertedTranscription: () -> Void
    let openSetup: () -> Void
    let quitApp: () -> Void


    private var canCancelSession: Bool {
        recordingState == .recording
            || recordingState == .processing
            || recordingState.isModelDownloading
            || recordingState == .converting
    }

    private var canRestartSession: Bool {
        recordingState == .recording
    }

    private var recoveryStatusText: String? {
        if let recoveryFeedback {
            switch recoveryFeedback {
            case .canceled:
                return "Last session canceled."
            case .restarted:
                return "Recording restarted from a clean buffer."
            }
        }

        switch recordingState {
        case .recording:
            return "Recording is active. Use Restart to clear the current buffer or Cancel to discard it."
        case .processing:
            return "Processing is active. Cancel stops the session and preserves the existing clipboard."
        case .modelDownloading(let model, _):
            return "\(model.displayName) is still downloading. Cancel stops the session and preserves the existing clipboard."
        case .failure(let reason):
            return failureMessage(for: reason)
        case .idle, .success, .converting:
            return nil
        }
    }


    private var showsMicrophoneSettingsAction: Bool {
        guard case .failure(let reason) = recordingState else {
            return false
        }

        switch reason {
        case .microphonePermissionDenied:
            return true
        case .noSpeechDetected,
             .microphoneUnavailable,
             .selectedMicrophoneUnavailable,
             .selectedMicrophoneDisconnected,
             .modelError,
             .silenceTimeout,
             .wordLimitExceeded:
            return false
        }
    }

    private var showsMicrophoneRecoveryAction: Bool {
        guard case .failure(let reason) = recordingState else {
            return false
        }

        switch reason {
        case .microphonePermissionDenied,
             .microphoneUnavailable,
             .selectedMicrophoneUnavailable,
             .selectedMicrophoneDisconnected:
            return true
        case .noSpeechDetected, .modelError, .silenceTimeout, .wordLimitExceeded:
            return false
        }
    }


    private var needsSetup: Bool {
        readinessStore.snapshot.state != .ready
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if needsSetup {
                Button(action: openSetup) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Setup — Permissions Required")
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityIdentifier("statusMenu.primaryAction")
            } else {
                if canCancelSession {
                    Button("Cancel Session", action: cancelSession)
                        .accessibilityIdentifier("statusMenu.cancelSession")
                }

                if canRestartSession {
                    Button("Restart Recording", action: restartSession)
                        .accessibilityIdentifier("statusMenu.restartSession")
                }

                if let recoveryStatusText {
                    Text(recoveryStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(recoveryStatusText)
                        .accessibilityIdentifier("statusMenu.recoveryMessage")
                }

                if showsMicrophoneRecoveryAction {
                    Button("Open Microphone Recovery", action: openSetup)
                        .accessibilityIdentifier("statusMenu.openMicrophoneRecovery")
                }

                if showsMicrophoneSettingsAction {
                    Button("Open Microphone Settings") {
                        recoveryActionPerformer.openMicrophoneSettings()
                    }
                    .accessibilityIdentifier("statusMenu.openMicrophoneSettings")
                }

                Button("Hotkeys & Settings…", action: openSetup)
                    .keyboardShortcut(",", modifiers: .command)
                    .accessibilityIdentifier("statusMenu.primaryAction")

                Divider()

                if lastTranscription != nil {
                    Button("Copy Last Transcription", action: copyLastTranscription)
                        .accessibilityIdentifier("statusMenu.copyLastTranscription")
                }

                Button("Copy Last AI Converted Transcription",
                       action: copyLastConvertedTranscription)
                    .disabled(lastConvertedTranscription == nil)
                    .accessibilityIdentifier("statusMenu.copyLastConvertedTranscription")
            }

            Divider()

            Button("Quit Speech2Text", action: quitApp)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            readinessStore.refresh()
        }
    }

    private func failureMessage(for reason: RecordingState.FailureReason) -> String {
        switch reason {
        case .microphonePermissionDenied:
            return "Microphone access is blocked. Open Settings to re-enable it, or open Setup to review recovery."
        case .microphoneUnavailable:
            return "No microphone is available. Connect one, then open Setup to review the input choice."
        case .selectedMicrophoneUnavailable:
            return "The selected microphone is unavailable. Reconnect it or open Setup to choose another one."
        case .selectedMicrophoneDisconnected:
            return "The selected microphone disconnected. Reconnect it or open Setup to choose another input."
        case .noSpeechDetected:
            return "No speech was detected. Try again when you are ready to speak."
        case .modelError:
            return "Transcription failed. Try the session again after recovery."
        case .silenceTimeout:
            return "The session timed out after extended silence."
        case .wordLimitExceeded:
            return "Dictation is too long to convert. Raw text copied to clipboard."
        }
    }

}
