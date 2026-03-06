import AppKit
import ApplicationServices
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let activate = Self("activate", default: .init(.z, modifiers: [.command, .shift]))
}

@MainActor
final class HotkeyService {
    static let shared = HotkeyService(
        preferences: .shared,
        onArm: { ActivationStore.shared.arm() }
    )

    let doubleTapWindow: CFAbsoluteTime

    var now: () -> CFAbsoluteTime
    var onArm: () -> Void

    private let preferences: ShellPreferences
    private var lastTapTime: CFAbsoluteTime?
    private var pendingTapWork: DispatchWorkItem?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelfPointer: UnsafeMutableRawPointer?

    init(
        preferences: ShellPreferences,
        doubleTapWindow: CFAbsoluteTime = 0.350,
        onArm: @escaping () -> Void,
        now: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent
    ) {
        self.preferences = preferences
        self.doubleTapWindow = doubleTapWindow
        self.onArm = onArm
        self.now = now
    }

    func handleKeyDown() -> Bool {
        let tapMode = preferences.tapMode
        NSLog("HotkeyService: handleKeyDown tapMode=\(tapMode)")

        if tapMode == .single {
            pendingTapWork?.cancel()
            pendingTapWork = nil
            lastTapTime = nil
            NSLog("HotkeyService: single-tap → arm()")
            onArm()
            return true
        }

        let currentTime = now()
        if let lastTapTime, currentTime - lastTapTime <= doubleTapWindow {
            pendingTapWork?.cancel()
            pendingTapWork = nil
            self.lastTapTime = nil
            NSLog("HotkeyService: double-tap detected (interval: \(currentTime - lastTapTime)s) → arm()")
            onArm()
            return true
        }

        NSLog("HotkeyService: first tap registered, waiting for second within \(doubleTapWindow)s")
        pendingTapWork?.cancel()
        self.lastTapTime = currentTime

        let discardWork = DispatchWorkItem { [weak self] in
            NSLog("HotkeyService: double-tap window expired, discarding first tap")
            self?.lastTapTime = nil
            self?.pendingTapWork = nil
        }

        pendingTapWork = discardWork
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: discardWork)
        return true
    }

    func start() {
        guard eventTap == nil else {
            return
        }

        // CGEventTap at the session level requires Accessibility permission
        // (AXIsProcessTrusted), NOT Input Monitoring (CGPreflightListenEventAccess).
        let trusted = AXIsProcessTrusted()
        NSLog("HotkeyService: AXIsProcessTrusted() = \(trusted)")
        guard trusted else {
            NSLog("HotkeyService: Accessibility not granted. Grant in System Settings > Privacy & Security > Accessibility. " +
                  "If running from Xcode, you may need to re-grant after each rebuild.")
            return
        }

        let retainedSelf = Unmanaged.passRetained(self)
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // Use .cgSessionEventTap (user-session level) — NOT .cghidEventTap which
        // requires root. The session tap is sufficient for hotkey interception.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: retainedSelf.toOpaque()
        ) else {
            retainedSelf.release()
            NSLog("HotkeyService failed to create a CGEventTap. " +
                  "Ensure Accessibility permission is granted and the app is not sandboxed.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        retainedSelfPointer = retainedSelf.toOpaque()

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("HotkeyService: CGEventTap created and enabled successfully.")
    }

    func stop() {
        pendingTapWork?.cancel()
        pendingTapWork = nil
        lastTapTime = nil

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        if let retainedSelfPointer {
            Unmanaged<HotkeyService>.fromOpaque(retainedSelfPointer).release()
            self.retainedSelfPointer = nil
        }
    }

    private func matchesConfiguredShortcut(event: CGEvent) -> Bool {
        matchesConfiguredShortcutWithDebug(event: event).0
    }

    private func matchesConfiguredShortcutWithDebug(event: CGEvent) -> (Bool, String) {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .activate) else {
            return (false, "no shortcut configured for .activate")
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return (false, "could not create NSEvent from CGEvent")
        }

        guard let eventShortcut = KeyboardShortcuts.Shortcut(event: nsEvent) else {
            return (false, "could not create Shortcut from NSEvent (keyCode=\(nsEvent.keyCode), modifiers=\(nsEvent.modifierFlags.rawValue)). Expected: \(shortcut)")
        }

        if eventShortcut == shortcut {
            return (true, "matched")
        }

        return (false, "shortcut mismatch: got \(eventShortcut), expected \(shortcut)")
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout {
            MainActor.assumeIsolated {
                if let tap = service.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }

            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let (shouldConsume, debugInfo) = MainActor.assumeIsolated {
            service.matchesConfiguredShortcutWithDebug(event: event)
        }

        if !shouldConsume {
            #if DEBUG
            // Log only modifier+key combos (not plain typing) to avoid console spam
            let flags = CGEventFlags(rawValue: event.flags.rawValue)
            let hasModifiers = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
            if hasModifiers {
                NSLog("HotkeyService: key event did not match. \(debugInfo)")
            }
            #endif
            return Unmanaged.passUnretained(event)
        }

        NSLog("HotkeyService: shortcut matched, dispatching handleKeyDown")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = service.handleKeyDown()
            }
        }

        return nil
    }
}
