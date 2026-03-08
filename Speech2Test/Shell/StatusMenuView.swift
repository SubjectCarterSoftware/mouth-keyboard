import SwiftUI

struct StatusMenuView: View {
    let recordingState: RecordingState
    let recoveryFeedback: RecordingState.RecoveryFeedback?
    let longSessionStatus: LongSessionStatus
    let resultNotice: LongSessionResultNotice?
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    let recoveryActionPerformer: RecoveryActionPerformer = .live
    let cancelSession: () -> Void
    let restartSession: () -> Void
    let openSetup: () -> Void
    let quitApp: () -> Void

    private var attentionItems: [PermissionChecklistItem] {
        readinessStore.snapshot.permissions.filter { !$0.isAuthorized }
    }

    private var canCancelSession: Bool {
        recordingState == .recording || recordingState == .processing
    }

    private var canRestartSession: Bool {
        recordingState == .recording
    }

    private var recoveryStatusText: String? {
        if let recoveryFeedback {
            switch recoveryFeedback {
            case .canceled:
                return preferences.indicatorVisible
                    ? "Last session canceled."
                    : "Last session canceled. The menu is carrying confirmation because the indicator is hidden."
            case .restarted:
                return preferences.indicatorVisible
                    ? "Recording restarted from a clean buffer."
                    : "Recording restarted from a clean buffer. The menu is carrying confirmation because the indicator is hidden."
            }
        }

        switch recordingState {
        case .recording:
            return "Recording is active. Use Restart to clear the current buffer or Cancel to discard it."
        case .processing:
            return "Processing is active. Cancel stops the session and preserves the existing clipboard."
        case .failure(let reason):
            return failureMessage(for: reason)
        case .idle, .success:
            return nil
        }
    }

    private var longSessionStatusText: String? {
        let baseText: String

        switch longSessionStatus.phase {
        case .inactive:
            return nil
        case .recordingSegmented:
            baseText = "Long dictation is active. Finish when you are ready and Speech2Test will assemble the queued segments into one clipboard result."
        case .finalizing:
            baseText = "Finalizing long dictation. Queued segments are still settling into one clipboard result."
        }

        return menuCarriedText(baseText)
    }

    private var longSessionWarningText: String? {
        guard let resultNotice else {
            return nil
        }

        let segmentLabel = resultNotice.failedSegmentCount == 1 ? "segment" : "segments"
        let baseText = "The last long dictation omitted \(resultNotice.failedSegmentCount) failed \(segmentLabel) from the clipboard result."
        return menuCarriedText(baseText)
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
             .silenceTimeout:
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
        case .noSpeechDetected, .modelError, .silenceTimeout:
            return false
        }
    }

    private var menuHintText: String {
        switch readinessStore.snapshot.state {
        case .ready:
            return "Speech2Test is ready to stay quiet in the menu bar until you trigger a session."
        case .needsSetup:
            return "Finish the checklist once and the app will settle into the quieter menu bar shell on future launches."
        case .blocked:
            return "One or more permissions still need recovery in System Settings before Speech2Test can become ready."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusCardView(
                snapshot: readinessStore.snapshot,
                readyConfirmation: readinessStore.readyConfirmation
            )

            if !attentionItems.isEmpty {
                PermissionChecklistView(
                    permissions: attentionItems,
                    requestPermission: { kind in
                        readinessStore.requestPermission(for: kind)
                    },
                    openRecovery: { kind in
                        readinessStore.openRecovery(for: kind)
                    }
                )
            }

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

            if let longSessionStatusText {
                Text(longSessionStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(longSessionStatusText)
                    .accessibilityIdentifier("statusMenu.longSessionStatus")
            }

            if let longSessionWarningText {
                Text(longSessionWarningText)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(longSessionWarningText)
                    .accessibilityIdentifier("statusMenu.longSessionWarning")
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

            Button(readinessStore.snapshot.primaryActionTitle, action: openSetup)
                .accessibilityIdentifier("statusMenu.primaryAction")

            Toggle("Show recording indicator", isOn: $preferences.indicatorVisible)
                .accessibilityIdentifier("statusMenu.indicatorVisible")

            Toggle("Show shell hints in menu", isOn: $preferences.showsMenuHints)
                .accessibilityIdentifier("statusMenu.showsMenuHints")

            if preferences.showsMenuHints {
                Text(menuHintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if preferences.hasCompletedInitialSetup {
                Button("Reset Setup") {
                    readinessStore.resetSetup()
                    openSetup()
                }
                .accessibilityIdentifier("statusMenu.resetSetup")
            }

            Divider()

            Button("Quit Speech2Test", action: quitApp)
        }
        .padding(14)
        .frame(width: 310)
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
        }
    }

    private func menuCarriedText(_ text: String) -> String {
        if preferences.indicatorVisible {
            return text
        }

        return "\(text) The menu is carrying this status because the indicator is hidden."
    }
}
