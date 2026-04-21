import AppKit
import KeyboardShortcuts

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let preferences: ShellPreferences
    private let readinessStore: ReadinessStore
    private let audioDeviceService: AudioDeviceService
    private let activationStore: ActivationStore
    private let openSetup: () -> Void
    private let quitApp: () -> Void

    private let menu = NSMenu()
    private var statusItem: NSStatusItem?

    init(
        preferences: ShellPreferences,
        readinessStore: ReadinessStore,
        audioDeviceService: AudioDeviceService,
        activationStore: ActivationStore,
        openSetup: @escaping () -> Void,
        quitApp: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.readinessStore = readinessStore
        self.audioDeviceService = audioDeviceService
        self.activationStore = activationStore
        self.openSetup = openSetup
        self.quitApp = quitApp
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

    func install() {
        guard statusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
        self.statusItem = statusItem
        updateIcon(for: activationStore.state)
    }

    func updateIcon(for state: RecordingState) {
        let tint: NSColor?
        let description: String

        switch state {
        case .idle:
            tint = nil
            description = "Speech2Text"
        case .recording:
            tint = .systemRed
            description = "Recording"
        case .processing:
            tint = NSColor(red: 0.102, green: 0.431, blue: 1.0, alpha: 1.0)
            description = "Processing"
        case .modelDownloading:
            tint = NSColor(red: 0.102, green: 0.431, blue: 1.0, alpha: 1.0)
            description = "Downloading model"
        case .converting:
            tint = NSColor(red: 0.545, green: 0.184, blue: 0.788, alpha: 1.0)
            description = "Converting"
        case .success:
            tint = .systemGreen
            description = "Transcribed"
        case .failure:
            tint = .systemRed
            description = "Failed"
        }

        statusItem?.button?.image = menuBarWaveform(tint: tint, accessibilityDescription: description)
        statusItem?.button?.toolTip = description
    }

    private func menuBarWaveform(tint: NSColor?, accessibilityDescription: String) -> NSImage? {
        let baseConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        if let tint {
            let config = baseConfig.applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: accessibilityDescription)?
                .withSymbolConfiguration(config)
            image?.isTemplate = false
            return image
        } else {
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: accessibilityDescription)?
                .withSymbolConfiguration(baseConfig)
            image?.isTemplate = true
            return image
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private var recordingState: RecordingState {
        activationStore.state
    }

    private var canCancelSession: Bool {
        recordingState == .recording
            || recordingState == .processing
            || recordingState.isModelDownloading
            || recordingState == .converting
    }

    private var canFinishSession: Bool {
        recordingState == .recording
    }

    private var canStartSession: Bool {
        recordingState == .idle || recordingState.isTerminal
    }

    private var needsSetup: Bool {
        readinessStore.snapshot.state != .ready
    }

    private var primaryHoldShortcutText: String {
        guard preferences.holdShortcutKeyCode >= 0 else {
            return "Not set"
        }

        return HoldKeyDisplayFormatter.symbol(
            keyCode: preferences.holdShortcutKeyCode,
            modifiers: preferences.holdShortcutModifiers
        )
    }

    private func rebuildMenu() {
        readinessStore.refresh()
        if !needsSetup {
            audioDeviceService.refresh()
        }

        menu.removeAllItems()

        if needsSetup {
            let setupItem = actionItem(
                title: "Setup Required",
                action: #selector(openSetupFromMenu),
                shortcut: KeyboardShortcuts.Shortcut(.comma, modifiers: [.command]),
                enabled: true
            )
            setupItem.image = NSImage(
                systemSymbolName: "exclamationmark.circle.fill",
                accessibilityDescription: "Setup Required"
            )
            menu.addItem(setupItem)
        } else {
            if canFinishSession {
                menu.addItem(
                    actionItem(
                        title: "Stop Transcription",
                        action: #selector(finishRecordingFromMenu),
                        shortcut: KeyboardShortcuts.getShortcut(for: .stopSession),
                        enabled: true,
                        symbolNames: ["stop.circle"]
                    )
                )
            } else {
                menu.addItem(
                    actionItem(
                        title: "Start Transcription",
                        action: #selector(startRecordingFromMenu),
                        shortcut: KeyboardShortcuts.getShortcut(for: .activate),
                        enabled: canStartSession,
                        symbolNames: ["record.circle"]
                    )
                )
            }

            menu.addItem(.separator())

            menu.addItem(
                actionItem(
                    title: "Copy Last AI Converted Transcription",
                    action: #selector(copyLastConvertedTranscriptionFromMenu),
                    enabled: activationStore.lastConvertedTranscription != nil,
                    symbolNames: ["sparkles", "wand.and.stars"]
                )
            )
            menu.addItem(
                actionItem(
                    title: "Copy Last Transcription",
                    action: #selector(copyLastTranscriptionFromMenu),
                    enabled: activationStore.lastTranscription != nil,
                    symbolNames: ["doc.on.doc", "doc.on.clipboard"]
                )
            )
            menu.addItem(toggleItem(
                title: "Auto Paste",
                action: #selector(toggleAutoPasteFromMenu),
                isOn: preferences.alwaysAutoPaste,
                enabled: !canCancelSession,
                symbolNames: ["text.insert", "arrow.right.doc.on.clipboard"]
            ))
            menu.addItem(toggleItem(
                title: "Clipboard Access",
                action: #selector(toggleClipboardAccessFromMenu),
                isOn: preferences.allowClipboardAccess,
                enabled: !canCancelSession,
                symbolNames: ["list.clipboard", "doc.on.clipboard"]
            ))
            menu.addItem(.separator())
            menu.addItem(microphoneMenuItem())
            menu.addItem(
                actionItem(
                    title: "Settings & Hotkeys…",
                    action: #selector(openSetupFromMenu),
                    shortcut: KeyboardShortcuts.Shortcut(.comma, modifiers: [.command]),
                    enabled: true,
                    symbolNames: ["gearshape", "gear"]
                )
            )
        }

        menu.addItem(.separator())
        menu.addItem(
            actionItem(
                title: "Quit Speech-to-Text",
                action: #selector(quitFromMenu),
                shortcut: KeyboardShortcuts.Shortcut(.q, modifiers: [.command]),
                enabled: true,
                symbolNames: ["power", "xmark.circle"]
            )
        )
    }

    private func actionItem(
        title: String,
        action: Selector,
        shortcut: KeyboardShortcuts.Shortcut? = nil,
        enabled: Bool,
        symbolNames: [String] = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        item.image = menuItemImage(symbolNames: symbolNames, accessibilityDescription: title)

        if let shortcut {
            item.keyEquivalent = shortcut.menuKeyEquivalent ?? ""
            item.keyEquivalentModifierMask = shortcut.modifiers
        }

        return item
    }

    private func toggleItem(
        title: String,
        action: Selector,
        isOn: Bool,
        enabled: Bool,
        symbolNames: [String] = []
    ) -> NSMenuItem {
        let item = actionItem(
            title: title,
            action: action,
            enabled: enabled,
            symbolNames: symbolNames
        )
        item.state = isOn ? .on : .off
        return item
    }

    private func microphoneMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        item.isEnabled = !canCancelSession
        item.image = menuItemImage(
            symbolNames: ["mic", "mic.fill"],
            accessibilityDescription: "Microphone"
        )

        let submenu = NSMenu(title: "Microphone")
        submenu.autoenablesItems = false

        let systemDefaultItem = NSMenuItem(
            title: "System Default",
            action: #selector(selectSystemDefaultMicFromMenu),
            keyEquivalent: ""
        )
        systemDefaultItem.target = self
        systemDefaultItem.state = preferences.micDeviceUIDs.isEmpty ? .on : .off
        submenu.addItem(systemDefaultItem)

        if !audioDeviceService.availableDevices.isEmpty {
            submenu.addItem(.separator())
            for device in audioDeviceService.availableDevices {
                let deviceItem = NSMenuItem(
                    title: device.name,
                    action: #selector(selectMicDeviceFromMenu(_:)),
                    keyEquivalent: ""
                )
                deviceItem.target = self
                deviceItem.representedObject = device.uid
                deviceItem.state = preferences.micDeviceUIDs.first == device.uid ? .on : .off
                submenu.addItem(deviceItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func passiveShortcutItem(
        title: String,
        shortcutText _: String,
        accessibilityIdentifier _: String,
        symbolNames: [String] = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = menuItemImage(symbolNames: symbolNames, accessibilityDescription: title)

        if let shortcut = primaryHoldMenuShortcut {
            item.keyEquivalent = shortcut.keyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifiers
        }

        return item
    }

    private func menuItemImage(symbolNames: [String], accessibilityDescription: String) -> NSImage? {
        for symbolName in symbolNames {
            guard let image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: accessibilityDescription
            ) else {
                continue
            }

            image.isTemplate = true
            if let configuredImage = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            ) {
                configuredImage.isTemplate = true
                return configuredImage
            }

            return image
        }

        return nil
    }

    private var primaryHoldMenuShortcut: NativeMenuShortcut? {
        nativeMenuShortcut(
            keyCode: preferences.holdShortcutKeyCode,
            modifiers: preferences.holdShortcutModifiers
        )
    }

    private func nativeMenuShortcut(keyCode: Int, modifiers: UInt) -> NativeMenuShortcut? {
        switch keyCode {
        case 54, 55:
            return NativeMenuShortcut(keyEquivalent: "⌘", modifiers: [])
        case 56, 60:
            return NativeMenuShortcut(keyEquivalent: "⇧", modifiers: [])
        case 58, 61:
            return NativeMenuShortcut(keyEquivalent: "⌥", modifiers: [])
        case 59, 62:
            return NativeMenuShortcut(keyEquivalent: "⌃", modifiers: [])
        case 63:
            return NativeMenuShortcut(keyEquivalent: "fn", modifiers: [])
        default:
            guard let keyEquivalent = menuKeyEquivalent(forHoldKeyCode: keyCode) else {
                return nil
            }

            return NativeMenuShortcut(
                keyEquivalent: keyEquivalent,
                modifiers: NSEvent.ModifierFlags(rawValue: modifiers)
            )
        }
    }

    private func menuKeyEquivalent(forHoldKeyCode keyCode: Int) -> String? {
        switch keyCode {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "o"
        case 32: return "u"
        case 33: return "["
        case 34: return "i"
        case 35: return "p"
        case 36: return String(Character(UnicodeScalar(NSCarriageReturnCharacter)!))
        case 37: return "l"
        case 38: return "j"
        case 39: return "'"
        case 40: return "k"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "n"
        case 46: return "m"
        case 47: return "."
        case 48: return String(Character(UnicodeScalar(NSTabCharacter)!))
        case 49: return " "
        case 50: return "`"
        case 51: return String(Character(UnicodeScalar(NSDeleteCharacter)!))
        case 53: return String(Character(UnicodeScalar(0x1B)!))
        case 123: return functionKeyEquivalent(NSLeftArrowFunctionKey)
        case 124: return functionKeyEquivalent(NSRightArrowFunctionKey)
        case 125: return functionKeyEquivalent(NSDownArrowFunctionKey)
        case 126: return functionKeyEquivalent(NSUpArrowFunctionKey)
        default: return nil
        }
    }

    @objc
    private func openSetupFromMenu() {
        openSetup()
    }

    @objc
    private func startRecordingFromMenu() {
        activationStore.arm()
    }

    @objc
    private func finishRecordingFromMenu() {
        activationStore.finish()
    }

    @objc
    private func cancelSessionFromMenu() {
        activationStore.cancelCurrentSession()
    }

    @objc
    private func restartRecordingFromMenu() {
        activationStore.restartCurrentSession()
    }

    @objc
    private func toggleAutoPasteFromMenu() {
        preferences.alwaysAutoPaste.toggle()
    }

    @objc
    private func toggleClipboardAccessFromMenu() {
        preferences.allowClipboardAccess.toggle()
    }

    @objc
    private func selectSystemDefaultMicFromMenu() {
        preferences.micDeviceUIDs = []
    }

    @objc
    private func selectMicDeviceFromMenu(_ sender: NSMenuItem) {
        if let uid = sender.representedObject as? String {
            preferences.promoteMicDevice(uid)
        }
    }

    @objc
    private func copyLastConvertedTranscriptionFromMenu() {
        activationStore.copyLastConvertedTranscription()
    }

    @objc
    private func copyLastTranscriptionFromMenu() {
        activationStore.copyLastTranscription()
    }

    @objc
    private func quitFromMenu() {
        quitApp()
    }
}

private struct NativeMenuShortcut {
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags
}

private func functionKeyEquivalent(_ scalarValue: Int) -> String? {
    guard let scalar = UnicodeScalar(scalarValue) else {
        return nil
    }

    return String(Character(scalar))
}

private extension KeyboardShortcuts.Shortcut {
    var menuKeyEquivalent: String? {
        key?.menuKeyEquivalent
    }
}

private extension KeyboardShortcuts.Key {
    var menuKeyEquivalent: String? {
        switch self {
        case .a: return "a"
        case .b: return "b"
        case .c: return "c"
        case .d: return "d"
        case .e: return "e"
        case .f: return "f"
        case .g: return "g"
        case .h: return "h"
        case .i: return "i"
        case .j: return "j"
        case .k: return "k"
        case .l: return "l"
        case .m: return "m"
        case .n: return "n"
        case .o: return "o"
        case .p: return "p"
        case .q: return "q"
        case .r: return "r"
        case .s: return "s"
        case .t: return "t"
        case .u: return "u"
        case .v: return "v"
        case .w: return "w"
        case .x: return "x"
        case .y: return "y"
        case .z: return "z"
        case .zero: return "0"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .backslash: return "\\"
        case .backtick: return "`"
        case .comma: return ","
        case .equal: return "="
        case .minus: return "-"
        case .period: return "."
        case .quote: return "'"
        case .semicolon: return ";"
        case .slash: return "/"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .space: return " "
        case .tab: return String(Character(UnicodeScalar(NSTabCharacter)!))
        case .return: return String(Character(UnicodeScalar(NSCarriageReturnCharacter)!))
        case .delete: return String(Character(UnicodeScalar(NSDeleteCharacter)!))
        case .deleteForward: return functionKeyEquivalent(NSDeleteFunctionKey)
        case .home: return functionKeyEquivalent(NSHomeFunctionKey)
        case .end: return functionKeyEquivalent(NSEndFunctionKey)
        case .pageUp: return functionKeyEquivalent(NSPageUpFunctionKey)
        case .pageDown: return functionKeyEquivalent(NSPageDownFunctionKey)
        case .upArrow: return functionKeyEquivalent(NSUpArrowFunctionKey)
        case .rightArrow: return functionKeyEquivalent(NSRightArrowFunctionKey)
        case .downArrow: return functionKeyEquivalent(NSDownArrowFunctionKey)
        case .leftArrow: return functionKeyEquivalent(NSLeftArrowFunctionKey)
        case .escape: return String(Character(UnicodeScalar(0x1B)!))
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

    private func functionKeyEquivalent(_ scalarValue: Int) -> String? {
        guard let scalar = UnicodeScalar(scalarValue) else {
            return nil
        }

        return String(Character(scalar))
    }
}
