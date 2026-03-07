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

    var onArm: () -> Void

    private var isListening = false

    init(onArm: @escaping () -> Void) {
        self.onArm = onArm
    }

    func handleKeyDown() -> Bool {
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
            MainActor.assumeIsolated {
                NSLog("HotkeyService: shortcut fired via KeyboardShortcuts")
                _ = self?.handleKeyDown()
            }
        }

        isListening = true
        NSLog("HotkeyService: listening via KeyboardShortcuts (Carbon hot key, no Accessibility required)")
    }

    func stop() {
        KeyboardShortcuts.disable(.activate)
        isListening = false
    }
}
