import AppKit
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

        if tapMode == .single {
            pendingTapWork?.cancel()
            pendingTapWork = nil
            lastTapTime = nil
            onArm()
            return true
        }

        let currentTime = now()
        if let lastTapTime, currentTime - lastTapTime <= doubleTapWindow {
            pendingTapWork?.cancel()
            pendingTapWork = nil
            self.lastTapTime = nil
            onArm()
            return true
        }

        pendingTapWork?.cancel()
        self.lastTapTime = currentTime

        let discardWork = DispatchWorkItem { [weak self] in
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

        guard CGPreflightListenEventAccess() else {
            NSLog("HotkeyService could not start because keyboard monitoring permission is unavailable.")
            return
        }

        let retainedSelf = Unmanaged.passRetained(self)
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: retainedSelf.toOpaque()
        ) else {
            retainedSelf.release()
            NSLog("HotkeyService failed to create a CGEventTap.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        retainedSelfPointer = retainedSelf.toOpaque()

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
        guard
            let shortcut = KeyboardShortcuts.getShortcut(for: .activate),
            let event = NSEvent(cgEvent: event),
            let eventShortcut = KeyboardShortcuts.Shortcut(event: event)
        else {
            return false
        }

        return eventShortcut == shortcut
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

        let shouldConsume = MainActor.assumeIsolated {
            service.matchesConfiguredShortcut(event: event)
        }

        guard shouldConsume else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = service.handleKeyDown()
            }
        }

        return nil
    }
}
