import AppKit
import CoreGraphics
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let activate = Self("activate", default: .init(.v, modifiers: [.control]))
    static let stopSession = Self("stopSession", default: .init(.v, modifiers: [.control]))
    static let cancelSession = Self("cancelSession", default: .init(.v, modifiers: [.control, .shift]))
    static let activateAlt = Self("activateAlt")
    static let activateTertiary = Self("activateTertiary")
    static let stopSessionAlt = Self("stopSessionAlt")
    static let stopSessionTertiary = Self("stopSessionTertiary")
}

enum HoldBindingSlot {
    case primary
    case secondary
    case tertiary
}

enum HoldModifierKey: Int, CaseIterable {
    case rightCommand = 54
    case leftCommand = 55
    case leftShift = 56
    case leftOption = 58
    case leftControl = 59
    case rightShift = 60
    case rightOption = 61
    case rightControl = 62
    case fn = 63

    static let relevantNSEventFlags: NSEvent.ModifierFlags = [.command, .option, .shift, .control]

    var cgEventFlag: CGEventFlags {
        switch self {
        case .rightCommand, .leftCommand:
            return .maskCommand
        case .leftShift, .rightShift:
            return .maskShift
        case .leftOption, .rightOption:
            return .maskAlternate
        case .leftControl, .rightControl:
            return .maskControl
        case .fn:
            return .maskSecondaryFn
        }
    }

    var nsEventFlag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand, .leftCommand:
            return .command
        case .leftShift, .rightShift:
            return .shift
        case .leftOption, .rightOption:
            return .option
        case .leftControl, .rightControl:
            return .control
        case .fn:
            return .function
        }
    }

    var displaySymbol: String {
        switch self {
        case .rightCommand, .leftCommand:
            return "⌘"
        case .leftShift, .rightShift:
            return "⇧"
        case .leftOption, .rightOption:
            return "⌥"
        case .leftControl, .rightControl:
            return "⌃"
        case .fn:
            return "fn"
        }
    }

    var displayName: String {
        switch self {
        case .rightCommand:
            return "Right ⌘"
        case .leftCommand:
            return "Left ⌘"
        case .leftShift:
            return "Left ⇧"
        case .leftOption:
            return "Left ⌥"
        case .leftControl:
            return "Left ⌃"
        case .rightShift:
            return "Right ⇧"
        case .rightOption:
            return "Right ⌥"
        case .rightControl:
            return "Right ⌃"
        case .fn:
            return "fn"
        }
    }

    static func contains(_ keyCode: Int) -> Bool {
        Self(rawValue: keyCode) != nil
    }

    static func contains(_ keyCode: Int64) -> Bool {
        Self(rawValue: Int(keyCode)) != nil
    }

    static func cgEventFlag(for keyCode: Int64) -> CGEventFlags {
        Self(rawValue: Int(keyCode))?.cgEventFlag ?? []
    }

    static func nsEventFlag(for keyCode: Int) -> NSEvent.ModifierFlags {
        Self(rawValue: keyCode)?.nsEventFlag ?? []
    }

    static func displaySymbol(for keyCode: Int) -> String? {
        Self(rawValue: keyCode)?.displaySymbol
    }

    static func displayName(for keyCode: Int) -> String? {
        Self(rawValue: keyCode)?.displayName
    }

    static func cgEventFlags(fromStoredModifiers modifiers: UInt) -> CGEventFlags {
        var cgFlags: CGEventFlags = []
        if modifiers & (1 << 20) != 0 { cgFlags.insert(.maskCommand) }
        if modifiers & (1 << 17) != 0 { cgFlags.insert(.maskShift) }
        if modifiers & (1 << 19) != 0 { cgFlags.insert(.maskAlternate) }
        if modifiers & (1 << 18) != 0 { cgFlags.insert(.maskControl) }
        return cgFlags
    }
}

@MainActor
final class HotkeyService {
    static let shared = HotkeyService(
        currentState: { ActivationStore.shared.state },
        isHoldRecordingActive: { ActivationStore.shared.isHoldSessionActive },
        onArm: { ActivationStore.shared.arm() },
        onStop: { ActivationStore.shared.finish() },
        onCancel: { ActivationStore.shared.cancelCurrentSession() },
        onBeginHold: { ActivationStore.shared.beginHoldSession() },
        onFinishHold: { ActivationStore.shared.finishHoldSession() }
    )

    let minimumActivationInterval: CFAbsoluteTime

    var currentState: () -> RecordingState
    var isHoldRecordingActive: () -> Bool
    var now: () -> CFAbsoluteTime
    var onArm: () -> Void
    var onStop: () -> Void
    var onCancel: () -> Void
    var onBeginHold: () -> Bool
    var onFinishHold: () -> Void
    var currentMouseBindings: @MainActor () -> (
        start: MouseButtonBindingSet,
        stop: MouseButtonBindingSet,
        hold: MouseButtonBindingSet
    )

    private let holdMonitor: HoldToTranscribeMonitor
    private let mouseMonitor: MouseButtonShortcutMonitor

    private var isListening = false
    private var lastActivationTime: CFAbsoluteTime?
    private var lastHandledKeypressTime: CFAbsoluteTime = 0
    private var isHoldKeyDown = false
    private var hasActiveHoldSession = false

    init(
        minimumActivationInterval: CFAbsoluteTime = 0.35,
        currentState: @escaping () -> RecordingState,
        isHoldRecordingActive: @escaping () -> Bool = { false },
        onArm: @escaping () -> Void,
        onStop: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        onBeginHold: @escaping () -> Bool = { false },
        onFinishHold: @escaping () -> Void = {},
        currentMouseBindings: @escaping @MainActor () -> (
            start: MouseButtonBindingSet,
            stop: MouseButtonBindingSet,
            hold: MouseButtonBindingSet
        ) = {
            ShortcutBindingPolicy.sanitizedMouseBindings(preferences: .shared)
        },
        now: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent,
        holdMonitor: HoldToTranscribeMonitor = HoldToTranscribeMonitor(),
        mouseMonitor: MouseButtonShortcutMonitor = MouseButtonShortcutMonitor()
    ) {
        self.minimumActivationInterval = minimumActivationInterval
        self.currentState = currentState
        self.isHoldRecordingActive = isHoldRecordingActive
        self.onArm = onArm
        self.onStop = onStop
        self.onCancel = onCancel
        self.onBeginHold = onBeginHold
        self.onFinishHold = onFinishHold
        self.currentMouseBindings = currentMouseBindings
        self.now = now
        self.holdMonitor = holdMonitor
        self.mouseMonitor = mouseMonitor
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
        self.mouseMonitor.onMouseButtonPressed = { [weak self] buttonNumber in
            Task { @MainActor [weak self] in
                self?.handleMouseButtonDown(buttonNumber: buttonNumber)
            }
        }
        self.mouseMonitor.onMouseButtonReleased = { [weak self] buttonNumber in
            Task { @MainActor [weak self] in
                self?.handleMouseButtonUp(buttonNumber: buttonNumber)
            }
        }
    }

    func handleKeyDown() -> Bool {
        let currentTime = now()

        if currentState() == .recording {
            if isHoldRecordingActive() {
                return true
            }

            lastHandledKeypressTime = currentTime
            onStop()
            return true
        }

        if let lastActivationTime,
           currentTime - lastActivationTime < minimumActivationInterval {
            return true
        }

        lastActivationTime = currentTime
        onArm()
        return true
    }

    func handleHoldKeyStateChange(isPressed: Bool) {
        if isPressed {
            guard !isHoldKeyDown else { return }

            isHoldKeyDown = true
            hasActiveHoldSession = false
            lastHandledKeypressTime = now()

            if onBeginHold() {
                hasActiveHoldSession = true
            }
            return
        }

        guard isHoldKeyDown else { return }
        defer { clearHoldInteractionState() }

        guard hasActiveHoldSession else { return }

        onFinishHold()
    }

    @discardableResult
    func handleMouseButtonDown(buttonNumber: Int) -> Bool {
        let currentTime = now()
        let bindings = currentMouseBindings()
        let isStartButton = bindings.start.contains(buttonNumber: buttonNumber)
        let isStopButton = bindings.stop.contains(buttonNumber: buttonNumber)
        let state = currentState()

        if bindings.hold.contains(buttonNumber: buttonNumber) {
            lastHandledKeypressTime = currentTime
            handleHoldKeyStateChange(isPressed: true)
            return true
        }

        if isStopButton && state == .recording {
            lastHandledKeypressTime = currentTime
            onStop()
            return true
        }

        if isStartButton && (state == .idle || state.isTerminal) {
            if let lastActivationTime,
               currentTime - lastActivationTime < minimumActivationInterval {
                return true
            }

            lastActivationTime = currentTime
            onArm()
            return true
        }

        return isStartButton || isStopButton
    }

    @discardableResult
    func handleMouseButtonUp(buttonNumber: Int) -> Bool {
        let bindings = currentMouseBindings()
        guard bindings.hold.contains(buttonNumber: buttonNumber) else {
            return false
        }

        handleHoldKeyStateChange(isPressed: false)
        return true
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
                    self.lastHandledKeypressTime = fireTime
                    _ = self.handleKeyDown()
                }
            }

            KeyboardShortcuts.onKeyDown(for: .activateAlt) { [weak self] in
                let fireTime = CFAbsoluteTimeGetCurrent()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard fireTime - self.lastHandledKeypressTime > 0.05 else { return }
                    self.lastHandledKeypressTime = fireTime
                    _ = self.handleKeyDown()
                }
            }

            KeyboardShortcuts.onKeyDown(for: .activateTertiary) { [weak self] in
                let fireTime = CFAbsoluteTimeGetCurrent()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard fireTime - self.lastHandledKeypressTime > 0.05 else { return }
                    self.lastHandledKeypressTime = fireTime
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
                    self.onStop()
                }
            }

            KeyboardShortcuts.onKeyDown(for: .stopSessionTertiary) { [weak self] in
                let fireTime = CFAbsoluteTimeGetCurrent()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard fireTime - self.lastHandledKeypressTime > 0.05 else { return }
                    guard self.currentState() == .recording else { return }
                    self.lastHandledKeypressTime = fireTime
                    self.onStop()
                }
            }

            KeyboardShortcuts.onKeyDown(for: .cancelSession) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.onCancel()
                }
            }

            isListening = true
        }

        configureHoldTarget()
        configureMouseBindings()
        _ = holdMonitor.start()
        _ = mouseMonitor.start()
    }

    func configureHoldTarget() {
        let prefs = ShellPreferences.shared
        let sanitizedBindings = ShortcutBindingPolicy.sanitizedHoldBindings(preferences: prefs)

        holdMonitor.updateTarget(
            keyCode: sanitizedBindings.primary?.keyCode ?? -1,
            modifiers: sanitizedBindings.primary?.modifiers ?? 0
        )
        if let secondary = sanitizedBindings.secondary {
            holdMonitor.updateSecondaryTarget(keyCode: secondary.keyCode, modifiers: secondary.modifiers)
        } else {
            holdMonitor.clearSecondaryTarget()
        }
        if let tertiary = sanitizedBindings.tertiary {
            holdMonitor.updateTertiaryTarget(keyCode: tertiary.keyCode, modifiers: tertiary.modifiers)
        } else {
            holdMonitor.clearTertiaryTarget()
        }
    }

    func configureHoldTarget(keyCode: Int, modifiers: UInt) {
        holdMonitor.updateTarget(keyCode: keyCode, modifiers: modifiers)
    }

    func configureMouseBindings() {
        let prefs = ShellPreferences.shared
        let sanitizedBindings = ShortcutBindingPolicy.sanitizedMouseBindings(preferences: prefs)
        mouseMonitor.updateBindings(
            start: sanitizedBindings.start,
            stop: sanitizedBindings.stop,
            hold: sanitizedBindings.hold
        )
    }

    func setMouseBindingsEnabled(_ isEnabled: Bool) {
        mouseMonitor.setEnabled(isEnabled)
    }

    func stop() {
        KeyboardShortcuts.disable(.activate, .activateAlt, .activateTertiary)
        KeyboardShortcuts.disable(.stopSession, .stopSessionAlt, .stopSessionTertiary)
        KeyboardShortcuts.disable(.cancelSession)
        holdMonitor.stop()
        mouseMonitor.stop()
        clearHoldInteractionState()
        lastActivationTime = nil
        isListening = false
    }

    private func clearHoldInteractionState() {
        isHoldKeyDown = false
        hasActiveHoldSession = false
    }
}

final class MouseButtonShortcutMonitor {
    var onMouseButtonPressed: ((Int) -> Void)?
    var onMouseButtonReleased: ((Int) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startBindings: MouseButtonBindingSet = .empty
    private var stopBindings: MouseButtonBindingSet = .empty
    private var holdBindings: MouseButtonBindingSet = .empty
    private var isEnabled = true

    func updateBindings(start: MouseButtonBindingSet, stop: MouseButtonBindingSet, hold: MouseButtonBindingSet) {
        startBindings = start
        stopBindings = stop
        holdBindings = hold
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventsOfInterest =
            Self.mask(for: .otherMouseDown)
            | Self.mask(for: .otherMouseUp)
            | Self.mask(for: .tapDisabledByTimeout)
            | Self.mask(for: .tapDisabledByUserInput)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: CGEventTapOptions(rawValue: 0)!,
            eventsOfInterest: eventsOfInterest,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<MouseButtonShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
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

        isEnabled = true
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)

        case .otherMouseDown:
            let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard shouldHandle(buttonNumber: buttonNumber) else {
                return Unmanaged.passUnretained(event)
            }

            onMouseButtonPressed?(buttonNumber)
            return nil

        case .otherMouseUp:
            let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard shouldHandle(buttonNumber: buttonNumber) else {
                return Unmanaged.passUnretained(event)
            }

            onMouseButtonReleased?(buttonNumber)
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func shouldHandle(buttonNumber: Int) -> Bool {
        guard isEnabled else {
            return false
        }

        return startBindings.contains(buttonNumber: buttonNumber)
            || stopBindings.contains(buttonNumber: buttonNumber)
            || holdBindings.contains(buttonNumber: buttonNumber)
    }

    private static func mask(for type: CGEventType) -> CGEventMask {
        1 << type.rawValue
    }
}

final class HoldToTranscribeMonitor {
    var onHoldKeyPressed: (() -> Void)?
    var onHoldKeyReleased: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeHoldOwner: HoldBindingSlot?
    private var pendingModifierRelease: DispatchWorkItem?
    private var pendingModifierReleaseOwner: HoldBindingSlot?
    private static let modifierReleaseDebounce: TimeInterval = 0.15

    private struct HoldBindingTarget {
        let slot: HoldBindingSlot
        var keyCode: Int64
        var isModifier: Bool
        var modifierFlag: CGEventFlags
        var requiredModifiers: CGEventFlags

        init(slot: HoldBindingSlot, keyCode: Int64 = -1, requiredModifiers: CGEventFlags = []) {
            self.slot = slot
            self.keyCode = keyCode
            self.isModifier = HoldModifierKey.contains(keyCode)
            self.modifierFlag = HoldModifierKey.cgEventFlag(for: keyCode)
            self.requiredModifiers = requiredModifiers
        }

        var isConfigured: Bool {
            keyCode >= 0
        }
    }

    private enum HoldBindingEdge {
        case pressed(HoldBindingSlot)
        case released(HoldBindingSlot)
    }

    private var primaryTarget = HoldBindingTarget(slot: .primary, keyCode: 61)
    private var secondaryTarget = HoldBindingTarget(slot: .secondary)
    private var tertiaryTarget = HoldBindingTarget(slot: .tertiary)

    static func isAutoRepeatKeyDownEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    }

    func updateTarget(keyCode: Int, modifiers: UInt) {
        primaryTarget = HoldBindingTarget(
            slot: .primary,
            keyCode: Int64(keyCode),
            requiredModifiers: HoldModifierKey.cgEventFlags(fromStoredModifiers: modifiers)
        )
        resetHoldState()
    }

    func updateSecondaryTarget(keyCode: Int, modifiers: UInt) {
        secondaryTarget = HoldBindingTarget(
            slot: .secondary,
            keyCode: Int64(keyCode),
            requiredModifiers: HoldModifierKey.cgEventFlags(fromStoredModifiers: modifiers)
        )
        resetHoldState()
    }

    func clearSecondaryTarget() {
        secondaryTarget = HoldBindingTarget(slot: .secondary)
        resetHoldState()
    }

    func updateTertiaryTarget(keyCode: Int, modifiers: UInt) {
        tertiaryTarget = HoldBindingTarget(
            slot: .tertiary,
            keyCode: Int64(keyCode),
            requiredModifiers: HoldModifierKey.cgEventFlags(fromStoredModifiers: modifiers)
        )
        resetHoldState()
    }

    func clearTertiaryTarget() {
        tertiaryTarget = HoldBindingTarget(slot: .tertiary)
        resetHoldState()
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
        return true
    }

    func stop() {
        resetHoldState()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

        case .flagsChanged:
            handleFlagsChangedEvent(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: event.flags
            )

        case .keyDown:
            handleKeyDownEvent(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                isAutoRepeat: Self.isAutoRepeatKeyDownEvent(event),
                eventFlags: event.flags
            )

        case .keyUp:
            handleKeyUpEvent(keyCode: event.getIntegerValueField(.keyboardEventKeycode))

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChangedEvent(keyCode: Int64, flags: CGEventFlags) {
        if let edge = modifierEdge(for: primaryTarget, keyCode: keyCode, flags: flags) {
            handleModifierEdge(edge)
            return
        }

        if let edge = modifierEdge(for: secondaryTarget, keyCode: keyCode, flags: flags) {
            handleModifierEdge(edge)
            return
        }

        if let edge = modifierEdge(for: tertiaryTarget, keyCode: keyCode, flags: flags) {
            handleModifierEdge(edge)
            return
        }

        if let owner = activeHoldOwner,
           let ownerTarget = target(for: owner),
           !ownerTarget.isModifier,
           !ownerTarget.requiredModifiers.isEmpty,
           !flags.contains(ownerTarget.requiredModifiers) {
            handle(edge: .released(owner))
        }
    }

    /// Debounce modifier releases to absorb brief flag flicker that some apps
    /// cause (e.g. Secure Input transitions, custom keyboard handling).
    /// Press events are applied immediately; releases are deferred by
    /// ``modifierReleaseDebounce`` so a quick drop-and-restore of the flag
    /// is silently absorbed instead of creating a spurious release→press cycle.
    private func handleModifierEdge(_ edge: HoldBindingEdge) {
        switch edge {
        case .pressed(let slot):
            if pendingModifierReleaseOwner == slot {
                pendingModifierRelease?.cancel()
                pendingModifierRelease = nil
                pendingModifierReleaseOwner = nil
                return
            }
            handle(edge: edge)
        case .released(let slot):
            guard activeHoldOwner == slot else { return }
            pendingModifierRelease?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.pendingModifierReleaseOwner == slot else { return }
                self.pendingModifierReleaseOwner = nil
                self.pendingModifierRelease = nil
                self.handle(edge: edge)
            }
            pendingModifierReleaseOwner = slot
            pendingModifierRelease = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.modifierReleaseDebounce, execute: workItem)
        }
    }

    private func handle(edge: HoldBindingEdge) {
        switch edge {
        case .pressed(let slot):
            guard activeHoldOwner == nil else { return }
            activeHoldOwner = slot
            onHoldKeyPressed?()
        case .released(let slot):
            guard activeHoldOwner == slot else { return }
            activeHoldOwner = nil
            onHoldKeyReleased?()
        }
    }

    private func resetHoldState() {
        pendingModifierRelease?.cancel()
        pendingModifierRelease = nil
        pendingModifierReleaseOwner = nil
        activeHoldOwner = nil
    }

    private func modifierEdge(for target: HoldBindingTarget, keyCode: Int64, flags: CGEventFlags) -> HoldBindingEdge? {
        guard target.isConfigured, target.isModifier, target.keyCode == keyCode else {
            return nil
        }

        return flags.contains(target.modifierFlag) ? .pressed(target.slot) : .released(target.slot)
    }

    func handleModifierFlagsChanged(keyCode: Int64, flags: CGEventFlags) {
        handleFlagsChangedEvent(keyCode: keyCode, flags: flags)
    }

    func handleKeyDownEvent(keyCode: Int64, isAutoRepeat: Bool, eventFlags: CGEventFlags = []) {
        guard !isAutoRepeat else { return }

        if let edge = regularKeyDownEdge(for: primaryTarget, keyCode: keyCode, eventFlags: eventFlags) {
            handle(edge: edge)
            return
        }

        if let edge = regularKeyDownEdge(for: secondaryTarget, keyCode: keyCode, eventFlags: eventFlags) {
            handle(edge: edge)
            return
        }

        if let edge = regularKeyDownEdge(for: tertiaryTarget, keyCode: keyCode, eventFlags: eventFlags) {
            handle(edge: edge)
        }
    }

    private func regularKeyDownEdge(for target: HoldBindingTarget, keyCode: Int64, eventFlags: CGEventFlags) -> HoldBindingEdge? {
        guard target.isConfigured, !target.isModifier, target.keyCode == keyCode else {
            return nil
        }

        guard target.requiredModifiers.isEmpty || eventFlags.contains(target.requiredModifiers) else {
            return nil
        }

        return .pressed(target.slot)
    }

    func handleKeyUpEvent(keyCode: Int64) {
        if let edge = regularKeyUpEdge(for: primaryTarget, keyCode: keyCode) {
            handle(edge: edge)
            return
        }

        if let edge = regularKeyUpEdge(for: secondaryTarget, keyCode: keyCode) {
            handle(edge: edge)
            return
        }

        if let edge = regularKeyUpEdge(for: tertiaryTarget, keyCode: keyCode) {
            handle(edge: edge)
        }
    }

    private func regularKeyUpEdge(for target: HoldBindingTarget, keyCode: Int64) -> HoldBindingEdge? {
        guard target.isConfigured, !target.isModifier, target.keyCode == keyCode else {
            return nil
        }

        return .released(target.slot)
    }

    private func target(for slot: HoldBindingSlot) -> HoldBindingTarget? {
        switch slot {
        case .primary:
            return primaryTarget.isConfigured ? primaryTarget : nil
        case .secondary:
            return secondaryTarget.isConfigured ? secondaryTarget : nil
        case .tertiary:
            return tertiaryTarget.isConfigured ? tertiaryTarget : nil
        }
    }

    private static func mask(for eventType: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(eventType.rawValue)
    }
}
