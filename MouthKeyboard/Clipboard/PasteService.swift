import AppKit
import CoreGraphics

enum PasteOutcome {
    case pasted
    case copiedOnly
}

enum PostEventOutcome {
    case dispatched
    case unavailable
}

protocol PasteServicing {
    func pasteCurrentClipboard() -> PasteOutcome
    func copySelectedTextToClipboard() -> PostEventOutcome
}

struct PasteService: PasteServicing {
    func pasteCurrentClipboard() -> PasteOutcome {
        let outcome = dispatchCommandShortcut(
            virtualKey: 9,
            actionDescription: "paste"
        )
        return outcome == .dispatched ? .pasted : .copiedOnly
    }

    func copySelectedTextToClipboard() -> PostEventOutcome {
        dispatchCommandShortcut(
            virtualKey: 8,
            actionDescription: "copy selected text"
        )
    }

    private func dispatchCommandShortcut(
        virtualKey: CGKeyCode,
        actionDescription: String
    ) -> PostEventOutcome {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logPostEventFailure(
                actionDescription: actionDescription,
                reason: "could not create CGEventSource"
            )
            return .unavailable
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else {
            logPostEventFailure(
                actionDescription: actionDescription,
                reason: "could not create synthetic key events"
            )
            return .unavailable
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .dispatched
    }

    private func logPostEventFailure(actionDescription: String, reason: String) {
        NSLog("MouthKeyboard: Synthetic %@ failure (%@).", actionDescription, reason)
    }
}
