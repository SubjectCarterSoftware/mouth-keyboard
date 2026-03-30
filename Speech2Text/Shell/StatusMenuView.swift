import SwiftUI
import KeyboardShortcuts

private enum StatusMenuMetrics {
    static let width: CGFloat = 280
    static let padding: CGFloat = 14
    static let rowHeight: CGFloat = 18
    static let rowSpacing: CGFloat = 12
}

struct StatusMenuView: View {
    let recordingState: RecordingState
    let lastTranscription: String?
    @ObservedObject var preferences: ShellPreferences
    @ObservedObject var readinessStore: ReadinessStore
    @ObservedObject var audioDeviceService: AudioDeviceService
    let cancelSession: () -> Void
    let restartSession: () -> Void
    let startRecording: () -> Void
    let finishRecording: () -> Void
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

    private var canFinishSession: Bool {
        recordingState == .recording
    }

    private var canStartSession: Bool {
        recordingState == .idle || recordingState.isTerminal
    }

    private var startRecordingKeyboardShortcut: KeyboardShortcut? {
        KeyboardShortcuts.getShortcut(for: .activate)?.swiftUIKeyboardShortcut
    }

    private var finishRecordingKeyboardShortcut: KeyboardShortcut? {
        KeyboardShortcuts.getShortcut(for: .stopSession)?.swiftUIKeyboardShortcut
    }

    private var primaryHoldShortcutText: String {
        if let primary = holdShortcutSymbol(
            keyCode: preferences.holdShortcutKeyCode,
            modifiers: preferences.holdShortcutModifiers
        ) {
            return primary
        }

        return "Not set"
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
                if let startRecordingKeyboardShortcut {
                    Button("Start Recording", action: startRecording)
                        .keyboardShortcut(startRecordingKeyboardShortcut)
                        .disabled(!canStartSession)
                        .accessibilityIdentifier("statusMenu.startRecording")
                } else {
                    Button("Start Recording", action: startRecording)
                        .disabled(!canStartSession)
                        .accessibilityIdentifier("statusMenu.startRecording")
                }

                if let finishRecordingKeyboardShortcut {
                    Button("Finish Recording", action: finishRecording)
                        .keyboardShortcut(finishRecordingKeyboardShortcut)
                        .disabled(!canFinishSession)
                        .accessibilityIdentifier("statusMenu.finishRecording")
                } else {
                    Button("Finish Recording", action: finishRecording)
                        .disabled(!canFinishSession)
                        .accessibilityIdentifier("statusMenu.finishRecording")
                }

                Button("Cancel Session", action: cancelSession)
                    .keyboardShortcut("v", modifiers: [.control, .shift])
                    .disabled(!canCancelSession)
                    .accessibilityIdentifier("statusMenu.cancelSession")

                Button("Restart Recording", action: restartSession)
                    .disabled(!canRestartSession)
                    .accessibilityIdentifier("statusMenu.restartSession")

                PassiveMenuShortcutRow(
                    title: "Hold to Transcribe",
                    shortcutText: primaryHoldShortcutText,
                    accessibilityIdentifier: "statusMenu.holdShortcutHint"
                )

                Divider()

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

                Button(action: { preferences.allowClipboardAccess.toggle() }) {
                    HStack {
                        if preferences.allowClipboardAccess {
                            Image(systemName: "checkmark")
                        }
                        Text("Clipboard access")
                    }
                }
                .disabled(canCancelSession)
                .accessibilityIdentifier("statusMenu.clipboardAccess")

                Divider()

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

                Button("Settings & Hotkeys…", action: openSetup)
                    .keyboardShortcut(",", modifiers: .command)
                    .accessibilityIdentifier("statusMenu.primaryAction")

                Button("Copy Last AI Converted Transcription",
                       action: copyLastConvertedTranscription)
                    .disabled(lastConvertedTranscription == nil)
                    .accessibilityIdentifier("statusMenu.copyLastConvertedTranscription")

                Button("Copy Last Transcription", action: copyLastTranscription)
                    .disabled(lastTranscription == nil)
                    .accessibilityIdentifier("statusMenu.copyLastTranscription")
            }

            Divider()

            Button("Quit Speech2Text", action: quitApp)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(StatusMenuMetrics.padding)
        .frame(width: StatusMenuMetrics.width)
        .onAppear {
            readinessStore.refresh()
            if !needsSetup {
                audioDeviceService.refresh()
            }
        }
    }

}

private func holdShortcutSymbol(keyCode: Int, modifiers: UInt) -> String? {
    guard keyCode >= 0 else {
        return nil
    }

    return HoldKeyDisplayFormatter.symbol(keyCode: keyCode, modifiers: modifiers)
}

private struct PassiveMenuShortcutRow: NSViewRepresentable {
    let title: String
    let shortcutText: String
    let accessibilityIdentifier: String

    func makeNSView(context: Context) -> PassiveMenuShortcutRowView {
        let view = PassiveMenuShortcutRowView()
        view.setAccessibilityIdentifier(accessibilityIdentifier)
        return view
    }

    func updateNSView(_ nsView: PassiveMenuShortcutRowView, context: Context) {
        nsView.configure(title: title, shortcutText: shortcutText)
    }
}

private final class PassiveMenuShortcutRowView: NSView {
    private let titleField = NSTextField(labelWithString: "")
    private let shortcutField = NSTextField(labelWithString: "")

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: StatusMenuMetrics.width - (StatusMenuMetrics.padding * 2),
            height: StatusMenuMetrics.rowHeight
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, shortcutText: String) {
        titleField.stringValue = title
        shortcutField.stringValue = shortcutText
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        [titleField, shortcutField].forEach { field in
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isBezeled = false
            field.drawsBackground = false
            field.isEditable = false
            field.isSelectable = false
            field.font = NSFont.menuFont(ofSize: 0)
            field.textColor = NSColor.disabledControlTextColor
            addSubview(field)
        }

        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        shortcutField.alignment = .right
        shortcutField.lineBreakMode = .byClipping
        shortcutField.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: StatusMenuMetrics.rowHeight),
            widthAnchor.constraint(equalToConstant: StatusMenuMetrics.width - (StatusMenuMetrics.padding * 2)),

            titleField.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: StatusMenuMetrics.rowSpacing),
            shortcutField.trailingAnchor.constraint(equalTo: trailingAnchor),
            shortcutField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
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
