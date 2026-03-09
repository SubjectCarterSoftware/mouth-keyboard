import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let activate = Self("activate", default: .init(.v, modifiers: [.control]))
    static let cancelSession = Self("cancelSession", default: .init(.v, modifiers: [.control, .shift]))
}

@MainActor
final class HotkeyService {
    static let shared = HotkeyService(
        currentState: { ActivationStore.shared.state },
        onArm: { ActivationStore.shared.arm() },
        onCancel: { ActivationStore.shared.cancelCurrentSession() }
    )

    let minimumActivationInterval: CFAbsoluteTime

    var currentState: () -> RecordingState
    var now: () -> CFAbsoluteTime
    var onArm: () -> Void
    var onCancel: () -> Void

    private var isListening = false
    private var lastActivationTime: CFAbsoluteTime?

    init(
        minimumActivationInterval: CFAbsoluteTime = 0.35,
        currentState: @escaping () -> RecordingState,
        onArm: @escaping () -> Void,
        onCancel: @escaping () -> Void = {},
        now: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent
    ) {
        self.minimumActivationInterval = minimumActivationInterval
        self.currentState = currentState
        self.onArm = onArm
        self.onCancel = onCancel
        self.now = now
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

    /// Register with KeyboardShortcuts using the Carbon hot key API.
    /// No Accessibility permission required — unlike CGEventTap.
    func start() {
        guard !isListening else { return }

        KeyboardShortcuts.onKeyDown(for: .activate) { [weak self] in
            Task { @MainActor [weak self] in
                NSLog("HotkeyService: shortcut fired via KeyboardShortcuts")
                _ = self?.handleKeyDown()
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

    func stop() {
        KeyboardShortcuts.disable(.activate)
        KeyboardShortcuts.disable(.cancelSession)
        lastActivationTime = nil
        isListening = false
    }
}
