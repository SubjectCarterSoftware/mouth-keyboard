import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let activate = Self("activate", default: .init(.v, modifiers: [.control]))
}

@MainActor
final class HotkeyService {
    static let shared = HotkeyService(
        onArm: { ActivationStore.shared.arm() }
    )

    let doubleTapWindow: CFAbsoluteTime

    var now: () -> CFAbsoluteTime
    var onArm: () -> Void

    private let tapModeOverride: TapMode?
    private var lastTapTime: CFAbsoluteTime?
    private var pendingTapWork: DispatchWorkItem?
    private var isListening = false

    init(
        doubleTapWindow: CFAbsoluteTime = 0.500,
        onArm: @escaping () -> Void,
        now: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent,
        tapModeOverride: TapMode? = nil
    ) {
        self.doubleTapWindow = doubleTapWindow
        self.onArm = onArm
        self.now = now
        self.tapModeOverride = tapModeOverride
    }

    private var effectiveTapMode: TapMode {
        if let tapModeOverride { return tapModeOverride }
        // Auto-detect: single key (no modifiers) → double-tap to avoid accidental triggers.
        // Multi-key combo (has modifiers) → single-tap since the combo itself prevents accidents.
        if let shortcut = KeyboardShortcuts.getShortcut(for: .activate),
           !shortcut.modifiers.isEmpty {
            return .single
        }
        return .double
    }

    func handleKeyDown() -> Bool {
        let tapMode = effectiveTapMode
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

    /// Register with KeyboardShortcuts using the Carbon hot key API.
    /// No Accessibility permission required — unlike CGEventTap.
    func start() {
        guard !isListening else { return }

        KeyboardShortcuts.onKeyDown(for: .activate) { [weak self] in
            MainActor.assumeIsolated {
                NSLog("HotkeyService: shortcut fired via KeyboardShortcuts")
                _ = self?.handleKeyDown()
            }
        }

        isListening = true
        NSLog("HotkeyService: listening via KeyboardShortcuts (Carbon hot key, no Accessibility required)")
    }

    func stop() {
        pendingTapWork?.cancel()
        pendingTapWork = nil
        lastTapTime = nil

        KeyboardShortcuts.disable(.activate)
        isListening = false
    }
}
