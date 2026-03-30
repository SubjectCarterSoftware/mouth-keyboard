import CoreGraphics
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let activate = Self("activate", default: .init(.v, modifiers: [.control]))
    static let stopSession = Self("stopSession", default: .init(.v, modifiers: [.control]))
    static let cancelSession = Self("cancelSession", default: .init(.v, modifiers: [.control, .shift]))
    static let activateAlt = Self("activateAlt")
    static let stopSessionAlt = Self("stopSessionAlt")
}

@MainActor
final class HotkeyService {
    static let shared = HotkeyService(
        currentState: { ActivationStore.shared.state },
        onArm: { ActivationStore.shared.arm() },
        onStop: { ActivationStore.shared.finish() },
        onCancel: { ActivationStore.shared.cancelCurrentSession() },
        onBeginHold: { ActivationStore.shared.beginHoldSession() },
        onFinishHold: { ActivationStore.shared.finishHoldSession() }
    )

    let minimumActivationInterval: CFAbsoluteTime

    var currentState: () -> RecordingState
    var now: () -> CFAbsoluteTime
    var onArm: () -> Void
    var onStop: () -> Void
    var onCancel: () -> Void
    var onBeginHold: () -> Bool
    var onFinishHold: () -> Void

    private let holdMonitor: HoldToTranscribeMonitor

    private var isListening = false
    private var lastActivationTime: CFAbsoluteTime?
    private var lastHandledKeypressTime: CFAbsoluteTime = 0
    private var isHoldKeyDown = false
    private var hasActiveHoldSession = false
    private var isHoldInteractionInvalidated = false

    init(
        minimumActivationInterval: CFAbsoluteTime = 0.35,
        currentState: @escaping () -> RecordingState,
        onArm: @escaping () -> Void,
        onStop: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        onBeginHold: @escaping () -> Bool = { false },
        onFinishHold: @escaping () -> Void = {},
        now: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent,
        holdMonitor: HoldToTranscribeMonitor = HoldToTranscribeMonitor()
    ) {
        self.minimumActivationInterval = minimumActivationInterval
        self.currentState = currentState
        self.onArm = onArm
        self.onStop = onStop
        self.onCancel = onCancel
        self.onBeginHold = onBeginHold
        self.onFinishHold = onFinishHold
        self.now = now
        self.holdMonitor = holdMonitor
        self.holdMonitor.onHoldKeyPressed = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleHoldKeyStateChange(isPressed: true)
            }
        }
        self.holdMonitor.onHoldKeyReleased = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleHoldKeyStateChange(isPressed: false)
            }
        }
        self.holdMonitor.onInterferingKeyDown = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleInterferingKeyDown()
            }
        }
    }

    func handleKeyDown() -> Bool {
        let currentTime = now()
        if currentState() != .recording,
           let lastActivationTime,
           currentTime - lastActivationTime < minimumActivationInterval {
            NSLog("HotkeyService: ignoring repeat activation within \(minimumActivationInterval)s")
            return true
        }

        lastActivationTime = currentTime
        NSLog("HotkeyService: handleKeyDown singleTap=true")
        NSLog("HotkeyService: single-tap → arm()")
        onArm()
        return true
    }

    func handleHoldKeyStateChange(isPressed: Bool) {
        if isPressed {
            guard !isHoldKeyDown else { return }

            isHoldKeyDown = true
            hasActiveHoldSession = false
            isHoldInteractionInvalidated = false

            if onBeginHold() {
                hasActiveHoldSession = true
                NSLog("HotkeyService: hold activation → beginHoldSession()")
            } else {
                NSLog("HotkeyService: hold activation ignored for current state")
            }
            return
        }

        guard isHoldKeyDown else { return }
        defer { clearHoldInteractionState() }

        guard hasActiveHoldSession, !isHoldInteractionInvalidated else { return }

        NSLog("HotkeyService: hold release → finishHoldSession()")
        onFinishHold()
    }

    func handleInterferingKeyDown() {
        guard isHoldKeyDown else { return }

        guard hasActiveHoldSession else {
            isHoldInteractionInvalidated = true
            return
        }

        NSLog("HotkeyService: cancelling hold session because another key was pressed")
        isHoldInteractionInvalidated = true
        hasActiveHoldSession = false
        onCancel()
    }

    /// Register with KeyboardShortcuts using the Carbon hot key API.
    /// No Accessibility permission required — unlike CGEventTap.
    func start() {
        if !isListening {
            KeyboardShortcuts.onKeyDown(for: .activate) { [weak self] in
                let fireTime = CFAbsoluteTimeGetCurrent()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard fireTime - self.lastHandledKeypressTime > 0.05 else { return }
                    guard self.currentState() != .recording else { return }
                    self.lastHandledKeypressTime = fireTime
                    NSLog("HotkeyService: start shortcut fired via KeyboardShortcuts")
                    _ = self.handleKeyDown()
                }
            }

            KeyboardShortcuts.onKeyDown(for: .activateAlt) { [weak self] in
                let fireTime = CFAbsoluteTimeGetCurrent()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard fireTime - self.lastHandledKeypressTime > 0.05 else { return }
                    guard self.currentState() != .recording else { return }
                    self.lastHandledKeypressTime = fireTime
                    NSLog("HotkeyService: start (alt) shortcut fired via KeyboardShortcuts")
                    _ = self.handleKeyDown()
                }
            }

            KeyboardShortcuts.onKeyDown(for: .stopSession) { [weak self] in
                let fireTime = CFAbsoluteTimeGetCurrent()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard fireTime - self.lastHandledKeypressTime > 0.05 else { return }
                    guard self.currentState() == .recording else { return }
                    self.lastHandledKeypressTime = fireTime
                    NSLog("HotkeyService: stop shortcut fired via KeyboardShortcuts")
                    self.onStop()
                }
            }

            KeyboardShortcuts.onKeyDown(for: .stopSessionAlt) { [weak self] in
                let fireTime = CFAbsoluteTimeGetCurrent()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard fireTime - self.lastHandledKeypressTime > 0.05 else { return }
                    guard self.currentState() == .recording else { return }
                    self.lastHandledKeypressTime = fireTime
                    NSLog("HotkeyService: stop (alt) shortcut fired via KeyboardShortcuts")
                    self.onStop()
                }
            }

            KeyboardShortcuts.onKeyDown(for: .cancelSession) { [weak self] in
                Task { @MainActor [weak self] in
                    NSLog("HotkeyService: cancel shortcut fired via KeyboardShortcuts")
                    self?.onCancel()
                }
            }

            isListening = true
            NSLog("HotkeyService: listening via KeyboardShortcuts (Carbon hot key, no Accessibility required)")
        }

        configureHoldTarget()
        _ = holdMonitor.start()
    }

    func configureHoldTarget() {
        let prefs = ShellPreferences.shared
        holdMonitor.updateTarget(keyCode: prefs.holdShortcutKeyCode, modifiers: prefs.holdShortcutModifiers)
        if prefs.holdShortcutKeyCodeAlt >= 0 {
            holdMonitor.updateSecondaryTarget(keyCode: prefs.holdShortcutKeyCodeAlt, modifiers: prefs.holdShortcutModifiersAlt)
        } else {
            holdMonitor.clearSecondaryTarget()
        }
    }

    func configureHoldTarget(keyCode: Int, modifiers: UInt) {
        holdMonitor.updateTarget(keyCode: keyCode, modifiers: modifiers)
    }

    func stop() {
        KeyboardShortcuts.disable(.activate, .activateAlt)
        KeyboardShortcuts.disable(.stopSession, .stopSessionAlt)
        KeyboardShortcuts.disable(.cancelSession)
        holdMonitor.stop()
        clearHoldInteractionState()
        lastActivationTime = nil
        isListening = false
    }

    private func clearHoldInteractionState() {
        isHoldKeyDown = false
        hasActiveHoldSession = false
        isHoldInteractionInvalidated = false
    }
}

final class HoldToTranscribeMonitor {
    var onHoldKeyPressed: (() -> Void)?
    var onHoldKeyReleased: (() -> Void)?
    var onInterferingKeyDown: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHoldKeyDown = false

    // Configurable target key
    private var targetKeyCode: Int64 = 61
    private var targetIsModifier: Bool = true
    private var targetModifierFlag: CGEventFlags = .maskAlternate
    private var requiredModifiers: CGEventFlags = []

    // Optional secondary target key
    private var hasSecondaryTarget = false
    private var secondaryKeyCode: Int64 = -1
    private var secondaryIsModifier: Bool = false
    private var secondaryModifierFlag: CGEventFlags = []
    private var secondaryRequiredModifiers: CGEventFlags = []

    private static let modifierKeyCodes: Set<Int64> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static func modifierFlag(for keyCode: Int64) -> CGEventFlags {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return []
        }
    }

    static func isAutoRepeatKeyDownEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    }

    func updateTarget(keyCode: Int, modifiers: UInt) {
        let code = Int64(keyCode)
        targetKeyCode = code
        targetIsModifier = Self.modifierKeyCodes.contains(code)
        targetModifierFlag = targetIsModifier ? Self.modifierFlag(for: code) : []

        // NSEvent.ModifierFlags and CGEventFlags share the same bit layout for standard modifiers
        var cgFlags: CGEventFlags = []
        if modifiers & (1 << 20) != 0 { cgFlags.insert(.maskCommand) }   // .command
        if modifiers & (1 << 17) != 0 { cgFlags.insert(.maskShift) }     // .shift
        if modifiers & (1 << 19) != 0 { cgFlags.insert(.maskAlternate) } // .option
        if modifiers & (1 << 18) != 0 { cgFlags.insert(.maskControl) }   // .control
        requiredModifiers = cgFlags

        if isHoldKeyDown {
            isHoldKeyDown = false
        }
    }

    func updateSecondaryTarget(keyCode: Int, modifiers: UInt) {
        let code = Int64(keyCode)
        secondaryKeyCode = code
        secondaryIsModifier = Self.modifierKeyCodes.contains(code)
        secondaryModifierFlag = secondaryIsModifier ? Self.modifierFlag(for: code) : []

        var cgFlags: CGEventFlags = []
        if modifiers & (1 << 20) != 0 { cgFlags.insert(.maskCommand) }
        if modifiers & (1 << 17) != 0 { cgFlags.insert(.maskShift) }
        if modifiers & (1 << 19) != 0 { cgFlags.insert(.maskAlternate) }
        if modifiers & (1 << 18) != 0 { cgFlags.insert(.maskControl) }
        secondaryRequiredModifiers = cgFlags
        hasSecondaryTarget = true

        if isHoldKeyDown {
            isHoldKeyDown = false
        }
    }

    func clearSecondaryTarget() {
        hasSecondaryTarget = false
        secondaryKeyCode = -1
        secondaryIsModifier = false
        secondaryModifierFlag = []
        secondaryRequiredModifiers = []

        if isHoldKeyDown {
            isHoldKeyDown = false
        }
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventsOfInterest =
            Self.mask(for: .flagsChanged)
            | Self.mask(for: .keyDown)
            | Self.mask(for: .keyUp)
            | Self.mask(for: .tapDisabledByTimeout)
            | Self.mask(for: .tapDisabledByUserInput)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventsOfInterest,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<HoldToTranscribeMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("HotkeyService: hold monitor unavailable (Listen Events permission missing or tap creation failed)")
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("HotkeyService: hold monitor listening for hold-to-transcribe key (keyCode=\(targetKeyCode))")
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        isHoldKeyDown = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

        case .flagsChanged:
            let isAnyModifierTarget = targetIsModifier || (hasSecondaryTarget && secondaryIsModifier)
            if isAnyModifierTarget {
                handleModifierTargetFlagsChanged(event)
            }
            // Check if modifiers released for a regular-key target being held
            if isHoldKeyDown {
                if !targetIsModifier && !requiredModifiers.isEmpty && !event.flags.contains(requiredModifiers) {
                    isHoldKeyDown = false
                    onHoldKeyReleased?()
                } else if hasSecondaryTarget && !secondaryIsModifier && !secondaryRequiredModifiers.isEmpty && !event.flags.contains(secondaryRequiredModifiers) {
                    isHoldKeyDown = false
                    onHoldKeyReleased?()
                }
            }

        case .keyDown:
            if Self.isAutoRepeatKeyDownEvent(event) {
                break
            }

            let isAnyModifierTarget = targetIsModifier && (!hasSecondaryTarget || secondaryIsModifier)
            if isAnyModifierTarget {
                if isHoldKeyDown {
                    onInterferingKeyDown?()
                }
            } else {
                handleRegularTargetKeyDown(event)
            }

        case .keyUp:
            if !targetIsModifier || (hasSecondaryTarget && !secondaryIsModifier) {
                handleRegularTargetKeyUp(event)
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleModifierTargetFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Check primary modifier target
        if targetIsModifier && keyCode == targetKeyCode {
            let isPressed = event.flags.contains(targetModifierFlag)
            if isPressed != isHoldKeyDown {
                isHoldKeyDown = isPressed
                if isPressed { onHoldKeyPressed?() } else { onHoldKeyReleased?() }
            }
            return
        }

        // Check secondary modifier target
        if hasSecondaryTarget && secondaryIsModifier && keyCode == secondaryKeyCode {
            let isPressed = event.flags.contains(secondaryModifierFlag)
            if isPressed != isHoldKeyDown {
                isHoldKeyDown = isPressed
                if isPressed { onHoldKeyPressed?() } else { onHoldKeyReleased?() }
            }
        }
    }

    private func handleRegularTargetKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let matchesPrimary = !targetIsModifier && keyCode == targetKeyCode
            && (requiredModifiers.isEmpty || event.flags.contains(requiredModifiers))
        let matchesSecondary = hasSecondaryTarget && !secondaryIsModifier && keyCode == secondaryKeyCode
            && (secondaryRequiredModifiers.isEmpty || event.flags.contains(secondaryRequiredModifiers))

        if matchesPrimary || matchesSecondary {
            if !isHoldKeyDown {
                isHoldKeyDown = true
                onHoldKeyPressed?()
            }
        } else if isHoldKeyDown {
            onInterferingKeyDown?()
        }
    }

    private func handleRegularTargetKeyUp(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let matchesPrimary = !targetIsModifier && keyCode == targetKeyCode
        let matchesSecondary = hasSecondaryTarget && !secondaryIsModifier && keyCode == secondaryKeyCode
        if (matchesPrimary || matchesSecondary) && isHoldKeyDown {
            isHoldKeyDown = false
            onHoldKeyReleased?()
        }
    }

    private static func mask(for eventType: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(eventType.rawValue)
    }
}
