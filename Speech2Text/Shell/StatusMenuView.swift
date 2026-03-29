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

    private var startRecordingKeyboardShortcut: KeyboardShortcut? {
        KeyboardShortcuts.getShortcut(for: .activate)?.swiftUIKeyboardShortcut
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
                    if let startRecordingKeyboardShortcut {
                        Button("Start Recording", action: startRecording)
                            .keyboardShortcut(startRecordingKeyboardShortcut)
                            .accessibilityIdentifier("statusMenu.startRecording")
                    } else {
                        Button("Start Recording", action: startRecording)
                            .accessibilityIdentifier("statusMenu.startRecording")
                    }
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

private extension NSEvent.ModifierFlags {
    var swiftUIEventModifiers: EventModifiers {
        var result: EventModifiers = []

        if contains(.control) {
            result.insert(.control)
        }

        if contains(.option) {
            result.insert(.option)
        }

        if contains(.shift) {
            result.insert(.shift)
        }

        if contains(.command) {
            result.insert(.command)
        }

        return result
    }
}

private extension KeyboardShortcuts.Shortcut {
    var swiftUIKeyboardShortcut: KeyboardShortcut? {
        guard let keyEquivalent = key?.swiftUIKeyEquivalent else {
            return nil
        }

        return KeyboardShortcut(keyEquivalent, modifiers: modifiers.swiftUIEventModifiers)
    }
}

private extension KeyboardShortcuts.Key {
    var swiftUIKeyEquivalent: KeyEquivalent? {
        switch self {
        case .a: return keyEquivalent("a")
        case .b: return keyEquivalent("b")
        case .c: return keyEquivalent("c")
        case .d: return keyEquivalent("d")
        case .e: return keyEquivalent("e")
        case .f: return keyEquivalent("f")
        case .g: return keyEquivalent("g")
        case .h: return keyEquivalent("h")
        case .i: return keyEquivalent("i")
        case .j: return keyEquivalent("j")
        case .k: return keyEquivalent("k")
        case .l: return keyEquivalent("l")
        case .m: return keyEquivalent("m")
        case .n: return keyEquivalent("n")
        case .o: return keyEquivalent("o")
        case .p: return keyEquivalent("p")
        case .q: return keyEquivalent("q")
        case .r: return keyEquivalent("r")
        case .s: return keyEquivalent("s")
        case .t: return keyEquivalent("t")
        case .u: return keyEquivalent("u")
        case .v: return keyEquivalent("v")
        case .w: return keyEquivalent("w")
        case .x: return keyEquivalent("x")
        case .y: return keyEquivalent("y")
        case .z: return keyEquivalent("z")
        case .zero: return keyEquivalent("0")
        case .one: return keyEquivalent("1")
        case .two: return keyEquivalent("2")
        case .three: return keyEquivalent("3")
        case .four: return keyEquivalent("4")
        case .five: return keyEquivalent("5")
        case .six: return keyEquivalent("6")
        case .seven: return keyEquivalent("7")
        case .eight: return keyEquivalent("8")
        case .nine: return keyEquivalent("9")
        case .backslash: return keyEquivalent("\\")
        case .backtick: return keyEquivalent("`")
        case .comma: return keyEquivalent(",")
        case .equal: return keyEquivalent("=")
        case .minus: return keyEquivalent("-")
        case .period: return keyEquivalent(".")
        case .quote: return keyEquivalent("'")
        case .semicolon: return keyEquivalent(";")
        case .slash: return keyEquivalent("/")
        case .leftBracket: return keyEquivalent("[")
        case .rightBracket: return keyEquivalent("]")
        case .space: return .space
        case .tab: return .tab
        case .return: return .return
        case .delete: return .delete
        case .deleteForward: return .deleteForward
        case .home: return .home
        case .end: return .end
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .upArrow: return .upArrow
        case .rightArrow: return .rightArrow
        case .downArrow: return .downArrow
        case .leftArrow: return .leftArrow
        case .escape: return .escape
        case .f1: return functionKeyEquivalent(NSF1FunctionKey)
        case .f2: return functionKeyEquivalent(NSF2FunctionKey)
        case .f3: return functionKeyEquivalent(NSF3FunctionKey)
        case .f4: return functionKeyEquivalent(NSF4FunctionKey)
        case .f5: return functionKeyEquivalent(NSF5FunctionKey)
        case .f6: return functionKeyEquivalent(NSF6FunctionKey)
        case .f7: return functionKeyEquivalent(NSF7FunctionKey)
        case .f8: return functionKeyEquivalent(NSF8FunctionKey)
        case .f9: return functionKeyEquivalent(NSF9FunctionKey)
        case .f10: return functionKeyEquivalent(NSF10FunctionKey)
        case .f11: return functionKeyEquivalent(NSF11FunctionKey)
        case .f12: return functionKeyEquivalent(NSF12FunctionKey)
        case .f13: return functionKeyEquivalent(NSF13FunctionKey)
        case .f14: return functionKeyEquivalent(NSF14FunctionKey)
        case .f15: return functionKeyEquivalent(NSF15FunctionKey)
        case .f16: return functionKeyEquivalent(NSF16FunctionKey)
        case .f17: return functionKeyEquivalent(NSF17FunctionKey)
        case .f18: return functionKeyEquivalent(NSF18FunctionKey)
        case .f19: return functionKeyEquivalent(NSF19FunctionKey)
        case .f20: return functionKeyEquivalent(NSF20FunctionKey)
        default: return nil
        }
    }

    private func keyEquivalent(_ character: Character) -> KeyEquivalent {
        KeyEquivalent(character)
    }

    private func functionKeyEquivalent(_ scalarValue: Int) -> KeyEquivalent? {
        guard let scalar = UnicodeScalar(scalarValue) else {
            return nil
        }

        return KeyEquivalent(Character(scalar))
    }
}
