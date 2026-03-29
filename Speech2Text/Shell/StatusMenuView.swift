import SwiftUI
import KeyboardShortcuts

struct StatusMenuView: View {
    let recordingState: RecordingState
    let recoveryFeedback: RecordingState.RecoveryFeedback?
    let lastTranscription: String?
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    @ObservedObject var audioDeviceService: AudioDeviceService
    let recoveryActionPerformer: RecoveryActionPerformer = .live
    let cancelSession: () -> Void
    let restartSession: () -> Void
    let startRecording: () -> Void
    let copyLastTranscription: () -> Void
    let lastConvertedTranscription: String?
    let copyLastConvertedTranscription: () -> Void
    let setMicDevice: (String?) -> Void
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

    private var canStartSession: Bool {
        recordingState == .idle
    }

    private var holdKeyHint: String {
        HoldKeyDisplayFormatter.symbol(
            keyCode: preferences.holdShortcutKeyCode,
            modifiers: preferences.holdShortcutModifiers
        )
    }

    private var tapKeyHint: String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .activate) else { return "" }
        var result = ""
        if shortcut.modifiers.contains(.control) { result += "⌃" }
        if shortcut.modifiers.contains(.option)  { result += "⌥" }
        if shortcut.modifiers.contains(.shift)   { result += "⇧" }
        if shortcut.modifiers.contains(.command) { result += "⌘" }
        if let key = shortcut.key {
            result += HoldKeyDisplayFormatter.keyCharacter(for: key.rawValue)
        }
        return result
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
                if canStartSession {
                    Button(action: startRecording) {
                        HStack {
                            Text("Start Recording")
                            Spacer()
                            HStack(spacing: 4) {
                                Text("Hold \(holdKeyHint)")
                                if !tapKeyHint.isEmpty {
                                    Text("·")
                                    Text(tapKeyHint)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("statusMenu.startRecording")
                }

                if canCancelSession {
                    Button("Cancel Session", action: cancelSession)
                        .keyboardShortcut("v", modifiers: [.control, .shift])
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

                Menu {
                    Button(action: { setMicDevice(nil) }) {
                        HStack {
                            if preferences.micDeviceUID == nil {
                                Image(systemName: "checkmark")
                            }
                            Text("System Default")
                        }
                    }
                    .accessibilityIdentifier("statusMenu.mic.systemDefault")

                    if !audioDeviceService.availableDevices.isEmpty {
                        Divider()
                        ForEach(audioDeviceService.availableDevices) { device in
                            Button(action: { setMicDevice(device.uid) }) {
                                HStack {
                                    if preferences.micDeviceUID == device.uid {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(device.name)
                                }
                            }
                            .accessibilityIdentifier("statusMenu.mic.\(device.uid)")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic")
                        Text("Microphone")
                    }
                }
                .disabled(canCancelSession)
                .accessibilityIdentifier("statusMenu.microphoneMenu")

                Button(action: { preferences.alwaysAutoPaste.toggle() }) {
                    HStack {
                        if preferences.alwaysAutoPaste {
                            Image(systemName: "checkmark")
                        }
                        Text("Auto-paste")
                    }
                }
                .disabled(canCancelSession)
                .accessibilityIdentifier("statusMenu.autoPaste")

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
            if !needsSetup {
                audioDeviceService.refresh()
            }
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
